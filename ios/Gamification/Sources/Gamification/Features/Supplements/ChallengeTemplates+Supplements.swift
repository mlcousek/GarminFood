// ChallengeTemplates+Supplements.swift
//
// add-supplements D9, task 6.3: four long-running challenges about the
// supplement stack, appended to `ChallengeCatalog.all` and evaluated from
// the supplement digest (`ChallengeKind.supplementDays`,
// `ChallengeEngine.progress(... supplements:)`).
//
// They are in the rotation ONLY while the feature is enabled with at least
// one product (`ChallengeRotationPolicy.supplements` active), and a
// slot-time rule only once that slot was completed at least once in the
// last 14 days (the same "data must exist" rule every signal template
// follows). Their static weight is 0: they are not part of "complete every
// challenge" (an optional feature can't be required for a core badge) and
// don't move the rotation-weighted mean reward XPBudget assumes. Their XP
// is ordinary challenge XP: the one challenge slot pays about the same
// whichever template fills it, so offering these doesn't add XP per day.
//
// Ids are persisted (ChallengeStore / ChallengeHistoryStore) -- never
// rename one. Text: English here, Czech per id in cs.lproj/Catalog.strings
// (CatalogL10n; these kinds are not `isSignalBased`).
//
// Depends on: ChallengeTemplate/ChallengeKind, CatalogL10n, FoodLogCore
// (SupplementSignals). Depended on by: ChallengeCatalog.all,
// ChallengeEngine, ChallengeRotationPolicy.

import Foundation
import FoodLogCore

/// A rule a supplement day satisfies (or not), evaluated from the digest.
public enum SupplementDayRule: Sendable, Equatable {
    /// Every planned item of the day was taken.
    case stackComplete
    /// The slot (`TimeSlot.key`) was completed before hour:minute.
    case slotBefore(slotKey: String, hour: Int, minute: Int)

    public func holds(on day: SupplementDaySignal) -> Bool {
        switch self {
        case .stackComplete:
            return day.status == .complete
        case .slotBefore(let slotKey, let hour, let minute):
            guard let completed = day.slotMinutes[slotKey] else { return false }
            return completed < hour * 60 + minute
        }
    }

    /// Whether the rule can be offered: the digest is active and, for a
    /// slot rule, the slot was completed on one of the last `lookbackDays`.
    public func isOffered(by signals: SupplementSignals, lookbackDays: Int) -> Bool {
        guard signals.isActive else { return false }
        switch self {
        case .stackComplete:
            return true
        case .slotBefore(let slotKey, _, _):
            let earliest = SupplementDate.adding(-(lookbackDays - 1), to: signals.today) ?? signals.today
            return signals.days.contains { $0.day >= earliest && $0.day <= signals.today && $0.slotMinutes[slotKey] != nil }
        }
    }
}

extension ChallengeCatalog {
    static let supplementTemplates: [ChallengeTemplate] = [
        ChallengeTemplate(
            id: "supp-stack-5",
            title: CatalogL10n.title("supp-stack-5", "Stack Week"),
            subtitle: CatalogL10n.subtitle("supp-stack-5", "Take every planned supplement on 5 days."),
            category: .streakExtension, windowDays: 7, xpReward: 90,
            kind: .supplementDays(.stackComplete, minDays: 5)
        ),
        ChallengeTemplate(
            id: "supp-stack-10",
            title: CatalogL10n.title("supp-stack-10", "Steady Stack"),
            subtitle: CatalogL10n.subtitle("supp-stack-10", "Take every planned supplement on 10 days."),
            category: .streakExtension, windowDays: 14, xpReward: 120,
            kind: .supplementDays(.stackComplete, minDays: 10)
        ),
        ChallengeTemplate(
            id: "supp-evening-22",
            title: CatalogL10n.title("supp-evening-22", "Evening Routine"),
            subtitle: CatalogL10n.subtitle("supp-evening-22", "Take your evening supplements before 22:00 on 3 days."),
            category: .streakExtension, windowDays: 7, xpReward: 70,
            kind: .supplementDays(.slotBefore(slotKey: TimeSlot.evening.key, hour: 22, minute: 0), minDays: 3)
        ),
        ChallengeTemplate(
            id: "supp-morning-9",
            title: CatalogL10n.title("supp-morning-9", "Morning Kick-off"),
            subtitle: CatalogL10n.subtitle("supp-morning-9", "Take your morning supplements before 9:00 on 5 days."),
            category: .streakExtension, windowDays: 7, xpReward: 80,
            kind: .supplementDays(.slotBefore(slotKey: TimeSlot.morning.key, hour: 9, minute: 0), minDays: 5)
        ),
    ]

    /// The supplement template ids (for tests and the rotation policy).
    public static var supplementTemplateIds: Set<String> { Set(supplementTemplates.map(\.id)) }
}
