// ConfirmedLogRelay.swift
//
// fix-review-findings-2026-09 finding 1: a food logged WITHOUT a screen --
// the four quick-pick Controls, the "Log usual food" and "Log <food>" Siri
// shortcuts (Shared/QuickPickLoggingIntents.swift, GarminFood/Shortcuts/)
// -- used to commit the entry and stop there. The in-app confirm screens
// call `GamificationEngine.handleLogConfirmed` as a deliberate second step
// (GamificationEngine.swift's header), so an intent log earned no XP, no
// lifetime stats, no challenge progress/rewards and no moment. Nothing
// later made up for it either: `GamificationEngine.refresh()` recomputes
// display state but never awards.
//
// Why a relay and not a direct call: the intents live in `Shared/`, which
// is also compiled into the widget extension, and the widget does not link
// the Gamification package (project.yml) -- so they cannot name the
// engine. And an intent can reach `perform()` before the app's
// `AppEnvironment` (which owns the engine) exists, so a plain weak
// observer (like `AppServices.logObserver`) could silently drop the award.
// The relay holds a reported log until the app attaches its handler, then
// hands each log over EXACTLY ONCE (deduplicated by the committed entry's
// id), so the award path is the same `handleLogConfirmed` the in-app
// confirm uses, never skipped and never doubled.
//
// In-memory on purpose: an intent that logs always runs in the APP's own
// process (`openAppWhenRun`, QuickPickLoggingIntents.swift's header), the
// same process whose `AppEnvironment` attaches. Nothing persists across a
// relaunch, so nothing can be replayed twice after one.
//
// `QuickPickCommit` is the testable half of `QuickPickControlAction.
// performLog`: commit the resolved target, then report it here.
//
// Depended on by: Shared/AppServices.swift (the one relay per process),
// Shared/QuickPickLoggingIntents.swift, GarminFood/Shortcuts/
// LogNamedFoodIntent.swift, GarminFood/App/AppEnvironment.swift (attach).
// Tests: ConfirmedLogRelayTests.

import Foundation
import GarminKit

/// One durably committed log, as the gamification award needs it.
public struct ConfirmedLog: Sendable, Equatable, Identifiable {
    /// The committed outbox (or local) entry's id -- the dedup key.
    public let id: UUID
    /// The entry's calories, `nil` when unknown (lifetime-calories ledger).
    public let calories: Double?
    /// When it was logged; the award is dated by this, not by delivery.
    public let loggedAt: Date

    public init(id: UUID, calories: Double?, loggedAt: Date) {
        self.id = id
        self.calories = calories
        self.loggedAt = loggedAt
    }
}

/// Hands screenless logs to the app's gamification handler exactly once.
@MainActor
public final class ConfirmedLogRelay {
    public typealias Handler = @MainActor (ConfirmedLog) async -> Void

    private var handler: Handler?
    private var pending: [ConfirmedLog] = []
    private var handedOver: Set<UUID> = []
    private var isDraining = false

    public init() {}

    /// Logs reported but not yet handed to a handler.
    public var pendingCount: Int { pending.count }

    /// Reports a committed log. Handed over now if a handler is attached,
    /// otherwise held until `attach`. A log already reported (same id) is
    /// ignored.
    public func report(_ log: ConfirmedLog) async {
        guard !handedOver.contains(log.id), !pending.contains(where: { $0.id == log.id }) else { return }
        pending.append(log)
        await drain()
    }

    /// Attaches the handler (the app does this once, at launch) and hands
    /// over everything reported before it, in order.
    public func attach(_ handler: @escaping Handler) async {
        self.handler = handler
        await drain()
    }

    private func drain() async {
        guard let handler, !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        // Re-checked each turn: a report arriving while the handler runs is
        // appended and picked up here, never handed over concurrently.
        while !pending.isEmpty {
            let next = pending.removeFirst()
            handedOver.insert(next.id)
            await handler(next)
        }
    }
}

extension QuickPickLogTarget {
    /// The logged amount's calories, the same way the confirm screen
    /// computes them (`serving.calories * quantity`); `nil` when unknown.
    public var calories: Double? {
        switch self {
        case .catalog(_, let serving, let numberOfUnits):
            return serving.calories.map { $0 * numberOfUnits }
        case .custom(let draft, let quantity):
            return draft.asFood().servings.first?.calories.map { $0 * quantity }
        }
    }
}

/// Commits a resolved quick pick and reports it to the relay -- the part of
/// `QuickPickControlAction.performLog` that must award exactly like an
/// in-app confirm.
public enum QuickPickCommit {
    @MainActor
    @discardableResult
    public static func commit<Logging: FoodLogging>(
        _ target: QuickPickLogTarget,
        using logging: Logging,
        mealType: MealType,
        date: String,
        now: Date = Date(),
        relay: ConfirmedLogRelay
    ) async throws -> OutboxEntry {
        let entry: OutboxEntry
        switch target {
        case .catalog(let food, let serving, let numberOfUnits):
            entry = try await logging.confirm(
                food: food,
                serving: serving,
                numberOfUnits: numberOfUnits,
                mealType: mealType,
                date: date,
                now: now,
                regionCode: nil,
                languageCode: nil
            )
        case .custom(let draft, let quantity):
            // Same call the confirm screen makes for a custom food.
            entry = try await logging.confirmCustomFood(
                draft,
                quantity: quantity,
                mealType: mealType,
                date: date,
                now: now,
                regionCode: nil,
                languageCode: nil
            ).entry
        }
        // Only after the durable commit: a failed commit awards nothing.
        await relay.report(ConfirmedLog(id: entry.id, calories: target.calories, loggedAt: now))
        return entry
    }
}
