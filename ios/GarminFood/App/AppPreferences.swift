// AppPreferences.swift
//
// The few settings that survive a relaunch (profile-and-settings spec,
// design D9). Standard `UserDefaults`: there is no App Group, and nothing in
// an extension needs these values.

import Foundation
import Observation
import FoodLogCore

@MainActor
@Observable
final class AppPreferences {
    enum Key {
        static let haptics = "preferences.haptics"
        static let celebrations = "preferences.celebrations"
        static let garminMealWindows = "preferences.garminMealWindows"
        static let czechOnlySearch = "preferences.czechOnlySearch"
        // add-offline-czech-food-index D3: download the index on cellular too.
        static let offlineIndexAllowsCellular = "preferences.offlineIndex.allowsCellular"
        // redesign-fasting-schedule: the daily fasting window.
        static let fastingEnabled = "preferences.fasting.enabled"
        static let fastingStartMinute = "preferences.fasting.startMinute"
        static let fastingEndMinute = "preferences.fasting.endMinute"
        static let fastingTrackedSince = "preferences.fasting.trackedSince"
        static let fastingLegacyMigrated = "preferences.fasting.legacyMigrated"
        // sync-weight-hydration-with-garmin D5: local goal overrides. Absent
        // = use Garmin's goal (AppPreferences+Goals.swift).
        static let waterGoalOverrideML = "goals.water.overrideML"
        static let weightGoalOverrideKg = "goals.weight.overrideKg"
        static let weightGoalStartKg = "goals.weight.startKg"
        // amount-in-grams: type grams or servings in quantity fields.
        static let quantityInputMode = "preferences.quantityInputMode"
    }

    @ObservationIgnored private let defaults: UserDefaults

    // Stored, tracked values; the public properties below write through to
    // UserDefaults on every change.
    private var storedHaptics: Bool
    private var storedCelebrations: Bool
    private var storedGarminMealWindows: Bool
    private var storedCzechOnlySearch: Bool
    private var storedOfflineIndexAllowsCellular: Bool
    private var storedFastingEnabled: Bool
    private var storedFastingStartMinute: Int
    private var storedFastingEndMinute: Int
    private var storedFastingTrackedSince: Date?
    private var storedFastingLegacyMigrated: Bool
    private var storedWaterGoalOverrideML: Double?
    private var storedWeightGoalOverrideKg: Double?
    private var storedWeightGoalStartKg: Double?
    private var storedQuantityInputMode: QuantityInputMode

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedHaptics = defaults.object(forKey: Key.haptics) as? Bool ?? true
        storedCelebrations = defaults.object(forKey: Key.celebrations) as? Bool ?? true
        storedGarminMealWindows = defaults.object(forKey: Key.garminMealWindows) as? Bool ?? true
        // On by default, as the catalog's toggle always was.
        storedCzechOnlySearch = defaults.object(forKey: Key.czechOnlySearch) as? Bool ?? true
        // Off: Wi-Fi only until the user allows cellular.
        storedOfflineIndexAllowsCellular = defaults.object(forKey: Key.offlineIndexAllowsCellular) as? Bool ?? false
        // Off, 20:00-12:00 until set (or seeded once from the retired
        // manual-fasting file -- AppEnvironment.migrateLegacyFastingIfNeeded).
        storedFastingEnabled = defaults.object(forKey: Key.fastingEnabled) as? Bool ?? false
        storedFastingStartMinute = defaults.object(forKey: Key.fastingStartMinute) as? Int ?? 20 * 60
        storedFastingEndMinute = defaults.object(forKey: Key.fastingEndMinute) as? Int ?? 12 * 60
        storedFastingTrackedSince = (defaults.object(forKey: Key.fastingTrackedSince) as? Double).map { Date(timeIntervalSince1970: $0) }
        storedFastingLegacyMigrated = defaults.object(forKey: Key.fastingLegacyMigrated) as? Bool ?? false
        storedWaterGoalOverrideML = defaults.object(forKey: Key.waterGoalOverrideML) as? Double
        storedWeightGoalOverrideKg = defaults.object(forKey: Key.weightGoalOverrideKg) as? Double
        storedWeightGoalStartKg = defaults.object(forKey: Key.weightGoalStartKg) as? Double
        // Grams by default: the owner asked to always be able to type 150
        // for 150 g, never 1,5 (see FoodLogCore/ServingAmount.swift).
        storedQuantityInputMode = (defaults.string(forKey: Key.quantityInputMode))
            .flatMap(QuantityInputMode.init(rawValue:)) ?? .amount
    }

    var hapticsEnabled: Bool {
        get { storedHaptics }
        set {
            storedHaptics = newValue
            defaults.set(newValue, forKey: Key.haptics)
        }
    }

    /// Celebratory animations (level-up, streak milestone, challenge done).
    /// Reduce Motion always wins over this.
    var celebrationsEnabled: Bool {
        get { storedCelebrations }
        set {
            storedCelebrations = newValue
            defaults.set(newValue, forKey: Key.celebrations)
        }
    }

    /// Pre-select the meal from Garmin's meal windows (design D4).
    var useGarminMealWindows: Bool {
        get { storedGarminMealWindows }
        set {
            storedGarminMealWindows = newValue
            defaults.set(newValue, forKey: Key.garminMealWindows)
        }
    }

    /// How a quantity field is typed for a serving with a known gram/ml
    /// size: the amount in g/ml, or a multiplier of the serving. The last
    /// choice made on any quantity field sticks (`ServingQuantityField`).
    var quantityInputMode: QuantityInputMode {
        get { storedQuantityInputMode }
        set {
            storedQuantityInputMode = newValue
            defaults.set(newValue.rawValue, forKey: Key.quantityInputMode)
        }
    }

    var czechOnlySearch: Bool {
        get { storedCzechOnlySearch }
        set {
            storedCzechOnlySearch = newValue
            defaults.set(newValue, forKey: Key.czechOnlySearch)
        }
    }

    /// Let the Czech offline database download over cellular, not just
    /// Wi-Fi (add-offline-czech-food-index D3). Low Data Mode still wins.
    var offlineIndexAllowsCellular: Bool {
        get { storedOfflineIndexAllowsCellular }
        set {
            storedOfflineIndexAllowsCellular = newValue
            defaults.set(newValue, forKey: Key.offlineIndexAllowsCellular)
        }
    }

    // MARK: Fasting (redesign-fasting-schedule)
    //
    // Raw values only; the `FastingSchedule` built from them lives in
    // AppPreferences+Fasting.swift. Any user edit also marks the one-time
    // legacy migration as done, so a migration still in flight can never
    // overwrite a choice the user just made.

    /// Turning fasting ON (re)starts kept/broken tracking from now: days
    /// while it was off were never meant as fasts and aren't judged.
    var fastingEnabled: Bool {
        get { storedFastingEnabled }
        set {
            if newValue, !storedFastingEnabled {
                fastingTrackedSince = Date()
            }
            storedFastingEnabled = newValue
            defaults.set(newValue, forKey: Key.fastingEnabled)
            fastingLegacyMigrated = true
        }
    }

    /// Minute of the day the fast starts, `0..<1440`.
    var fastingStartMinute: Int {
        get { storedFastingStartMinute }
        set {
            storedFastingStartMinute = newValue
            defaults.set(newValue, forKey: Key.fastingStartMinute)
            fastingLegacyMigrated = true
        }
    }

    /// Minute of the day the fast ends, `0..<1440`.
    var fastingEndMinute: Int {
        get { storedFastingEndMinute }
        set {
            storedFastingEndMinute = newValue
            defaults.set(newValue, forKey: Key.fastingEndMinute)
            fastingLegacyMigrated = true
        }
    }

    /// Windows that started before this aren't judged kept or broken.
    var fastingTrackedSince: Date? {
        get { storedFastingTrackedSince }
        set {
            storedFastingTrackedSince = newValue
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: Key.fastingTrackedSince)
            } else {
                defaults.removeObject(forKey: Key.fastingTrackedSince)
            }
        }
    }

    /// Whether `fasting-sessions.json` has been read once (task 1.3).
    var fastingLegacyMigrated: Bool {
        get { storedFastingLegacyMigrated }
        set {
            storedFastingLegacyMigrated = newValue
            defaults.set(newValue, forKey: Key.fastingLegacyMigrated)
        }
    }

    // MARK: Goals (sync-weight-hydration-with-garmin D5)
    //
    // Raw optional values; `nil` means "use Garmin's goal". The domain
    // `GoalSource` built from them lives in AppPreferences+Goals.swift, like
    // fasting's. Local only -- never written back to Garmin (proposal
    // non-goal).

    /// Water goal override in ml.
    var waterGoalOverrideML: Double? {
        get { storedWaterGoalOverrideML }
        set {
            storedWaterGoalOverrideML = newValue
            setOptional(newValue, forKey: Key.waterGoalOverrideML)
        }
    }

    /// Weight target override in kg.
    var weightGoalOverrideKg: Double? {
        get { storedWeightGoalOverrideKg }
        set {
            storedWeightGoalOverrideKg = newValue
            setOptional(newValue, forKey: Key.weightGoalOverrideKg)
        }
    }

    /// Starting weight override in kg (the progress bar's left end).
    var weightGoalStartKg: Double? {
        get { storedWeightGoalStartKg }
        set {
            storedWeightGoalStartKg = newValue
            setOptional(newValue, forKey: Key.weightGoalStartKg)
        }
    }

    private func setOptional(_ value: Double?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
