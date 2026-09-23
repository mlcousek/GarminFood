// TodayView.swift
//
// The Today tab (meal-dashboard spec): the day as Garmin Connect's food page
// shows it. There's a day switcher and a summary against the daily target,
// then one card per meal with its foods and consumed-vs-suggested calories
// and macros. Queued entries appear in their meal before they reach Garmin.
// Adding from a meal pre-selects that meal and day.
//
// `FastingTodayCard` (2026-09-22) is a compact, conditionally-shown summary
// of the active fast -- same "VStack + SectionHeader, shown only when there's
// something to show" shape `MealPresetShelf`/`QuickPickShelf` already use
// below, placed higher up (right under the streak strip) since the owner
// wants this genuinely checked day to day, not buried under the meal cards.
// Tapping it pushes the full `FastingView` (`GarminFood/Fasting/`).
//
// The "Weight & Water" section (2026-09-22, `TodayWeightHydrationSection.
// swift`) is the last thing in the scroll view, below the meal-preset
// shelf: both trackers already live one tap away on the Progress tab, so
// this is a second, more convenient entry point rather than these screens'
// primary home -- it reads last, after food logging, which is what this
// screen is actually for. Always shown (unlike the quick-pick/meal-preset
// shelves above it, which hide when empty): an empty weight/hydration
// history is itself useful information here ("log your weight to start"),
// and the water card's quick-add row is useful with zero history too.

import SwiftUI
import FoodLogCore
import GarminKit
import Gamification

@MainActor
struct TodayView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Same per-device preference `HydrationView`/`ProgressHomeView` read --
    /// see `HydrationComponents.swift`'s header for why this isn't
    /// Garmin-synced.
    @AppStorage(HydrationPreferenceKeys.dailyGoalML) private var hydrationDailyGoalML: Double = 2000

    @State private var quickPickItems: [QuickPickItem] = []
    @State private var mealPresets: [MealPreset] = []
    @State private var activeFastingSession: FastingSession?
    @State private var logTarget: LogTarget?
    @State private var mealPresetTarget: MealPreset?
    @State private var catalogContext: LogContext?
    @State private var openMeal: MealType?
    @State private var showFasting = false
    @State private var isPresentingAddHydration = false
    @State private var hydrationActionError: String?

    var body: some View {
        let dayLog = environment.dayLog
        let dashboard = dayLog.dashboard

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                DaySwitcher(
                    date: dayLog.selectedDate,
                    isToday: dayLog.isToday,
                    onStep: { days in Task { await environment.stepDay(byDays: days) } },
                    onToday: { Task { await environment.goToToday() } }
                )

                DaySummaryCard(
                    dashboard: dashboard,
                    isStale: dayLog.isStale,
                    isLoading: dayLog.isLoading,
                    activeKilocalories: dayLog.activeKilocalories,
                    isToday: dayLog.isToday
                )

                ProgressStrip(
                    streak: environment.gamificationEngine.streakStatus,
                    level: environment.gamificationEngine.levelProgress
                ) {
                    environment.router.selectedTab = .progress
                }

                if let activeFastingSession {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(title: "Fasting")
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            FastingTodayCard(session: activeFastingSession, now: context.date) {
                                showFasting = true
                            }
                        }
                    }
                }

                VStack(spacing: Theme.Spacing.md) {
                    ForEach(dashboard.sections) { section in
                        MealSectionCard(
                            section: section,
                            onOpen: { openMeal = section.mealType },
                            onAdd: { startLog(meal: section.mealType) }
                        )
                    }
                }

                if dayLog.isToday, !quickPickItems.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(title: "Log again")
                            .padding(.horizontal, Theme.Spacing.md)
                        QuickPickShelf(items: quickPickItems) { item in
                            logAgain(item)
                        }
                    }
                    .padding(.horizontal, -Theme.Spacing.md)
                }

                if dayLog.isToday, !mealPresets.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(title: "Log a meal")
                            .padding(.horizontal, Theme.Spacing.md)
                        MealPresetShelf(presets: mealPresets) { preset in
                            mealPresetTarget = preset
                        }
                    }
                    .padding(.horizontal, -Theme.Spacing.md)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: "Weight & Water")
                    TodayWeightCard(latest: environment.weightLoader.latest, previous: environment.weightLoader.previous)
                    TodayHydrationCard(
                        todayTotalML: environment.hydrationLoader.todayTotalML,
                        goalML: hydrationDailyGoalML,
                        onQuickAdd: { amount in Task { await quickAddHydration(amount) } },
                        onCustom: { isPresentingAddHydration = true }
                    )
                }

                // add-day-notes: note + tags for the selected day (see
                // DayNoteCard.swift's header).
                DayNoteCard(day: dayLog.dateString, store: environment.dayNoteStore)

                AppSignatureView()
                    .padding(.top, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Food log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startLog(meal: nil)
                } label: {
                    Label("Log a food", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationDestination(item: $catalogContext) { context in
            FoodCatalogView(logContext: context)
        }
        .navigationDestination(item: $logTarget) { target in
            LogEntryConfirmView(target: target, presetMealType: nil, presetDate: dayLog.selectedDate)
        }
        .navigationDestination(item: $mealPresetTarget) { preset in
            MealPresetConfirmView(preset: preset, presetMealType: nil, presetDate: dayLog.selectedDate)
        }
        .navigationDestination(item: $openMeal) { meal in
            MealDetailView(mealType: meal)
        }
        .navigationDestination(isPresented: $showFasting) {
            FastingView()
        }
        .sheet(isPresented: $isPresentingAddHydration) {
            NavigationStack {
                AddHydrationSheet()
            }
        }
        .alert(
            "Couldn't complete that action",
            isPresented: Binding(
                get: { hydrationActionError != nil },
                set: { if !$0 { hydrationActionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(hydrationActionError ?? "")
        }
        .refreshable {
            await environment.refreshOnForeground()
            await loadQuickPicks()
            await loadMealPresets()
            await loadFastingSession()
        }
        .task { await loadQuickPicks() }
        .task { await loadMealPresets() }
        .task { await loadFastingSession() }
        .onAppear {
            // Fasting state changes minute to minute and can also change on
            // a different screen (starting/ending a fast happens in
            // `FastingView`, pushed from the card below) -- re-read it every
            // time this view comes back on screen, not just once via
            // `.task`, so the card doesn't show a stale phase after
            // returning from it.
            Task { await loadFastingSession() }
        }
        .onChange(of: environment.router.catalogRequested, initial: true) { _, requested in
            guard requested else { return }
            environment.router.catalogRequested = false
            // 2026-09-21 bug fix: this used to unconditionally overwrite
            // `catalogContext`, even while a meal-scoped FoodCatalogView
            // was already open (e.g. the user tapped "Add food" under
            // Lunch, then triggered the Lock Screen/Control Center
            // barcode-scan Control before logging anything) -- silently
            // discarding that meal preset, reintroducing the exact "wrong
            // meal" bug already fixed once, just through this one
            // Control-driven entry point. Checking `environment.router.
            // isCatalogPresented` (not this view's own local
            // `catalogContext`) also correctly covers the catalog being
            // open one level deeper via `MealDetailView`'s own separate
            // `catalogContext`, since `TodayView` stays mounted underneath
            // it in the same `NavigationStack` and this listener still
            // fires either way. If a catalog is already open anywhere,
            // leave it alone: `FoodCatalogView` has its own independent
            // listener on the same `AppNavigationBridge` pending route
            // (`presentScannerIfRouteIsPending`) and will present the
            // scanner itself without needing a new push here.
            guard !environment.router.isCatalogPresented else { return }
            catalogContext = LogContext(mealType: nil, date: nil)
        }
    }

    private func startLog(meal: MealType?) {
        catalogContext = LogContext(mealType: meal, date: environment.dayLog.selectedDate)
    }

    /// "Log again" tap. A custom food on the shelf is cached as a
    /// `.custom`-source `Food` whose id is the draft's local UUID -- which
    /// means nothing to Garmin -- so it must route through its
    /// `CustomFoodDraft` (logged as its backing food), exactly like
    /// `FoodCatalogView.selectQuickPick`. A custom food whose draft was
    /// deleted can't be logged at all, so the tap does nothing.
    private func logAgain(_ item: QuickPickItem) {
        guard item.food.source == .custom else {
            logTarget = .catalog(food: item.food, initialServing: item.serving)
            return
        }
        Task {
            let drafts = await environment.customFoodStore.all()
            if let draft = drafts.first(where: { $0.id.uuidString == item.food.id }) {
                logTarget = .custom(draft)
            }
        }
    }

    private func loadQuickPicks() async {
        let events = await environment.usageHistory.all()
        let cache = await environment.foodCache.all()
        quickPickItems = QuickPick.rank(events: events).prefix(6).compactMap { entry in
            guard let food = cache[entry.foodId],
                  let serving = food.servings.first(where: { $0.id == entry.servingId })
            else { return nil }
            return QuickPickItem(food: food, serving: serving, numberOfUnits: entry.numberOfUnits)
        }
    }

    private func loadMealPresets() async {
        mealPresets = await environment.mealPresetStore.all()
    }

    private func loadFastingSession() async {
        activeFastingSession = await environment.fastingStore.active()
    }

    /// Mirrors `HydrationView.quickAdd(_:)` exactly (same coordinator call,
    /// same post-log refresh, same simple inline error surface) -- this is
    /// a second entry point to the same local-first logging path, not a
    /// separate implementation of it.
    private func quickAddHydration(_ amount: Double) async {
        do {
            _ = try await environment.hydrationLogCoordinator.logHydration(valueInML: amount)
            await environment.hydrationLogged()
        } catch {
            hydrationActionError = "Couldn't save this entry."
        }
    }
}

// MARK: - Day summary

/// The day against its target: a calorie ring and the three macro bars.
///
/// The Target is the fixed base goal and the ring is coloured by
/// `CalorieBand`'s stepped scale (fix-testing-feedback-quick-wins,
/// today-dashboard spec). Active calories are shown under the Target for
/// information only -- they never change the Target (no eat-back).
struct DaySummaryCard: View {
    let dashboard: DayDashboard
    let isStale: Bool
    let isLoading: Bool
    /// The selected day's active kcal, or `nil` to hide the line (not
    /// loaded yet, or the read failed -- never shown as an error).
    var activeKilocalories: Double? = nil
    /// Picks the line's wording: "Active today" vs. a past day's "Active".
    var isToday: Bool = true

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 132

    var body: some View {
        let calories = dashboard.totals.calories
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                ProgressRing(
                    fraction: calories.fraction ?? 0,
                    lineWidth: 12,
                    tint: calories.calorieBand?.tint ?? Theme.accent
                ) {
                    VStack(spacing: 0) {
                        Text("\(Int(calories.consumed.rounded()))")
                            .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("kcal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(Theme.Spacing.sm)
                }
                .frame(width: ringSize, height: ringSize)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Calories")
                .accessibilityValue(caloriesAccessibility(calories))

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(remainingText(calories))
                        .font(.headline)
                    if let goal = calories.goal {
                        Text("Target \(Int(goal.rounded())) kcal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let activeKilocalories {
                        Label(activeText(activeKilocalories), systemImage: "flame")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(activeAccessibility(activeKilocalories))
                    }
                    statusLine
                }
            }

            VStack(spacing: Theme.Spacing.sm) {
                MacroBar(title: "Carbs", progress: dashboard.totals.carbs, unit: "g", tint: Theme.carbs)
                MacroBar(title: "Protein", progress: dashboard.totals.protein, unit: "g", tint: Theme.protein)
                MacroBar(title: "Fat", progress: dashboard.totals.fat, unit: "g", tint: Theme.fat)
            }
        }
        .card()
    }

    @ViewBuilder
    private var statusLine: some View {
        if isLoading {
            Label("Updating…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if isStale {
            Label("Showing the last loaded numbers", systemImage: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(Theme.warning)
        } else if !dashboard.hasGarminData {
            Label("Not loaded from Garmin yet", systemImage: "icloud.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func remainingText(_ calories: MacroProgress) -> String {
        guard let remaining = calories.remaining else { return "No calorie target" }
        let value = Int(abs(remaining).rounded())
        return remaining >= 0 ? "\(value) kcal left" : "\(value) kcal over"
    }

    private func caloriesAccessibility(_ calories: MacroProgress) -> String {
        let consumed = Int(calories.consumed.rounded())
        guard let goal = calories.goal else { return "\(consumed) kilocalories" }
        let base = "\(consumed) of \(Int(goal.rounded())) kilocalories"
        guard let band = calories.calorieBand else { return base }
        return "\(base), \(band.accessibilityDescription)"
    }

    private func activeText(_ kilocalories: Double) -> String {
        let value = Int(kilocalories.rounded())
        return isToday ? "Active today: \(value) kcal" : "Active: \(value) kcal"
    }

    private func activeAccessibility(_ kilocalories: Double) -> String {
        let value = Int(kilocalories.rounded())
        let when = isToday ? "today" : "that day"
        return "Active calories burned \(when): \(value) kilocalories. For information only, not added to the target."
    }
}

// MARK: - Streak and level strip

/// A compact line linking to the Progress tab.
struct ProgressStrip: View {
    let streak: StreakEngine.Status
    let level: LevelCurve.Progress
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(streak.length > 0 ? AnyShapeStyle(Theme.flameGradient) : AnyShapeStyle(Color.secondary))
                        .symbolEffect(.pulse, options: .repeating, isActive: shouldPulse)
                    Text("\(streak.length)")
                        .font(.streakNumber)
                    Text(streak.length == 1 ? "day" : "days")
                        .font(.streakLabel)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Level \(level.level)")
                        .font(.subheadline.weight(.semibold))
                    ProgressView(value: level.fractionToNextLevel)
                        .tint(Theme.accent)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card(padding: Theme.Spacing.sm + 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak \(streak.length) days, level \(level.level). \(streak.isAtRiskToday ? "Log something today to keep the streak." : "")")
        .accessibilityHint("Opens Progress")
    }

    /// The at-risk pulse is a repeating animation, so it respects Reduce
    /// Motion and the celebrations preference (add-gamification 26.3).
    private var shouldPulse: Bool {
        streak.isAtRiskToday && !reduceMotion && environment.preferences.celebrationsEnabled
    }
}

// MARK: - Fasting card

/// The compact Today-tab surface for the active fast (2026-09-22) --
/// mirrors `ProgressStrip`'s own shape (a `Button` wrapping a `.card()`,
/// `.buttonStyle(.plain)`, combined accessibility element) since both are
/// "tap this summary to go see more" rows. Reuses `ProgressRing` at a small
/// size rather than a bespoke mini-ring. The full ring/actions/history live
/// in `FastingView` (`GarminFood/Fasting/`), reached by tapping this card.
struct FastingTodayCard: View {
    let session: FastingSession
    let now: Date
    let onTap: () -> Void

    var body: some View {
        let phase = session.currentPhase(at: now)
        let tint = phase.kind == .fasting ? Theme.accent : Theme.success

        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                ProgressRing(fraction: phase.fraction(at: now), lineWidth: 5, tint: tint) {
                    Image(systemName: phase.kind == .fasting ? "timer" : "fork.knife")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text(phase.kind == .fasting ? "Fasting" : "Eating window")
                        .font(.subheadline.weight(.semibold))
                    Text(Self.remainingText(phase, now: now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card(padding: Theme.Spacing.sm + 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phase.kind == .fasting ? "Fasting" : "Eating window"). \(Self.remainingText(phase, now: now))")
        .accessibilityHint("Opens Fasting")
    }

    private static func remainingText(_ phase: FastingPhase, now: Date) -> String {
        if phase.isOverdue(at: now) {
            return "\(Self.hoursMinutes(phase.elapsed(at: now) - phase.duration)) over target"
        }
        return "\(Self.hoursMinutes(phase.remaining(at: now))) left"
    }

    private static func hoursMinutes(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

// MARK: - Meal card

struct MealSectionCard: View {
    let section: MealSection
    let onOpen: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button(action: onOpen) {
                header
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(section.mealType.displayName) details")

            HStack(spacing: Theme.Spacing.sm) {
                MacroBar(title: "C", progress: section.totals.carbs, unit: "g", tint: Theme.carbs, compact: true)
                    .accessibilityLabel("Carbs")
                MacroBar(title: "P", progress: section.totals.protein, unit: "g", tint: Theme.protein, compact: true)
                    .accessibilityLabel("Protein")
                MacroBar(title: "F", progress: section.totals.fat, unit: "g", tint: Theme.fat, compact: true)
                    .accessibilityLabel("Fat")
            }

            if !section.entries.isEmpty {
                Divider()
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(section.entries) { entry in
                        MealEntryRow(entry: entry)
                    }
                }
            }

            Button(action: onAdd) {
                Label("Add food", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .tint(Theme.accent)
            .padding(.top, Theme.Spacing.xs)
            .accessibilityLabel("Add food to \(section.mealType.displayName)")
        }
        .card()
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: section.mealType.symbolName)
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(section.mealType.displayName)
                    .font(.headline)
                if let window = section.window {
                    Text(window.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(caloriesText)
                    .font(.macroValue)
                    .foregroundStyle(section.totals.calories.state.tint(base: .primary))
                if section.hasPendingEntries {
                    Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var caloriesText: String {
        let consumed = Int(section.totals.calories.consumed.rounded())
        guard let goal = section.totals.calories.goal else { return "\(consumed) kcal" }
        return "\(consumed) / \(Int(goal.rounded())) kcal"
    }
}

// MARK: - Entry row

struct MealEntryRow: View {
    let entry: MealEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            statusIcon
            if let calories = entry.calories {
                MacroBadge(value: calories, unit: " kcal", accessibleUnit: "kilocalories")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        let quantity = entry.servingQty.formattedQuantity
        guard let serving = entry.servingDescription else { return "\(quantity) ×" }
        return "\(quantity) × \(serving)"
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch entry.status {
        case .synced:
            EmptyView()
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Syncing")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.warning)
                .accessibilityLabel("Not delivered")
        }
    }
}

extension MealWindow {
    /// "10:00–12:00"
    var displayText: String {
        "\(Self.clock(start))–\(Self.clock(end))"
    }

    private static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }
}

/// Matches `LogEntryConfirmView.swift`'s copy of this exact extension
/// (`%.2f`, closer to this row's "show the precise logged quantity"
/// purpose than `QuickPickShelf.swift`'s own copy, which uses `%.1f`).
/// Those two disagree with each other already -- there is no single,
/// module-visible source of truth to call into instead, since both are
/// `private` to their own file. This file previously formatted with a
/// third, different rule (`.formatted(.number.precision(.fractionLength(0...2)))`),
/// so `0.7` could read differently in a meal card than in the confirm
/// screen for the SAME entry. Consolidating all three into one shared,
/// non-private helper is a real follow-up, not attempted here to avoid
/// touching two already-shipped, working screens in a bug-fix pass.
private extension Double {
    var formattedQuantity: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.2f", self)
    }
}
