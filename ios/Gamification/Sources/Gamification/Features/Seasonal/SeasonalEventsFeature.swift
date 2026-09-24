// SeasonalEventsFeature.swift
//
// add-seasonal-events: the "seasonal" gamification feature -- 12 Czech
// seasonal/holiday food events (SeasonalEventCatalog) with date windows,
// food quests matched by seasonal tags, a limited-edition badge each, and
// 50 XP per event per year. Replaces the empty stub registered by
// add-gamification-signals (design D7); `GamificationFeatureRegistry`
// still creates it with `init(directory:)`, so no shared file changes.
//
// Each run (FeatureHost, after every refresh/confirm; local reads only):
//   1. resolves the owner's first name (Garmin profile, else the last one
//      stored) -> name day (CzechNameDays); unknown = no name-day event;
//   2. for every event instance of last year and this year that has
//      started, unions fresh quest marks from the signals window with the
//      stored (sticky) ones;
//   3. grants `seasonal.event.<id>.<year>` (+50 XP) for a completed
//      instance and `...bonus.<questId>` (+25 XP) per bonus quest -- every
//      run, because `RewardLedger` makes them idempotent -- and requests the
//      event badge + collector badges (the host skips already-unlocked ids);
//   4. emits a moment only the first time an instance/bonus completes.
//
// The UI reads `bannerEvent`, `activeEvents`, `upcomingEvents` and
// `yearOverview` -- all computed from the store alone, so they work before
// this launch's first run.
//
// Depends on: GamificationFeature, SeasonalEventCatalog, SeasonalEvaluator,
// SeasonalStore, CzechNameDays, XPAward+Features.
// Depended on by: GamificationFeatureRegistry, the app's SeasonalBannerSlot /
// SeasonalSlotView / SeasonalEventsView.

import Foundation
import FoodLogCore

public actor SeasonalEventsFeature: GamificationFeature {
    public static let id = "seasonal"

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { SeasonalEventCatalog.badges }

    let directory: URL
    let store: SeasonalStore

    public init(directory: URL) {
        self.directory = directory
        self.store = SeasonalStore(directory: directory)
    }

    // MARK: - Grant keys (RewardLedger namespace "seasonal.")

    public static func completionGrantKey(eventId: String, year: Int) -> String {
        "\(id).event.\(eventId).\(year)"
    }

    public static func bonusGrantKey(eventId: String, year: Int, questId: String) -> String {
        "\(completionGrantKey(eventId: eventId, year: year)).bonus.\(questId)"
    }

    // MARK: - GamificationFeature

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        let today = SeasonalDate(date: context.now, calendar: context.calendar)
        let firstName = await resolveFirstName(profileName: context.snapshot.profile.firstName)
        let nameDay = CzechNameDays.nameDay(forFirstName: firstName)
        var update = FeatureUpdate()

        for year in [today.year - 1, today.year] {
            for event in SeasonalEventCatalog.all {
                guard let window = event.window(year: year, nameDay: nameDay), window.lowerBound <= today else { continue }
                let stored = await store.marks(eventId: event.id, year: year)
                let merged = SeasonalEvaluator.mergedMarks(
                    event: event,
                    year: year,
                    window: window,
                    snapshot: context.snapshot,
                    stored: stored
                )
                if merged.filter({ !$0.value.isEmpty }) != stored.filter({ !$0.value.isEmpty }) {
                    await store.setMarks(merged, eventId: event.id, year: year)
                }
                let title = event.displayTitle(firstName: firstName)

                if SeasonalEvaluator.isCompleted(event: event, marks: merged) {
                    update.grants.append(RewardGrant(
                        key: Self.completionGrantKey(eventId: event.id, year: year),
                        kind: .xp(XPAward.seasonalEventCompleted)
                    ))
                    if !context.unlockedBadgeIds.contains(event.badgeId), !update.unlockBadgeIds.contains(event.badgeId) {
                        update.unlockBadgeIds.append(event.badgeId)
                    }
                    let isNewYear = await store.recordCompletion(eventId: event.id, year: year)
                    if isNewYear {
                        let firstTime = await store.completedYears(eventId: event.id).count == 1
                        update.moments.append(FeatureMoment(
                            featureId: Self.id,
                            title: title,
                            message: firstTime
                                ? String(localized: "Event complete! Limited-edition badge earned.", bundle: .module, comment: "Seasonal event completed for the first time ever.")
                                : String(localized: "Event complete again! Another year in your collection.", bundle: .module, comment: "Seasonal event completed in a later year (badge already owned)."),
                            symbol: event.symbol,
                            style: .event,
                            xpAwarded: XPAward.seasonalEventCompleted
                        ))
                    }
                }

                for quest in event.bonusQuests where (merged[quest.id]?.count ?? 0) >= quest.target {
                    update.grants.append(RewardGrant(
                        key: Self.bonusGrantKey(eventId: event.id, year: year, questId: quest.id),
                        kind: .xp(SeasonalEventCatalog.bonusQuestXP)
                    ))
                    let wasDone = (stored[quest.id]?.count ?? 0) >= quest.target
                    if !wasDone {
                        update.moments.append(FeatureMoment(
                            featureId: Self.id,
                            title: quest.title,
                            message: String(
                                format: String(localized: "Bonus quest done: %@", bundle: .module, comment: "Seasonal bonus quest completed. %@ = event title."),
                                title
                            ),
                            symbol: event.symbol,
                            style: .event,
                            xpAwarded: SeasonalEventCatalog.bonusQuestXP
                        ))
                    }
                }
            }
        }

        let completed = await store.completedYears()
        for badgeId in SeasonalEvaluator.collectorBadgeIds(completedYears: completed, nameDay: nameDay)
        where !context.unlockedBadgeIds.contains(badgeId) {
            update.unlockBadgeIds.append(badgeId)
        }

        await store.pruneMarks(keepingFrom: today.year - 1)
        // A failed save costs at most a repeated moment next run: grants
        // are idempotent in RewardLedger and badges in AchievementStore.
        try? await store.save()

        update.summary = await summary(today: today, calendar: context.calendar, firstName: firstName)
        return update
    }

    // MARK: - UI reads

    /// Every event of `now`'s year, in window order.
    public func yearOverview(now: Date = Date(), calendar: Calendar = .current) async -> [SeasonalEventStatus] {
        let today = SeasonalDate(date: now, calendar: calendar)
        let firstName = await store.ownerFirstName()
        return await statuses(year: today.year, today: today, firstName: firstName)
    }

    /// Events inside their window today, ending soonest first.
    public func activeEvents(now: Date = Date(), calendar: Calendar = .current) async -> [SeasonalEventStatus] {
        await yearOverview(now: now, calendar: calendar)
            .filter { $0.phase == .active }
            .sorted { $0.end < $1.end }
    }

    /// Events in their "coming soon" teaser, including next year's first
    /// days (New Year's Day is teased from 29 December).
    public func upcomingEvents(now: Date = Date(), calendar: Calendar = .current) async -> [SeasonalEventStatus] {
        let today = SeasonalDate(date: now, calendar: calendar)
        let firstName = await store.ownerFirstName()
        var result: [SeasonalEventStatus] = []
        for year in [today.year, today.year + 1] {
            let yearStatuses = await statuses(year: year, today: today, firstName: firstName)
            result += yearStatuses.filter { $0.phase == .upcoming }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// The one event the Today banner shows (design D5): the active event
    /// ending soonest, else the nearest upcoming one.
    public func bannerEvent(now: Date = Date(), calendar: Calendar = .current) async -> SeasonalEventStatus? {
        if let active = await activeEvents(now: now, calendar: calendar).first { return active }
        return await upcomingEvents(now: now, calendar: calendar).first
    }

    /// The first event whose window starts after today (this year or next).
    public func nextEvent(now: Date = Date(), calendar: Calendar = .current) async -> SeasonalEventStatus? {
        let today = SeasonalDate(date: now, calendar: calendar)
        let firstName = await store.ownerFirstName()
        var result: [SeasonalEventStatus] = []
        for year in [today.year, today.year + 1] {
            let yearStatuses = await statuses(year: year, today: today, firstName: firstName)
            result += yearStatuses.filter { $0.start > today }
        }
        return result.min { $0.start < $1.start }
    }

    // MARK: - Helpers

    private func resolveFirstName(profileName: String?) async -> String? {
        let stored = await store.ownerFirstName()
        guard let profileName, !profileName.isEmpty else { return stored }
        if profileName != stored {
            await store.setOwnerFirstName(profileName)
        }
        return profileName
    }

    private func statuses(year: Int, today: SeasonalDate, firstName: String?) async -> [SeasonalEventStatus] {
        let nameDay = CzechNameDays.nameDay(forFirstName: firstName)
        var result: [SeasonalEventStatus] = []
        for event in SeasonalEventCatalog.all {
            let marks = await store.marks(eventId: event.id, year: year)
            let years = await store.completedYears(eventId: event.id)
            if let status = SeasonalEvaluator.status(
                event: event,
                year: year,
                today: today,
                nameDay: nameDay,
                firstName: firstName,
                marks: marks,
                completedYears: years
            ) {
                result.append(status)
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    private func summary(
        today: SeasonalDate,
        calendar: Calendar,
        firstName: String?
    ) async -> FeatureSummary? {
        var candidates: [SeasonalEventStatus] = []
        for year in [today.year, today.year + 1] {
            let yearStatuses = await statuses(year: year, today: today, firstName: firstName)
            candidates += yearStatuses
        }
        if let active = candidates.filter({ $0.phase == .active }).min(by: { $0.end < $1.end }) {
            let required = active.requiredQuests
            let done = required.filter(\.isDone).count
            return FeatureSummary(
                title: active.title,
                subtitle: String(
                    format: String(localized: "Quests: %1$lld/%2$lld", bundle: .module, comment: "Seasonal hub card: required quests done / total."),
                    done,
                    required.count
                ),
                fraction: required.isEmpty ? nil : Double(done) / Double(required.count),
                symbol: active.symbol
            )
        }
        guard let next = candidates.filter({ $0.start > today }).min(by: { $0.start < $1.start }) else { return nil }
        let dateText = next.start.date(in: calendar)?.formatted(.dateTime.day().month(.wide)) ?? next.start.dayKey
        return FeatureSummary(
            title: next.title,
            subtitle: String(
                format: String(localized: "Starts %@", bundle: .module, comment: "Seasonal hub card: when the next event starts. %@ = a date like '8 November'."),
                dateText
            ),
            fraction: nil,
            symbol: next.symbol
        )
    }
}
