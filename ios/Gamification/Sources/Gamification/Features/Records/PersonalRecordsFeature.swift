// PersonalRecordsFeature.swift
//
// add-journeys-and-records design D6/D7: the "records" gamification feature
// (replaces the add-gamification-signals stub; the registry already creates
// it with `init(directory:)`). Eight Garmin-style personal records -- most
// protein in a day, longest fast, ... -- each with its value, the day it
// was set and the previous best (see `PersonalRecordCatalog`).
//
// Per run (`update`): load `RecordsStore`, run the pure `RecordsEvaluator`,
// save, then return
//   - one 20 XP grant per announced PR, keyed `records.<record>.<day>`
//     (re-emitted from the history list every run; the `RewardLedger`
//     applies each key once). NOTE: design D6 wrote `record.<id>.<day>`;
//     the host drops any grant outside the feature's own `records.`
//     namespace, so the key uses the feature id;
//   - the record badges earned so far (the host skips unlocked ones);
//   - at most ONE "New PR!" moment (style `.record`) naming every record
//     beaten in this run -- none on the first (silent baseline) run;
//   - the hub-card summary.
//
// A store that exists but can't be read (before first unlock) skips the run
// entirely -- re-baselining over it would lose the records.
//
// Depends on: RecordsEvaluator, RecordsStore, PersonalRecordCatalog, XPAward.
// Depended on by: GamificationFeatureRegistry, the app's Records screens
// (via `records()` / `recentRecords()`).

import Foundation
import FoodLogCore

/// One record as the UI shows it.
public struct PersonalRecordStatus: Sendable, Equatable, Identifiable {
    public let definition: PersonalRecordDefinition
    public var id: String { definition.id.rawValue }
    public let value: Double?
    public let day: String?
    public let previousValue: Double?
    public let previousDay: String?
    /// `true` when this record's latest PR was announced within the last
    /// 7 days (trophy in the list).
    public let isRecentPR: Bool

    /// A record without a value is hidden, never shown as zero.
    public var isVisible: Bool { value != nil }

    public var valueText: String? {
        value.map { PersonalRecordFormat.value($0, unit: definition.unit) }
    }

    public var previousValueText: String? {
        previousValue.map { PersonalRecordFormat.value($0, unit: definition.unit) }
    }
}

public actor PersonalRecordsFeature: GamificationFeature {
    public static let id = "records"

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { PersonalRecordCatalog.badges }

    let directory: URL
    private let store: RecordsStore
    /// The last snapshot's window days (for "recent PR" in `records()`).
    private var windowDays: [String] = []

    public init(directory: URL) {
        self.directory = directory
        self.store = RecordsStore(directory: directory)
    }

    /// The grant key of a PR (inside this feature's namespace).
    public static func grantKey(_ id: PersonalRecordId, day: String) -> String {
        "\(Self.id).\(id.rawValue).\(day)"
    }

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        let loaded = await store.load()
        guard loaded.isReadable else { return .empty }

        windowDays = context.snapshot.windowDays
        let result = RecordsEvaluator.evaluate(state: loaded.state, snapshot: context.snapshot)
        do {
            try await store.save(result.state)
        } catch {
            // Not saved: nothing announced now, so the next run announces it once.
            return FeatureUpdate(summary: Self.summary(state: loaded.state))
        }

        var grants: [RewardGrant] = []
        for event in result.state.history ?? [] {
            guard let rawId = event.recordId, let id = PersonalRecordId(rawValue: rawId), let day = event.day else { continue }
            grants.append(RewardGrant(key: Self.grantKey(id, day: day), kind: .xp(XPAward.personalRecord)))
        }

        var moments: [FeatureMoment] = []
        if let moment = Self.moment(for: result.announced) {
            moments.append(moment)
        }
        return FeatureUpdate(
            grants: grants,
            unlockBadgeIds: RecordsEvaluator.earnedBadgeIds(result.state),
            moments: moments,
            summary: Self.summary(state: result.state)
        )
    }

    /// Every record in catalog order (hidden ones have `isVisible == false`).
    public func records() async -> [PersonalRecordStatus] {
        let state = await store.load().state
        let recent = Set(windowDays.suffix(7))
        return PersonalRecordCatalog.all.map { definition in
            let record = state.record(definition.id)
            let lastPR = (state.history ?? []).last { $0.recordId == definition.id.rawValue }
            return PersonalRecordStatus(
                definition: definition,
                value: record.current?.value,
                day: record.current?.day,
                previousValue: record.previous?.value,
                previousDay: record.previous?.day,
                isRecentPR: lastPR?.day.map { recent.contains($0) } ?? false
            )
        }
    }

    /// The last announced PRs, newest first.
    public func recentRecords() async -> [PersonalRecordEvent] {
        Array((await store.load().state.history ?? []).reversed())
    }

    // MARK: - Moment and summary

    /// One combined "New PR!" moment; the latest value per record.
    static func moment(for announced: [RecordsEvaluator.NewRecord]) -> FeatureMoment? {
        guard !announced.isEmpty else { return nil }
        var latest: [PersonalRecordId: RecordsEvaluator.NewRecord] = [:]
        for record in announced {
            latest[record.id] = record
        }
        let lines = PersonalRecordId.allCases.compactMap { id -> String? in
            guard let record = latest[id] else { return nil }
            let definition = PersonalRecordCatalog.definition(id)
            let name = definition.name
            let value = PersonalRecordFormat.value(record.value, unit: definition.unit)
            let previous = PersonalRecordFormat.value(record.previousValue, unit: definition.unit)
            return String(localized: "\(name): \(value) (previous \(previous))", bundle: .module, comment: "New PR moment line: record name, new value, previous value.")
        }
        return FeatureMoment(
            featureId: PersonalRecordsFeature.id,
            title: String(localized: "New PR!", bundle: .module, comment: "Moment title: a personal record was beaten."),
            message: lines.joined(separator: "\n"),
            symbol: "trophy.fill",
            style: .record,
            xpAwarded: announced.count * XPAward.personalRecord
        )
    }

    static func summary(state: RecordsState) -> FeatureSummary {
        let title = String(localized: "Personal records", bundle: .module, comment: "Hub card title for the personal records.")
        if let last = state.history?.last,
           let rawId = last.recordId, let id = PersonalRecordId(rawValue: rawId),
           let value = last.value {
            let definition = PersonalRecordCatalog.definition(id)
            let name = definition.name
            let text = PersonalRecordFormat.value(value, unit: definition.unit)
            return FeatureSummary(
                title: title,
                subtitle: String(localized: "Latest PR: \(name), \(text)", bundle: .module, comment: "Records hub card: the newest personal record and its value."),
                symbol: "trophy.fill"
            )
        }
        let count = PersonalRecordId.allCases.filter { state.record($0).current?.value != nil }.count
        return FeatureSummary(
            title: title,
            subtitle: String(localized: "Records tracked: \(count)", bundle: .module, comment: "Records hub card before any PR: how many records have a value."),
            symbol: "trophy.fill"
        )
    }
}
