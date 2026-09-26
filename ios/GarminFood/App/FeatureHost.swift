// FeatureHost.swift
//
// add-gamification-signals D7: the app-side runner of the gamification
// plug-in seam. It (1) builds the `SignalsSnapshot` every feature reads --
// from LOCAL stores only (usage history, food cache, cached Garmin day-log
// digests, activity cache, provenance, water, the Garmin health cache, day
// notes, fasting, goal status) via FoodLogCore's pure `DaySignalsBuilder`,
// never the network -- and (2) runs every registered `GamificationFeature`
// and applies what it returns: XP/freeze grants through the idempotent
// `RewardLedger`, badge unlocks through the existing `AchievementStore`
// (+ `XPAward.achievementBonus`, exactly like core achievements), and
// moments into `GamificationEngine.pendingMoments`.
//
// Called by `GamificationEngine.refresh` and at the end of
// `handleLogConfirmed` -- i.e. after the entry is already committed to the
// outbox, off the confirm action's critical path, with no network await.
//
// A misbehaving feature is contained: a grant outside its own
// `<featureId>.` key namespace or a badge id it doesn't declare is dropped
// and logged to `DiagnosticsLog` (category "features"), a failed ledger/
// store write is logged, and the other features still run. (`update` is
// non-throwing by protocol, so there is no error to catch from it.)
//
// Secret badges get NO generic `.achievementUnlocked` moment: their feature
// supplies its own `.secret` reveal, so a secret title is never shown twice
// or before the reveal (design D7).
//
// Depends on: Gamification (seam, registry, ledger, badges), FoodLogCore
// (stores, DaySignalsBuilder), GarminKit (DiagnosticsLog), AppPreferences,
// GamificationSignalsSync (cached first name).
//
// add-standalone-mode 7.1 (D11): in standalone mode the snapshot is built
// from `SignalsInput.standalone` -- no activities, active kcal or Garmin
// water/weigh-ins even if their caches still hold Garmin-era data, weigh-ins
// from this phone -- so nothing needing activities is ever offered, and
// `visibleBadgeCatalog` hides Garmin-only badges not yet earned
// (`StandaloneAvailability`).
// Depended on by: GamificationEngine; Progress/Today slot views (via
// `feature(_:)` and `summaries`).

import Foundation
import Observation
import GarminKit
import FoodLogCore
import Gamification

@MainActor
@Observable
final class FeatureHost {
    /// The local stores the snapshot is built from.
    struct Sources {
        let usageHistory: UsageHistoryStore
        let foodCache: FoodCacheStore
        let dayLogDigests: DayLogDigestStore
        let activityCache: ActivityCacheStore
        let provenance: FoodProvenanceStore
        let hydration: HydrationStore
        let garminHealthCache: GarminHealthCacheStore
        let dayNotes: DayNoteStore
        let preferences: AppPreferences
        /// This phone's weigh-ins (standalone mode's weight signal).
        let weight: WeightStore
    }

    struct Outcome {
        var moments: [GamificationMoment] = []
        /// Set when any XP was added (to refresh the level display).
        var levelProgress: LevelCurve.Progress?
        var unlockedBadges = false
    }

    /// Every registered feature, in registry order. One instance each per
    /// process -- features are actors that own their stores.
    let features: [any GamificationFeature]
    /// Core achievements + every feature's badges (`BadgeRegistry`).
    let badgeCatalog: [AchievementDefinition]
    /// The latest hub-card summary per feature id.
    private(set) var summaries: [String: FeatureSummary] = [:]
    /// Bumped after every completed pass. Detail screens key their reload
    /// on it, because a pass can change what they show (e.g. body progress
    /// after a weigh-in) without changing the feature's hub summary.
    private(set) var completedRuns = 0

    private let sources: Sources
    private let ledger: RewardLedger
    @ObservationIgnored private var isRunning = false

    init(
        sources: Sources,
        ledger: RewardLedger = RewardLedger(),
        features: [any GamificationFeature] = GamificationFeatureRegistry.makeAll()
    ) {
        self.sources = sources
        self.ledger = ledger
        self.features = features
        self.badgeCatalog = BadgeRegistry.badges(features: features)
    }

    /// A registered feature by concrete type, for a slot's detail screen
    /// (`featureHost.feature(WeeklyBingoFeature.self)`).
    /// add-standalone-mode 7.1: the effective data mode is standalone.
    var isStandalone: Bool { sources.preferences.isStandalone }

    /// The badges the Achievements screen lists (Garmin-only ones not yet
    /// earned are hidden in standalone mode).
    func visibleBadgeCatalog(unlockedIds: Set<String>) -> [AchievementDefinition] {
        StandaloneAvailability.visibleBadges(badgeCatalog, isStandalone: isStandalone, unlockedIds: unlockedIds)
    }

    func feature<T: GamificationFeature>(_ type: T.Type) -> T? {
        for feature in features {
            if let match = feature as? T { return match }
        }
        return nil
    }

    /// add-weekly-boss-and-streak-freezes D4: every streak-freeze grant the
    /// ledger has recorded (bingo full cards, boss defeats), for the freeze
    /// balance. The ledger stays private to this host -- one instance per
    /// process -- so the engine reads it through here.
    func freezeGrants() async -> [RewardLedger.FreezeGrant] {
        await ledger.freezeGrants()
    }

    // MARK: - Snapshot (local reads only)

    func buildSnapshot(goalStatuses: [DailyGoalStatus], now: Date, calendar: Calendar = .current) async -> SignalsSnapshot {
        let events = await sources.usageHistory.all()
        let foods = await sources.foodCache.all()
        let digests = await sources.dayLogDigests.all()
        let activityDays = await sources.activityCache.all()
        let provenance = await sources.provenance.all()
        let hydration = await sources.hydration.all()
        let health = await sources.garminHealthCache.current()
        let notes = await sources.dayNotes.all()
        let preferences = sources.preferences

        var fastingDays: [FastingDay] = []
        if let schedule = preferences.activeFastingSchedule {
            fastingDays = FastingDayEvaluator.history(
                schedule: schedule,
                days: 42,
                logTimestamps: FastingLogMoments.moments(from: events, calendar: calendar),
                trackedSince: preferences.fastingTrackedSince,
                now: now,
                calendar: calendar
            )
        }

        var goalStatusByDay: [String: SignalGoalStatus] = [:]
        for status in goalStatuses {
            goalStatusByDay[status.date] = SignalGoalStatus(
                metCalorieGoal: status.metCalorieGoal,
                metProteinGoal: status.metProteinGoal,
                metCarbGoal: status.metCarbGoal,
                metFatGoal: status.metFatGoal
            )
        }

        // The EFFECTIVE weight goal (ProfileSignals' contract): the local
        // override, else Garmin's cached nutrition-settings plan -- the same
        // resolution the Weight screen uses (`WeightLoader.goal`). Sport &
        // body milestones read it (add-sport-and-body-achievements).
        let standalone = preferences.isStandalone
        let localWeighIns = standalone ? await sources.weight.all() : []
        let effectiveGoal = standalone
            ? WeightAndWaterOverview.standaloneWeightGoal(
                targetOverrideKg: preferences.weightGoalOverrideKg,
                startOverrideKg: preferences.weightGoalStartKg,
                localEntries: localWeighIns
            )
            : WeightAndWaterOverview.weightGoal(
                snapshot: health,
                targetSource: preferences.weightGoalSource,
                startOverrideKg: preferences.weightGoalStartKg
            )
        let weightGoal = effectiveGoal.map { WeightGoalSignal(startKg: $0.startKg, targetKg: $0.targetKg) }

        let input = SignalsInput(
            events: events,
            foods: foods,
            digests: digests,
            activityDays: activityDays,
            provenance: provenance,
            localWaterMLByDay: SignalsInput.localWaterByDay(hydration, calendar: calendar),
            garminWaterByDay: SignalsInput.garminWaterByDay(health),
            defaultWaterGoalML: preferences.waterGoalOverrideML,
            weighInKgByDay: SignalsInput.weighInKgByDay(health),
            fastingDays: fastingDays,
            notes: notes,
            goalStatusByDay: goalStatusByDay,
            profile: ProfileSignals(firstName: GamificationSignalsSync.cachedFirstName(), weightGoal: weightGoal)
        )
        let effectiveInput = standalone ? input.standalone(localWeighIns: localWeighIns, calendar: calendar) : input
        return DaySignalsBuilder.build(input: effectiveInput, today: now, calendar: calendar)
    }

    // MARK: - Running features

    func run(
        snapshot: SignalsSnapshot,
        streak: StreakEngine.Status,
        level: Int,
        isConfirmPath: Bool,
        now: Date,
        xpStore: XPStore,
        achievementStore: AchievementStore,
        calendar: Calendar = .current
    ) async -> Outcome {
        // A confirm and a refresh can overlap; the ledger would keep them
        // correct, but one pass at a time keeps the moments tidy.
        guard !isRunning else { return Outcome() }
        isRunning = true
        defer {
            isRunning = false
            completedRuns += 1
        }

        var outcome = Outcome()
        var unlocked = await achievementStore.unlockedIds()
        let levelBefore = await xpStore.currentProgress().level
        var xpChanged = false
        let context = FeatureContext(
            snapshot: snapshot,
            now: now,
            calendar: calendar,
            streak: streak,
            level: level,
            unlockedBadgeIds: unlocked,
            isConfirmPath: isConfirmPath
        )

        for feature in features {
            let id = feature.featureId
            let update = await feature.update(context)
            summaries[id] = update.summary

            // Grants: only inside the feature's own key namespace.
            let grants = update.grants.filter { $0.key.hasPrefix(id + ".") }
            if grants.count != update.grants.count {
                DiagnosticsLog.log(.error, category: "features", "\(id): dropped \(update.grants.count - grants.count) grant(s) outside the '\(id).' key namespace")
            }
            if !grants.isEmpty {
                do {
                    let result = try await ledger.apply(grants, day: snapshot.today, now: now, xpStore: xpStore)
                    if result.xpAwarded > 0 { xpChanged = true }
                } catch {
                    DiagnosticsLog.log(.error, category: "features", "\(id): couldn't apply rewards: \(error)")
                }
            }

            // Badges: only ids the feature declares, not yet unlocked.
            let declared = Dictionary(feature.badges.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let requested = update.unlockBadgeIds.filter { declared[$0] != nil && !unlocked.contains($0) }
            if requested.count != update.unlockBadgeIds.filter({ !unlocked.contains($0) }).count {
                DiagnosticsLog.log(.error, category: "features", "\(id): dropped badge id(s) it does not declare")
            }
            var badgeWriteFailed = false
            if !requested.isEmpty {
                do {
                    let recorded = try await achievementStore.unlock(ids: requested, now: now)
                    for badgeId in recorded {
                        unlocked.insert(badgeId)
                        outcome.unlockedBadges = true
                        if (try? await xpStore.recordChallengeCompletion(xp: XPAward.achievementBonus)) != nil {
                            xpChanged = true
                        }
                        if let definition = declared[badgeId], !definition.isSecret {
                            outcome.moments.append(.achievementUnlocked(
                                title: definition.title,
                                badgeSymbol: definition.badgeSymbol,
                                rarity: definition.rarity
                            ))
                        }
                    }
                } catch {
                    badgeWriteFailed = true
                    DiagnosticsLog.log(.error, category: "features", "\(id): couldn't record badge unlocks: \(error)")
                }
            }

            // A `.secret` reveal IS its badge unlock (it replaces the generic
            // moment, see this file's header). If the unlock couldn't be
            // recorded -- typically `unlockedIds()` read as empty because the
            // achievements file isn't readable yet, so already-found secrets
            // looked new -- don't show the reveal: it may name old secrets
            // and claims XP nothing paid. The next run reveals what's real.
            let moments = badgeWriteFailed ? update.moments.filter { $0.style != .secret } : update.moments
            outcome.moments.append(contentsOf: moments.map { GamificationMoment.feature($0) })
        }

        if xpChanged {
            let progress = await xpStore.currentProgress()
            outcome.levelProgress = progress
            if progress.level > levelBefore {
                outcome.moments.append(.levelUp(newLevel: progress.level))
            }
        }
        return outcome
    }
}
