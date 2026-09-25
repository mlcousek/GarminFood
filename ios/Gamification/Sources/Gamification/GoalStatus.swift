import Foundation

// GoalStatus.swift
//
// D3's "meeting a day's nutrition goal" and the challenges spec's
// goal-hitting requirement both need to know, for a given nutrition-day,
// whether the day's consumption met its Garmin-set goal. That comparison
// needs both a target (`GarminKit.NutritionGoals`, from
// `GarminClient.dailyFoodLog(date:)`) and an actual (`DailyNutritionContent`
// from the same call) -- both of which require a NETWORK read.
//
// This package makes no network calls of its own (this file's package
// header), and the challenges spec is explicit that evaluation must happen
// "without requiring a network call of its own" -- so this type is
// deliberately just a small, already-computed LOCAL snapshot: something
// else (the app layer, which already owns a `GarminClient` -- see
// AppEnvironment.swift) fetches `dailyFoodLog(date:)`, decides whether each
// goal was met, and hands the result here to be cached. Nothing in this
// package decides HOW "met" is computed from raw calorie/macro numbers --
// see the app layer's translation code for that judgment call (documented
// there, since it is a real assumption, not a spec-given rule).
//
// `GoalStatusStore` mirrors `FoodLogCore.UsageHistoryStore`'s own pattern
// (own JSON file, own Application Support subdirectory, actor-isolated,
// atomic writes, capped size) as closely as possible, for exactly the same
// "trivially inspectable on disk, no interactive debugger" reasons.

/// One nutrition-day's worth of Garmin goal-vs-actual outcomes, already
/// resolved to booleans by whoever populated it (the app layer).
public struct DailyGoalStatus: Sendable, Equatable, Codable {
    /// `yyyy-MM-dd`, matching `NutritionDayBoundary.dayString(for:...)`'s
    /// format so the two are directly comparable as dictionary keys.
    public let date: String
    public let metCalorieGoal: Bool
    public let metProteinGoal: Bool
    public let metCarbGoal: Bool
    public let metFatGoal: Bool

    public init(date: String, metCalorieGoal: Bool, metProteinGoal: Bool, metCarbGoal: Bool, metFatGoal: Bool) {
        self.date = date
        self.metCalorieGoal = metCalorieGoal
        self.metProteinGoal = metProteinGoal
        self.metCarbGoal = metCarbGoal
        self.metFatGoal = metFatGoal
    }

    /// `true` if ANY tracked goal was met that day -- used by challenges
    /// like "hit your protein goal 4 days running" generalised to "hit ANY
    /// goal 3 days running" (`ChallengeKind.goalHitStreak(macro: nil, ...)`).
    public var anyGoalMet: Bool { metCalorieGoal || metProteinGoal || metCarbGoal || metFatGoal }

    public func met(_ macro: GoalMacro) -> Bool {
        switch macro {
        case .calories: return metCalorieGoal
        case .protein: return metProteinGoal
        case .carbs: return metCarbGoal
        case .fat: return metFatGoal
        }
    }
}

public enum GoalMacro: String, Sendable, Equatable, Codable, CaseIterable {
    case calories, protein, carbs, fat

    /// The goal's name for display and VoiceOver ("met calories, protein"
    /// on the Goals history rows) -- never `rawValue`, which is a storage
    /// key (add-localization 4.1).
    public var displayName: String {
        switch self {
        case .calories: return String(localized: "Calories", bundle: .module, comment: "Nutrition goal name (Goals history, VoiceOver).")
        case .protein: return String(localized: "Protein", bundle: .module, comment: "Nutrition goal name (Goals history, VoiceOver).")
        case .carbs: return String(localized: "Carbs", bundle: .module, comment: "Nutrition goal name (Goals history, VoiceOver).")
        case .fat: return String(localized: "Fat", bundle: .module, comment: "Nutrition goal name (Goals history, VoiceOver).")
        }
    }
}

public actor GoalStatusStore {
    /// Generous relative to the longest challenge window this package
    /// defines (10 days) and to the levels XP goal-bonus's own bookkeeping
    /// needs, while still bounded -- same "cannot grow unbounded" rationale
    /// as `UsageHistoryStore.maxStoredEvents`.
    public static let maxStoredDays = 120

    private let fileURL: URL
    private var byDate: [String: DailyGoalStatus] = [:]
    private var order: [String] = [] // insertion order, oldest first, for capping
    private var loaded = false

    public init(fileURL: URL = GoalStatusStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        GamificationStorage.directory().appendingPathComponent("goal-status.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        let result = GamificationStorage.loadPersistedJSON([DailyGoalStatus].self, from: fileURL, decoder: decoder, category: "GoalStatusStore")
        // Unreadable (e.g. before first unlock): don't latch, retry on next
        // access; `persist()` refuses to overwrite it meanwhile. Start from
        // scratch each attempt so a retry never appends a day twice.
        loaded = !result.isUnreadable
        byDate = [:]
        order = []
        for status in result.value ?? [] {
            byDate[status.date] = status
            order.append(status.date)
        }
    }

    private func persist() throws {
        try GamificationStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "GoalStatusStore")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(order.compactMap { byDate[$0] })
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    public func all() -> [DailyGoalStatus] {
        loadIfNeeded()
        return order.compactMap { byDate[$0] }
    }

    /// Records (or overwrites, if already present -- a day's status can
    /// legitimately be re-fetched and change as more is logged) one day's
    /// goal status.
    public func record(_ status: DailyGoalStatus) throws {
        loadIfNeeded()
        if byDate[status.date] == nil {
            order.append(status.date)
        }
        byDate[status.date] = status
        if order.count > Self.maxStoredDays {
            let overflow = order.count - Self.maxStoredDays
            for date in order.prefix(overflow) { byDate.removeValue(forKey: date) }
            order.removeFirst(overflow)
        }
        try persist()
    }
}
