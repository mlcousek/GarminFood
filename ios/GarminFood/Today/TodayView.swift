// TodayView.swift
//
// The Today tab (meal-dashboard spec): the day as Garmin Connect's food page
// shows it. There's a day switcher and a summary against the daily target,
// then one card per meal with its foods and consumed-vs-suggested calories
// and macros. Queued entries appear in their meal before they reach Garmin.
// Adding from a meal pre-selects that meal and day.
//
// `FastingHomeSection` (redesign-fasting-schedule, `GarminFood/Fasting/
// FastingHomeCard.swift`) is the always-on fasting card while the daily
// fasting window is enabled, placed right under the streak strip since the
// owner checks it day to day. Tapping it pushes `FastingHistoryView`.
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
//
// add-themes-and-layout (design.md D8, wave 3): the cards are no longer a
// fixed stack. The body renders `LayoutStore`'s resolved Today order through
// one `@ViewBuilder switch` over `TodayCardID` (`todayCard(_:variant:)`), showing
// a card only when the user left it visible AND `availability(_:)` says it
// has something to show. The show-when rules that used to be `if`s here
// (Log again / Log a meal only on today's date and non-empty, fasting only
// while enabled) moved into `availability(_:)` unchanged. With nothing
// stored, the order is exactly the one described above (golden test:
// AppearanceKit's LayoutResolverTests), so a user who never edits sees no
// change. "Edit layout…" in the toolbar menu opens `LayoutEditorSheet` at
// half height over this screen, which updates live underneath it.

import SwiftUI
import FoodLogCore
import GarminKit
import Gamification
import AppearanceKit

@MainActor
struct TodayView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var quickPickItems: [QuickPickItem] = []
    @State private var mealPresets: [MealPreset] = []
    @State private var logTarget: LogTarget?
    @State private var mealPresetTarget: MealPreset?
    @State private var catalogContext: LogContext?
    @State private var openMeal: MealType?
    /// add-log-entry-editing: Edit/Move/Duplicate/Delete on a meal card's
    /// rows and "Copy from…" -- see EntryEditing.swift.
    @State private var entryEditor = EntryEditor()
    @State private var showFasting = false
    @State private var isPresentingAddHydration = false
    @State private var hydrationActionError: String?
    @State private var isEditingLayout = false

    var body: some View {
        let dayLog = environment.dayLog

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                // Each card is a direct child of this stack (a ForEach
                // element's views flatten into it), so spacing is exactly
                // what the fixed stack had.
                ForEach(renderedCards) { placement in
                    if let card = TodayCardID(rawValue: placement.id) {
                        todayCard(card, variant: placement.variant)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background { GradientHeaderBackground() }
        .navigationTitle("Food log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        isEditingLayout = true
                    } label: {
                        Label("Edit layout…", systemImage: "rectangle.3.group")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
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
        .entryEditing(entryEditor)
        .navigationDestination(isPresented: $showFasting) {
            FastingHistoryView()
        }
        .sheet(isPresented: $isPresentingAddHydration) {
            NavigationStack {
                AddHydrationSheet()
            }
        }
        // add-themes-and-layout D9: half height over this screen, which
        // stays live and scrollable underneath as rows move.
        .sheet(isPresented: $isEditingLayout) {
            LayoutEditorSheet(screen: .today) { id in
                TodayCardID(rawValue: id).map { availability($0) } ?? .available
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
        }
        .task { await loadQuickPicks() }
        .task { await loadMealPresets() }
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

    // MARK: - Cards (add-themes-and-layout D8)

    /// The resolved Today order, keeping only cards the user left visible
    /// that have something to show.
    private var renderedCards: [ResolvedPlacement] {
        environment.layoutStore.resolved(.today).filter { placement in
            guard placement.isVisible, let card = TodayCardID(rawValue: placement.id) else { return false }
            return availability(card).isAvailable
        }
    }

    /// The show-when rules the fixed stack had, unchanged: Log again and
    /// Log a meal only on today's date with something in them, fasting only
    /// while enabled. Everything else always shows (the banner slots and
    /// Weight & Water decide their own content, as before).
    private func availability(_ card: TodayCardID) -> CardAvailability {
        let dayLog = environment.dayLog
        switch card {
        case .logAgain:
            return dayLog.isToday && !quickPickItems.isEmpty
                ? .available
                : .empty(String(localized: "Shows on today's date when there are foods to log again", comment: "Layout editor: when the Log again shelf appears on Today."))
        case .logMeal:
            return dayLog.isToday && !mealPresets.isEmpty
                ? .available
                : .empty(String(localized: "Shows on today's date when you have saved meals", comment: "Layout editor: when the Log a meal shelf appears on Today."))
        default:
            return TodayCardID.baseAvailability(card, preferences: environment.preferences)
        }
    }

    /// One Today card. Each arm is the view the fixed stack had in that
    /// position, plus its variant (D8 variants table).
    @ViewBuilder
    private func todayCard(_ card: TodayCardID, variant: String?) -> some View {
        let dayLog = environment.dayLog
        switch card {
        case .daySwitcher:
            DaySwitcher(
                date: dayLog.selectedDate,
                isToday: dayLog.isToday,
                onStep: { days in Task { await environment.stepDay(byDays: days) } },
                onToday: { Task { await environment.goToToday() } }
            )

        case .summary:
            DaySummaryCard(
                dashboard: dayLog.dashboard,
                isStale: dayLog.isStale,
                isLoading: dayLog.isLoading,
                activeKilocalories: dayLog.activeKilocalories,
                isToday: dayLog.isToday,
                style: variant.flatMap(SummaryVariant.init(rawValue:)) ?? .ring
            )

        case .progressStrip:
            ProgressStrip(
                streak: environment.gamificationEngine.streakStatus,
                level: environment.gamificationEngine.levelProgress
            ) {
                environment.router.selectedTab = .progress
            }

        case .fasting:
            FastingHomeSection { showFasting = true }

        case .banners:
            TodaySlotHost() // add-gamification-signals D12: feature banners

        case .meals:
            VStack(spacing: Theme.Spacing.md) {
                ForEach(dayLog.dashboard.sections) { section in
                    MealSectionCard(
                        section: section,
                        editor: entryEditor,
                        onOpen: { openMeal = section.mealType },
                        onAdd: { startLog(meal: section.mealType) },
                        isCollapsed: variant == MealsVariant.collapsed.rawValue
                    )
                }
            }

        case .logAgain:
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: String(localized: "Log again"))
                    .padding(.horizontal, Theme.Spacing.md)
                QuickPickShelf(items: quickPickItems) { item in
                    logAgain(item)
                }
            }
            .padding(.horizontal, -Theme.Spacing.md)

        case .logMeal:
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: String(localized: "Log a meal"))
                    .padding(.horizontal, Theme.Spacing.md)
                MealPresetShelf(presets: mealPresets) { preset in
                    mealPresetTarget = preset
                }
            }
            .padding(.horizontal, -Theme.Spacing.md)

        case .weightWater:
            weightWater(variant.flatMap(WeightWaterVariant.init(rawValue:)) ?? .both)

        case .dayNote:
            // add-day-notes: note + tags for the selected day (see
            // DayNoteCard.swift's header).
            DayNoteCard(day: dayLog.dateString, store: environment.dayNoteStore)

        case .signature:
            AppSignatureView()
                .padding(.top, Theme.Spacing.xs)
        }
    }

    /// "Weight & Water": both cards (today's look), or just one.
    private func weightWater(_ variant: WeightWaterVariant) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            switch variant {
            case .both:
                SectionHeader(title: String(localized: "Weight & Water"))
            case .weight:
                SectionHeader(title: String(localized: "Weight", comment: "Today: section header when only the weight card is shown."))
            case .water:
                SectionHeader(title: String(localized: "Water", comment: "Today: section header when only the water card is shown."))
            }
            if variant != .water {
                TodayWeightCard(
                    latest: environment.weightLoader.latest,
                    previous: environment.weightLoader.previous,
                    progress: environment.weightLoader.progress,
                    refreshFailed: environment.weightLoader.lastGarminRefreshFailed,
                    isStandalone: environment.dataMode == .standalone
                )
            }
            if variant != .weight {
                TodayHydrationCard(
                    todayTotalML: environment.hydrationLoader.todayTotalML,
                    goalML: environment.hydrationLoader.goalML,
                    refreshFailed: environment.hydrationLoader.lastGarminRefreshFailed,
                    onQuickAdd: { amount in Task { await quickAddHydration(amount) } },
                    onCustom: { isPresentingAddHydration = true }
                )
            }
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
    ///
    /// Either way the confirm screen starts at the card's own remembered
    /// amount (`item.numberOfUnits`, the "2×" the card shows), not one
    /// serving.
    private func logAgain(_ item: QuickPickItem) {
        guard item.food.source == .custom else {
            logTarget = .catalog(food: item.food, initialServing: item.serving, initialQuantity: item.numberOfUnits)
            return
        }
        Task {
            let drafts = await environment.customFoodStore.all()
            if let draft = drafts.first(where: { $0.id.uuidString == item.food.id }) {
                logTarget = .custom(draft, initialQuantity: item.numberOfUnits)
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

    /// Mirrors `HydrationView.quickAdd(_:)` exactly (same coordinator call,
    /// same post-log refresh, same simple inline error surface) -- this is
    /// a second entry point to the same local-first logging path, not a
    /// separate implementation of it.
    private func quickAddHydration(_ amount: Double) async {
        do {
            _ = try await environment.hydrationLogCoordinator.logHydration(valueInML: amount)
            await environment.hydrationLogged()
        } catch {
            hydrationActionError = String(localized: "Couldn't save this entry.")
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

    /// add-themes-and-layout D8: the layout editor's summary variant.
    /// `.ring` is the look this card always had.
    var style: SummaryVariant = .ring

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 132
    @ScaledMetric(relativeTo: .largeTitle) private var compactRingSize: CGFloat = 72

    var body: some View {
        let calories = dashboard.totals.calories
        switch style {
        case .ring:
            ringCard(calories)
        case .compact:
            compactCard(calories)
        case .hero:
            heroCard(calories)
        }
    }

    /// Today's look: the 132 pt ring beside the numbers, macro bars below.
    private func ringCard(_ calories: MacroProgress) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                ProgressRing(
                    fraction: calories.fraction ?? 0,
                    lineWidth: 12,
                    tint: calories.calorieBand?.tint ?? Theme.accent
                ) {
                    VStack(spacing: 0) {
                        Text("\(calories.consumed.wholeNumberText)")
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
                        Text("Target \(goal.wholeNumberText) kcal")
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

            macroBars
        }
        .card()
    }

    /// One row: a 72 pt (scaled) ring, what's left, and compact macro bars.
    private func compactCard(_ calories: MacroProgress) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            ProgressRing(
                fraction: calories.fraction ?? 0,
                lineWidth: 7,
                tint: calories.calorieBand?.tint ?? Theme.accent
            ) {
                Text(verbatim: calories.consumed.wholeNumberText)
                    .font(.macroValue)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(Theme.Spacing.xs)
            }
            .frame(width: compactRingSize, height: compactRingSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calories")
            .accessibilityValue(caloriesAccessibility(calories))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(remainingText(calories))
                    .font(.headline)
                compactMacroBars
                statusLine
            }
        }
        .card()
    }

    /// The day's calories as one big number (no ring) over a bar in the
    /// calorie-band color, then the same lines and macro bars as the ring.
    private func heroCard(_ calories: MacroProgress) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(verbatim: calories.consumed.wholeNumberText)
                        .heroNumberFont()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("kcal")
                        .font(.heroUnit)
                        .foregroundStyle(.secondary)
                }
                if calories.goal != nil {
                    ProgressView(value: min(max(calories.fraction ?? 0, 0), 1))
                        .tint(calories.calorieBand?.tint ?? Theme.accent)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calories")
            .accessibilityValue(caloriesAccessibility(calories))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(remainingText(calories))
                    .font(.headline)
                if let goal = calories.goal {
                    Text("Target \(goal.wholeNumberText) kcal")
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

            macroBars
        }
        .card()
    }

    private var macroBars: some View {
        VStack(spacing: Theme.Spacing.sm) {
            MacroBar(title: String(localized: "Carbs"), progress: dashboard.totals.carbs, unit: "g", tint: Theme.carbs)
            MacroBar(title: String(localized: "Protein"), progress: dashboard.totals.protein, unit: "g", tint: Theme.protein)
            MacroBar(title: String(localized: "Fat"), progress: dashboard.totals.fat, unit: "g", tint: Theme.fat)
        }
    }

    /// The meal cards' compact bars (same keys and labels as `MealSectionCard`).
    private var compactMacroBars: some View {
        HStack(spacing: Theme.Spacing.sm) {
            MacroBar(title: String(localized: "C", comment: "One-letter abbreviation of Carbs on a compact macro bar."), progress: dashboard.totals.carbs, unit: "g", tint: Theme.carbs, compact: true)
                .accessibilityLabel("Carbs")
            MacroBar(title: String(localized: "P", comment: "One-letter abbreviation of Protein on a compact macro bar."), progress: dashboard.totals.protein, unit: "g", tint: Theme.protein, compact: true)
                .accessibilityLabel("Protein")
            MacroBar(title: String(localized: "F", comment: "One-letter abbreviation of Fat on a compact macro bar."), progress: dashboard.totals.fat, unit: "g", tint: Theme.fat, compact: true)
                .accessibilityLabel("Fat")
        }
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
        guard let remaining = calories.remaining else { return String(localized: "No calorie target") }
        let value = abs(remaining).wholeNumberText
        return remaining >= 0 ? String(localized: "\(value) kcal left") : String(localized: "\(value) kcal over")
    }

    private func caloriesAccessibility(_ calories: MacroProgress) -> String {
        let consumed = calories.consumed.wholeNumberText
        guard let goal = calories.goal else { return String(localized: "Kilocalories: \(consumed)") }
        let base = String(localized: "\(consumed) of \(goal.wholeNumberText) kilocalories")
        guard let band = calories.calorieBand else { return base }
        return "\(base), \(band.accessibilityDescription)"
    }

    private func activeText(_ kilocalories: Double) -> String {
        let value = kilocalories.wholeNumberText
        return isToday ? String(localized: "Active today: \(value) kcal") : String(localized: "Active: \(value) kcal")
    }

    private func activeAccessibility(_ kilocalories: Double) -> String {
        let value = kilocalories.wholeNumberText
        return isToday
            ? String(localized: "Active calories burned today: \(value) kilocalories. For information only, not added to the target.")
            : String(localized: "Active calories burned that day: \(value) kilocalories. For information only, not added to the target.")
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
                    let parts = streakParts
                    if !parts.before.isEmpty {
                        Text(verbatim: parts.before)
                            .font(.streakLabel)
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: parts.number)
                        .font(.streakNumber)
                    Text(verbatim: parts.after)
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
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens Progress")
    }

    /// "5 days" as ONE plural-aware key (Czech: 1 den / 2 dny / 5 dní),
    /// split around the number so the number keeps its big streak style.
    /// Falls back to the whole phrase as the label if a translation ever
    /// drops the plain number.
    private var streakParts: (before: String, number: String, after: String) {
        let number = String(streak.length)
        let full = String(localized: "\(streak.length) days", comment: "Streak strip on Today: consecutive logged days. Plural. The number is shown larger than the word.")
        guard let range = full.range(of: number) else { return ("", "", full) }
        let before = full[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let after = full[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return (before, number, after)
    }

    private var accessibilityText: String {
        // Whole sentences joined by a space: each is its own key, so the
        // plural only ever depends on one number.
        var sentences = [
            String(localized: "Streak: \(streak.length) days in a row.", comment: "VoiceOver, Today's streak strip. Plural."),
            String(localized: "Level \(level.level).", comment: "VoiceOver, Today's streak strip: current level."),
        ]
        if streak.isAtRiskToday {
            sentences.append(String(localized: "Log something today to keep the streak."))
        }
        return sentences.joined(separator: " ")
    }

    /// The at-risk pulse is a repeating animation, so it respects Reduce
    /// Motion and the celebrations preference (add-gamification 26.3).
    private var shouldPulse: Bool {
        streak.isAtRiskToday && !reduceMotion && environment.preferences.celebrationsEnabled
    }
}

// MARK: - Meal card

struct MealSectionCard: View {
    let section: MealSection
    /// add-log-entry-editing: rows tap to edit and long-press for Move/
    /// Duplicate/Delete (a card isn't a List, so no swipe here -- that's on
    /// the meal's detail screen); "Copy from…" sits next to "Add food".
    let editor: EntryEditor
    let onOpen: () -> Void
    let onAdd: () -> Void
    /// add-themes-and-layout D8 "Collapsed" variant: header (with calories)
    /// and macro bars only, the whole card one tap into `MealDetailView`,
    /// where the entries and their actions are.
    var isCollapsed = false

    var body: some View {
        if isCollapsed {
            collapsedCard
        } else {
            expandedCard
        }
    }

    private var collapsedCard: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                header
                macroBars
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(section.mealType.displayName) details")
    }

    private var macroBars: some View {
        HStack(spacing: Theme.Spacing.sm) {
            MacroBar(title: String(localized: "C", comment: "One-letter abbreviation of Carbs on a compact macro bar."), progress: section.totals.carbs, unit: "g", tint: Theme.carbs, compact: true)
                .accessibilityLabel("Carbs")
            MacroBar(title: String(localized: "P", comment: "One-letter abbreviation of Protein on a compact macro bar."), progress: section.totals.protein, unit: "g", tint: Theme.protein, compact: true)
                .accessibilityLabel("Protein")
            MacroBar(title: String(localized: "F", comment: "One-letter abbreviation of Fat on a compact macro bar."), progress: section.totals.fat, unit: "g", tint: Theme.fat, compact: true)
                .accessibilityLabel("Fat")
        }
    }

    /// The look this card always had.
    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button(action: onOpen) {
                header
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(section.mealType.displayName) details")

            macroBars

            if !section.entries.isEmpty {
                Divider()
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(section.entries) { entry in
                        MealEntryRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if entry.canRelog {
                                    editor.editTarget = entry
                                }
                            }
                            .entryActions(entry, editor: editor)
                    }
                }
            }

            HStack {
                Button(action: onAdd) {
                    Label("Add food", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add food to \(section.mealType.displayName)")

                Button {
                    editor.copyTarget = CopyMealTarget(mealType: section.mealType)
                } label: {
                    Label("Copy from…", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy a past meal into \(section.mealType.displayName)")
            }
            .tint(Theme.accent)
            .padding(.top, Theme.Spacing.xs)
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
        let consumed = section.totals.calories.consumed.wholeNumberText
        guard let goal = section.totals.calories.goal else { return "\(consumed) kcal" }
        return "\(consumed) / \(goal.wholeNumberText) kcal"
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
                MacroBadge.calories(calories)
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
