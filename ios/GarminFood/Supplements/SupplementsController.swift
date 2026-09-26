// SupplementsController.swift
//
// add-supplements wave 3: the one observable model behind every supplement
// surface -- the Supplements screen, its editors and insights, the Today
// card and the Progress row -- so a tick on the Today card shows on the
// screen at once and the other way round. Owned by AppEnvironment (one per
// process, like WeightLoader).
//
// It holds what the screens read (the plan, the limit overrides, intake
// records for the last 366 days, the training days) and turns every user
// action into one store call (FoodLogCore `Supplements/`), then reloads.
// Everything is local: no action waits on the network (CLAUDE.md,
// "local-first, zero-network-wait"). The rules -- what's due on a day,
// totals, limits, stock, adherence, past-day editability -- all live in
// FoodLogCore and are unit-tested there; this file only calls them.
//
// A failed write is never silent: the store's own message is shown
// (`errorMessage`) and logged to DiagnosticsLog.
//
// After any change, `onDataChanged` runs (AppEnvironment re-plans the
// supplement reminders, so a ticked slot's reminder is removed).
//
// Depends on: FoodLogCore (supplement stores and logic, ActivityCacheStore,
// DayNoteStore), GarminKit (DiagnosticsLog), AppPreferences.
// Depended on by: AppEnvironment, GarminFood/Supplements/*,
// NotificationScheduler (via AppEnvironment.syncNotifications).

import Foundation
import Observation
import FoodLogCore
import GarminKit

@MainActor
@Observable
final class SupplementsController {
    @ObservationIgnored private let planStore: SupplementPlanStore
    @ObservationIgnored private let intakeStore: SupplementIntakeStore
    @ObservationIgnored private let limitsStore: SupplementLimitsStore
    @ObservationIgnored private let activityCache: ActivityCacheStore
    @ObservationIgnored private let dayNotes: DayNoteStore
    @ObservationIgnored private let preferences: AppPreferences

    /// Runs after every change (reminder re-plan).
    @ObservationIgnored var onDataChanged: (() async -> Void)?
    /// add-supplements 5.3: barcode prefill (Open Food Facts, then DSLD),
    /// with its cache -- one instance per process, like every store.
    let barcodeLookup = SupplementBarcodeLookup(cache: SupplementBarcodeCache())

    private(set) var plan = SupplementPlan()
    private(set) var overrides: SupplementLimits.Overrides = [:]
    /// Intake from `earliestDay` through today.
    private(set) var records: [IntakeRecord] = []
    private(set) var trainingDays: Set<String> = []
    private(set) var today: String = NutritionDate.string(from: Date())
    private(set) var hasLoaded = false
    /// A write that failed, in the store's words; shown in an alert.
    var errorMessage: String?

    init(
        planStore: SupplementPlanStore,
        intakeStore: SupplementIntakeStore,
        limitsStore: SupplementLimitsStore,
        activityCache: ActivityCacheStore,
        dayNotes: DayNoteStore,
        preferences: AppPreferences
    ) {
        self.planStore = planStore
        self.intakeStore = intakeStore
        self.limitsStore = limitsStore
        self.activityCache = activityCache
        self.dayNotes = dayNotes
        self.preferences = preferences
    }

    // MARK: - State the screens read

    var isEnabled: Bool { preferences.supplementsEnabled }

    /// Products planned on some day from today on (the "stack").
    var stack: [SupplementProduct] { plan.activeProducts(on: today) }

    /// Products kept but no longer planned (history stays).
    var retired: [SupplementProduct] { plan.inactiveProducts(on: today) }

    /// The Today card and Progress row show only while the feature is on
    /// with at least one product (design D4).
    var isAvailable: Bool { isEnabled && !plan.products.isEmpty }

    /// The oldest day the date picker offers (today − 365 days).
    var earliestDay: String { PastDayLogging.earliestEditableDay(today: today) ?? today }

    func product(_ id: UUID) -> SupplementProduct? { plan.product(id: id) }

    func records(on day: String) -> [IntakeRecord] {
        records.filter { $0.day == day }
    }

    func checklist(on day: String) -> SupplementChecklist {
        SupplementChecklist(day: day, plan: plan, records: records(on: day), trainingDays: trainingDays)
    }

    /// The slot the Today card shows: the next due one by clock time, else
    /// the first not yet done.
    func currentSlot(in checklist: SupplementChecklist, now: Date = Date()) -> TimeSlot? {
        let incomplete = checklist.slots.filter { !checklist.isComplete($0) }
        let preferred = SupplementSlotTimes.preferredSlot(
            among: incomplete,
            atMinute: SupplementSlotTimes.minute(of: now),
            plan: plan
        )
        return checklist.currentSlot(preferring: preferred)
    }

    func totals(on day: String) -> IngredientTotals {
        IngredientTotals.of(day: day, records: records, products: plan.products)
    }

    func warnings(on day: String) -> [LimitWarning] {
        SupplementLimits.warnings(for: totals(on: day), overrides: overrides)
    }

    func effectiveLimit(_ ingredient: IngredientID) -> EffectiveLimit {
        SupplementLimits.effective(for: ingredient, overrides: overrides)
    }

    /// Every ingredient in the stack or taken today, plus every one with an
    /// evidence card, for the limits list.
    var limitIngredients: [IngredientID] {
        var set = Set(EvidenceCatalog.all.map(\.ingredient))
        for product in plan.products {
            for row in product.ingredients { set.insert(row.ingredient) }
        }
        return set.sorted { EvidenceCatalog.name(of: $0).localizedCompare(EvidenceCatalog.name(of: $1)) == .orderedAscending }
    }

    func adherence(lastDays count: Int, productId: UUID?) -> SupplementAdherence {
        let start = SupplementDate.adding(-(count - 1), to: today) ?? today
        return SupplementAdherence.over(
            days: SupplementDate.days(from: start, through: today),
            productId: productId,
            plan: plan,
            records: records,
            trainingDays: trainingDays
        )
    }

    func status(on day: String) -> SupplementDayStatus {
        checklist(on: day).status
    }

    func daysLeft(_ product: SupplementProduct) -> Int? {
        StockProjection.daysLeft(of: product, plan: plan, records: records, today: today, trainingDays: trainingDays)
    }

    func remainingServings(_ product: SupplementProduct) -> Double? {
        StockProjection.remainingServings(of: product, records: records)
    }

    func cost(_ product: SupplementProduct) -> StockProjection.Cost? {
        StockProjection.cost(of: product, plan: plan, today: today, trainingDays: trainingDays)
    }

    /// Servings of `product` planned per day right now (label score dose).
    func plannedServingsPerDay(_ product: SupplementProduct) -> Double {
        StockProjection.plannedServingsPerDay(of: product.id, plan: plan, today: today, trainingDays: trainingDays)
    }

    func labelScore(_ product: SupplementProduct) -> LabelScore {
        let perDay = max(plannedServingsPerDay(product), 1)
        var others = IngredientTotals()
        for other in stack where other.id != product.id {
            others.add(other, servings: plannedServingsPerDay(other))
        }
        return LabelScore.evaluate(product, servingsPerDay: perDay, overrides: overrides, otherIntake: others)
    }

    /// What an extra dose would push over a limit (shown, never blocking).
    func extraDoseNotice(_ product: SupplementProduct, servings: Double, on day: String) -> [LimitWarning] {
        SupplementLimits.extraDoseNotice(adding: product, servings: servings, to: totals(on: day), overrides: overrides)
    }

    func editability(of day: String) -> PastDayLogging.Editability {
        PastDayLogging.editability(of: day, today: today)
    }

    // MARK: - Loading

    func reload(now: Date = Date()) async {
        let today = NutritionDate.string(from: now)
        let earliest = PastDayLogging.earliestEditableDay(today: today) ?? today
        do {
            let plan = try await planStore.plan()
            let overrides = try await limitsStore.overrides()
            let records = try await intakeStore.records(fromDay: earliest, toDay: today)
            let trainingDays = await SupplementTrainingDays.load(
                from: earliest,
                to: today,
                activityCache: activityCache,
                dayNotes: dayNotes,
                mode: preferences.effectiveDataMode
            )
            self.today = today
            self.plan = plan
            self.overrides = overrides
            self.records = records
            self.trainingDays = trainingDays
            hasLoaded = true
        } catch {
            // Unreadable (e.g. before first unlock) or quarantined: keep
            // what's shown and say so; nothing is written.
            report(error, action: "load")
        }
    }

    // MARK: - Ticking (local only)

    func setTaken(_ entry: SupplementChecklist.Entry, taken: Bool, on day: String) async {
        await perform("tick") {
            if taken {
                _ = try await intakeStore.recordPlanned([entry.item], on: day, takenAt: Date(), today: today)
            } else {
                try await intakeStore.removePlanned(productId: entry.item.productId, slot: entry.item.slot, on: day, today: today)
            }
        }
    }

    func takeAll(_ slot: TimeSlot, on day: String) async {
        let open = checklist(on: day).entries(in: slot).filter { !$0.isTaken }.map(\.item)
        guard !open.isEmpty else { return }
        await perform("take all") {
            _ = try await intakeStore.recordPlanned(open, on: day, takenAt: Date(), today: today)
        }
    }

    func addExtra(_ productId: UUID, servings: Double, on day: String) async {
        await perform("extra dose") {
            _ = try await intakeStore.addExtra(productId: productId, servings: servings, on: day, takenAt: Date(), today: today)
        }
    }

    func removeRecord(_ record: IntakeRecord) async {
        await perform("remove dose") {
            try await intakeStore.remove(id: record.id, on: record.day, today: today)
        }
    }

    // MARK: - The stack

    /// Saves a product and, when given, its schedule from today on (past
    /// days keep the schedule they had, design D3).
    func save(_ product: SupplementProduct, schedule: SupplementSchedule?, updateSchedule: Bool) async {
        await perform("save product") {
            try await planStore.upsertProduct(product)
            if updateSchedule {
                try await planStore.setSchedule(schedule, for: product.id, from: today)
            }
        }
    }

    func removeFromStack(_ productId: UUID) async {
        await perform("remove from stack") {
            try await planStore.removeFromStack(productId, from: today)
        }
    }

    func deleteProduct(_ productId: UUID) async {
        await perform("delete product") {
            try await planStore.deleteProduct(productId)
        }
    }

    func setStock(_ productId: UUID, servingsOnHand: Double) async {
        let since = records.filter { $0.productId == productId && $0.day >= today }
        await perform("set stock") {
            try await planStore.setStock(of: productId, servingsOnHand: servingsOnHand, on: today, records: since)
        }
    }

    func refill(_ productId: UUID, packs: Double = 1) async {
        let since = records.filter { $0.productId == productId }
        await perform("refill") {
            try await planStore.refill(productId, packs: packs, on: today, records: since)
        }
    }

    func setReminderMinute(_ minute: Int?, for slot: TimeSlot) async {
        await perform("reminder time") {
            try await planStore.setReminderMinute(minute, for: slot)
        }
    }

    /// A restock reminder was scheduled for the product's current pack.
    func markRestockReminded(_ productId: UUID) async {
        do {
            try await planStore.markRestockReminded(productId)
            plan = try await planStore.plan()
        } catch {
            DiagnosticsLog.log(.warning, category: "Supplements", "couldn't record the restock reminder: \(error.localizedDescription)")
        }
    }

    // MARK: - Limits

    func setLimit(_ override: LimitOverride) async {
        await perform("set limit") {
            try await limitsStore.setOverride(override)
        }
    }

    func resetLimit(_ ingredient: IngredientID) async {
        await perform("reset limit") {
            try await limitsStore.reset(ingredient)
        }
    }

    // MARK: - Reminders

    /// Slot reminders for today and tomorrow (design D5): each slot with
    /// something due and not yet ticked, at the slot's reminder time.
    func plannedSlotReminders(now: Date = Date()) -> [PlannedSupplementReminder] {
        let today = NutritionDate.string(from: now)
        let tomorrow = SupplementDate.adding(1, to: today) ?? today
        return NotificationPlanning.planSupplementSlotReminders(
            isEnabled: isEnabled,
            plan: plan,
            days: [today, tomorrow],
            records: records,
            trainingDays: trainingDays,
            today: today,
            nowMinute: SupplementSlotTimes.minute(of: now)
        )
    }

    func plannedRestockReminders(now: Date = Date()) -> [PlannedSupplementReminder] {
        NotificationPlanning.planSupplementRestockReminders(
            isEnabled: isEnabled,
            plan: plan,
            records: records,
            trainingDays: trainingDays,
            today: NutritionDate.string(from: now)
        )
    }

    // MARK: - Helpers

    private func perform(_ action: String, _ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            report(error, action: action)
        }
        await reload()
        await onDataChanged?()
    }

    private func report(_ error: Error, action: String) {
        DiagnosticsLog.log(.error, category: "Supplements", "\(action) failed: \(error.localizedDescription)")
        errorMessage = error.localizedDescription
    }
}
