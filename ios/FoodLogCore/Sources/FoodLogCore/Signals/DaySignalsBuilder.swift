// DaySignalsBuilder.swift
//
// The ONE pure function that turns everything the app already has on disk
// into the `SignalsSnapshot` every gamification rule reads (design D5).
// Pure on purpose: `SignalsInput` is a plain bag of values the app loads
// from its stores (usage history, FoodCache, day-log digests, activity
// cache, provenance, hydration, the Garmin health snapshot, notes, the
// fasting history), so this is unit-tested with literals and never touches
// a store, a clock or the network.
//
// Rules (each tested in DaySignalsBuilderTests):
//   - Entry identity: a day with a cached Garmin digest takes the digest's
//     entries; local usage events logged AFTER the digest was fetched are
//     appended (they are still in the outbox), unless an entry with the
//     same food id lies within +-120 s (never counted twice). Local events
//     from before the fetch are dropped -- the digest is authoritative
//     (the owner may have deleted them in Garmin Connect).
//   - Name/brand/barcode per entry: digest -> FoodCache -> provenance
//     (design D3). An Open Food Facts food's id IS its barcode.
//   - Meal: the usage event's meal, else the digest's, else the clock
//     (`MealTypeDefaulting`, same hours the log screen defaults to).
//   - Water: max(local total, Garmin total); goal from Garmin, else the
//     app's preference (`defaultWaterGoalML`).
//   - Tags: memoised per food id (a food's name does not change).
//   - Window: the last `windowDays` days ending today; only days with any
//     data appear in `days`.
//
// Depends on: DaySignals/ProfileSignals (output types), DayLogDigest,
// ActivityCache (DayActivity), FoodProvenanceStore (FoodProvenance),
// FoodTagger, UsageEvent, Food, DayNote, FastingDay, NutritionDate.
// Depended on by: the app's FeatureHost (builds the snapshot once per
// refresh / confirm and hands it to every GamificationFeature).

import Foundation
import GarminKit

/// A day's cached Garmin water read, as plain numbers.
public struct GarminWaterDay: Sendable, Equatable {
    public var totalML: Double?
    public var goalML: Double?

    public init(totalML: Double?, goalML: Double?) {
        self.totalML = totalML
        self.goalML = goalML
    }
}

/// Everything the builder reads, already loaded from the stores.
public struct SignalsInput: Sendable {
    public var events: [UsageEvent]
    public var foods: [String: Food]
    public var digests: [DayLogDigest]
    public var activityDays: [DayActivity]
    public var provenance: [String: FoodProvenance]
    /// The app's own hydration total per `yyyy-MM-dd`.
    public var localWaterMLByDay: [String: Double]
    public var garminWaterByDay: [String: GarminWaterDay]
    /// The app's water-goal preference, used when Garmin reports no goal.
    public var defaultWaterGoalML: Double?
    /// The LAST weigh-in of each day, kilograms.
    public var weighInKgByDay: [String: Double]
    public var fastingDays: [FastingDay]
    public var notes: [DayNote]
    public var goalStatusByDay: [String: SignalGoalStatus]
    public var profile: ProfileSignals

    public init(
        events: [UsageEvent] = [],
        foods: [String: Food] = [:],
        digests: [DayLogDigest] = [],
        activityDays: [DayActivity] = [],
        provenance: [String: FoodProvenance] = [:],
        localWaterMLByDay: [String: Double] = [:],
        garminWaterByDay: [String: GarminWaterDay] = [:],
        defaultWaterGoalML: Double? = nil,
        weighInKgByDay: [String: Double] = [:],
        fastingDays: [FastingDay] = [],
        notes: [DayNote] = [],
        goalStatusByDay: [String: SignalGoalStatus] = [:],
        profile: ProfileSignals = ProfileSignals()
    ) {
        self.events = events
        self.foods = foods
        self.digests = digests
        self.activityDays = activityDays
        self.provenance = provenance
        self.localWaterMLByDay = localWaterMLByDay
        self.garminWaterByDay = garminWaterByDay
        self.defaultWaterGoalML = defaultWaterGoalML
        self.weighInKgByDay = weighInKgByDay
        self.fastingDays = fastingDays
        self.notes = notes
        self.goalStatusByDay = goalStatusByDay
        self.profile = profile
    }

    // MARK: - Adapters (so the app does no mapping logic of its own)

    /// The app's own drinks summed per logged calendar day.
    public static func localWaterByDay(_ entries: [HydrationEntry], calendar: Calendar) -> [String: Double] {
        var result: [String: Double] = [:]
        for entry in entries {
            result[NutritionDate.string(from: entry.loggedAt, calendar: calendar), default: 0] += entry.valueInML
        }
        return result
    }

    /// Garmin water per day from the cached health snapshot.
    public static func garminWaterByDay(_ snapshot: GarminHealthSnapshot) -> [String: GarminWaterDay] {
        snapshot.hydrationDays.mapValues { cached in
            GarminWaterDay(totalML: cached.daily.valueInML, goalML: cached.daily.goalInML)
        }
    }

    /// The last weigh-in (by timestamp) of each cached day, in kilograms.
    public static func weighInKgByDay(_ snapshot: GarminHealthSnapshot) -> [String: Double] {
        var result: [String: Double] = [:]
        for (day, cached) in snapshot.weighInDays {
            if let last = cached.weighIns.max(by: { $0.timestampGMT < $1.timestampGMT }) {
                result[day] = last.weightGrams / 1000
            }
        }
        return result
    }
}

public enum DaySignalsBuilder {
    /// Entries of the same food this close together are the same entry.
    public static let duplicateTolerance: TimeInterval = 120

    public static func build(
        input: SignalsInput,
        today: Date,
        windowDays: Int = 42,
        calendar: Calendar
    ) -> SignalsSnapshot {
        var resolver = EntryResolver(input: input, calendar: calendar)

        // Window keys, oldest first.
        let todayStart = calendar.startOfDay(for: today)
        var windowKeys: [String] = []
        var dateByKey: [String: Date] = [:]
        for offset in stride(from: max(windowDays, 1) - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            let key = resolver.dayKey(date)
            if dateByKey[key] == nil {
                windowKeys.append(key)
                dateByKey[key] = date
            }
        }
        let todayKey = resolver.dayKey(today)

        // Group sources by day once.
        var eventsByDay: [String: [UsageEvent]] = [:]
        for event in input.events {
            eventsByDay[resolver.day(of: event), default: []].append(event)
        }
        let digestByDay = Dictionary(input.digests.map { ($0.day, $0) }, uniquingKeysWith: { a, b in
            (a.fetchedAt >= b.fetchedAt) ? a : b
        })
        let activityByDay = Dictionary(input.activityDays.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        var noteTagsByDay: [String: Set<DayNoteTag>] = [:]
        for note in input.notes where !note.tags.isEmpty {
            noteTagsByDay[note.day, default: []].formUnion(note.tags)
        }
        var fastingByDay: [String: FastingOutcome] = [:]
        for fast in input.fastingDays {
            let key = resolver.dayKey(fast.day)
            switch fast.result {
            case .kept: fastingByDay[key] = .kept
            case .broken: fastingByDay[key] = .broken
            case .inProgress, .upcoming, .notTracked: break
            }
        }

        // Days in the window.
        var days: [String: DaySignals] = [:]
        for key in windowKeys {
            guard let date = dateByKey[key] else { continue }
            let entries = resolver.entries(
                day: key,
                digest: digestByDay[key],
                events: eventsByDay[key] ?? []
            )
            let digest = digestByDay[key]
            let totals = Self.totals(entries: entries, digest: digest)

            let localWater = input.localWaterMLByDay[key]
            let garminWater = input.garminWaterByDay[key]
            let waterValues = [localWater, garminWater?.totalML].compactMap { $0 }
            let waterML = waterValues.max()
            let waterGoal = garminWater?.goalML ?? input.defaultWaterGoalML

            let activity = activityByDay[key]
            let activities = (activity?.activities ?? []).sorted { $0.start < $1.start }
            let weighIn = input.weighInKgByDay[key]
            let fasting = fastingByDay[key]
            let noteTags = noteTagsByDay[key] ?? []
            let goalStatus = input.goalStatusByDay[key]

            let hasAnyData = !entries.isEmpty || waterML != nil || activity != nil
                || weighIn != nil || fasting != nil || !noteTags.isEmpty || goalStatus != nil
            guard hasAnyData else { continue }

            let availability = SignalAvailability(
                hasGarminLog: digest != nil,
                hasMacros: !entries.isEmpty && totals.calories != nil && totals.protein != nil
                    && totals.carbs != nil && totals.fat != nil,
                hasWater: waterML != nil,
                hasActivities: activity?.activities != nil,
                hasWeight: weighIn != nil,
                hasFasting: fasting != nil
            )
            days[key] = DaySignals(
                day: key,
                date: date,
                entries: entries,
                totals: totals,
                goals: digest?.goals,
                goalStatus: goalStatus,
                waterML: waterML,
                waterGoalML: waterGoal,
                activeKcal: activity?.activeKcal,
                activities: activities,
                weighInKg: weighIn,
                fasting: fasting,
                noteTags: noteTags,
                availability: availability
            )
        }

        // Lifetime "first seen" facts over the whole retained history.
        var firstSeenFood: [String: String] = [:]
        var firstSeenBrand: [String: String] = [:]
        func see(foodId: String, day: String) {
            if let existing = firstSeenFood[foodId], existing <= day { return }
            firstSeenFood[foodId] = day
        }
        func seeBrand(foodId: String, name: String?, brand: String?, barcode: String?, day: String) {
            guard let brand, !brand.isEmpty else { return }
            let tags = resolver.tags(foodId: foodId, name: name, brand: brand, barcode: barcode)
            guard tags.contains(.czechBrand) else { return }
            let folded = SearchText.foldedPhrase(brand)
            guard !folded.isEmpty else { return }
            if let existing = firstSeenBrand[folded], existing <= day { return }
            firstSeenBrand[folded] = day
        }
        for (day, events) in eventsByDay {
            for event in events {
                see(foodId: event.foodId, day: day)
                let meta = resolver.metadata(foodId: event.foodId, digestName: nil, digestBrand: nil)
                seeBrand(foodId: event.foodId, name: meta.name, brand: meta.brand, barcode: meta.barcode, day: day)
            }
        }
        for digest in digestByDay.values {
            for entry in digest.entries {
                see(foodId: entry.foodId, day: digest.day)
                let meta = resolver.metadata(foodId: entry.foodId, digestName: entry.name, digestBrand: entry.brand)
                seeBrand(foodId: entry.foodId, name: meta.name, brand: meta.brand, barcode: meta.barcode, day: digest.day)
            }
        }

        return SignalsSnapshot(
            days: days,
            today: todayKey,
            windowDays: windowKeys,
            profile: input.profile,
            firstSeenDayByFood: firstSeenFood,
            firstSeenDayByCzechBrand: firstSeenBrand
        )
    }

    /// The digest's totals when nothing was appended; otherwise the digest
    /// totals plus the appended entries (or, with no digest, the sum of the
    /// entries). A macro is `nil` as soon as any contributing value is.
    static func totals(entries: [SignalEntry], digest: DayLogDigest?) -> MacroTotals {
        if digest == nil, entries.isEmpty { return .zero }
        let contributing = entries.filter { digest == nil || !$0.fromGarminLog }
        var totals: MacroTotals = digest?.totals ?? .zero
        for entry in contributing {
            totals.calories = add(totals.calories, entry.calories)
            totals.protein = add(totals.protein, entry.protein)
            totals.carbs = add(totals.carbs, entry.carbs)
            totals.fat = add(totals.fat, entry.fat)
            totals.fiber = add(totals.fiber, entry.fiber)
            totals.sugar = add(totals.sugar, entry.sugar)
        }
        return totals
    }

    private static func add(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return a + b
    }

    static func signalMeal(_ meal: MealType) -> SignalMeal {
        switch meal {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .snacks: return .snack
        }
    }

    static func signalMeal(rawMealType: String?) -> SignalMeal? {
        guard let raw = rawMealType, let meal = MealType(rawValue: raw.uppercased()) else { return nil }
        return signalMeal(meal)
    }
}

/// Per-build resolution state: tag memo and the food/provenance lookups.
private struct EntryResolver {
    let input: SignalsInput
    let calendar: Calendar
    private var tagMemo: [String: Set<FoodTag>] = [:]
    /// One formatter per build: `NutritionDate.string` makes a fresh
    /// `DateFormatter` per call, which dominated the 1,000-event budget.
    /// Same calendar, time zone and format, so the keys are identical.
    private let dayFormatter: DateFormatter

    init(input: SignalsInput, calendar: Calendar) {
        self.input = input
        self.calendar = calendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = formatter
    }

    func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    func day(of event: UsageEvent) -> String {
        event.nutritionDay ?? dayKey(event.timestamp)
    }

    struct Metadata {
        let name: String?
        let brand: String?
        let barcode: String?
    }

    func metadata(foodId: String, digestName: String?, digestBrand: String?) -> Metadata {
        let food = input.foods[foodId]
        let provenance = input.provenance[foodId]
        let name = nonBlank(digestName) ?? nonBlank(food?.name)
        let brand = nonBlank(digestBrand) ?? nonBlank(food?.brandName) ?? nonBlank(provenance?.brand)
        let barcode = nonBlank(provenance?.barcode) ?? (food?.source == .openFoodFacts ? nonBlank(food?.id) : nil)
        return Metadata(name: name, brand: brand, barcode: barcode)
    }

    mutating func tags(foodId: String, name: String?, brand: String?, barcode: String?) -> Set<FoodTag> {
        if let memo = tagMemo[foodId] { return memo }
        let tags = (name == nil && brand == nil && barcode == nil)
            ? []
            : FoodTagger.tags(name: name, brand: brand, barcode: barcode)
        tagMemo[foodId] = tags
        return tags
    }

    mutating func entries(day: String, digest: DayLogDigest?, events: [UsageEvent]) -> [SignalEntry] {
        var result: [SignalEntry] = []
        var localPool = events.sorted { $0.timestamp < $1.timestamp }

        if let digest {
            let noon = dayNoon(day)
            for entry in digest.entries {
                // A digest entry's time: Garmin's, else a same-food local
                // event on this day, else noon (placeholder).
                var timestamp = entry.timestamp
                var localMeal: MealType?
                if let index = matchIndex(in: localPool, foodId: entry.foodId, near: entry.timestamp) {
                    let local = localPool.remove(at: index)
                    if timestamp == nil { timestamp = local.timestamp }
                    localMeal = local.mealType
                }
                let resolvedTime = timestamp ?? noon
                let meal = localMeal.map { DaySignalsBuilder.signalMeal($0) }
                    ?? DaySignalsBuilder.signalMeal(rawMealType: entry.mealType)
                    ?? DaySignalsBuilder.signalMeal(MealTypeDefaulting.defaultMealType(for: resolvedTime, calendar: calendar))
                let meta = metadata(foodId: entry.foodId, digestName: entry.name, digestBrand: entry.brand)
                result.append(SignalEntry(
                    foodId: entry.foodId,
                    name: meta.name,
                    brand: meta.brand,
                    barcode: meta.barcode,
                    tags: tags(foodId: entry.foodId, name: meta.name, brand: meta.brand, barcode: meta.barcode),
                    timestamp: resolvedTime,
                    meal: meal,
                    calories: entry.calories,
                    protein: entry.protein,
                    carbs: entry.carbs,
                    fat: entry.fat,
                    fiber: entry.fiber,
                    sugar: entry.sugar,
                    fromGarminLog: true
                ))
            }
            // Only local events logged after the fetch are still missing
            // from the digest; anything older is either in it or deleted.
            localPool = localPool.filter { $0.timestamp > digest.fetchedAt }
            // ...and still de-duplicated against the digest's entries.
            localPool = localPool.filter { event in
                !result.contains { $0.foodId == event.foodId
                    && abs($0.timestamp.timeIntervalSince(event.timestamp)) <= DaySignalsBuilder.duplicateTolerance }
            }
        }

        for event in localPool {
            result.append(localEntry(event))
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    private func matchIndex(in pool: [UsageEvent], foodId: String, near timestamp: Date?) -> Int? {
        if let timestamp {
            return pool.firstIndex { $0.foodId == foodId
                && abs($0.timestamp.timeIntervalSince(timestamp)) <= DaySignalsBuilder.duplicateTolerance }
        }
        return pool.firstIndex { $0.foodId == foodId }
    }

    private mutating func localEntry(_ event: UsageEvent) -> SignalEntry {
        let food = input.foods[event.foodId]
        let serving = food?.servings.first { $0.id == event.servingId }
        let qty = event.numberOfUnits
        let meta = metadata(foodId: event.foodId, digestName: nil, digestBrand: nil)
        let meal = event.mealType.map { DaySignalsBuilder.signalMeal($0) }
            ?? DaySignalsBuilder.signalMeal(MealTypeDefaulting.defaultMealType(for: event.timestamp, calendar: calendar))
        return SignalEntry(
            foodId: event.foodId,
            name: meta.name,
            brand: meta.brand,
            barcode: meta.barcode,
            tags: tags(foodId: event.foodId, name: meta.name, brand: meta.brand, barcode: meta.barcode),
            timestamp: event.timestamp,
            meal: meal,
            calories: serving?.calories.map { $0 * qty },
            protein: serving?.protein.map { $0 * qty },
            carbs: serving?.carbs.map { $0 * qty },
            fat: serving?.fat.map { $0 * qty },
            fiber: serving?.fiber.map { $0 * qty },
            sugar: serving?.sugar.map { $0 * qty },
            fromGarminLog: false
        )
    }

    private func dayNoon(_ day: String) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        if parts.count == 3 {
            components.year = parts[0]
            components.month = parts[1]
            components.day = parts[2]
        }
        components.hour = 12
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
