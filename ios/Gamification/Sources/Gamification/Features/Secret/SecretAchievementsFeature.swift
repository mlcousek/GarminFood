// SecretAchievementsFeature.swift
//
// add-secret-achievements D3: the "secrets" gamification feature -- 15
// hidden achievements (SecretCatalog) whose rules (SecretRules) are pure
// functions of the 42-day `SignalsSnapshot`, plus the visible "Secret
// Keeper" once all 15 are found. Replaces the empty stub registered by
// add-gamification-signals; `GamificationFeatureRegistry` still creates it
// with `init(directory:)`, so no shared file changes.
//
// Each run (FeatureHost, after every refresh/confirm; local reads only):
//   1. evaluates every still-LOCKED secret against the snapshot (unlock
//      state is `AchievementStore`'s, handed in as
//      `context.unlockedBadgeIds` -- this feature keeps no store of its own,
//      which is also why the first run is retroactive over recent history);
//   2. requests the newly satisfied badge ids (+ the keeper when all 15
//      are then found); the host adds the standard `achievementBonus` per
//      unlock and suppresses its generic moment for `.secret` badges;
//   3. grants `secrets.<badge id>` (+50 XP, `XPAward.secretUnlocked`) for
//      every found secret on every run -- `RewardLedger` makes that
//      idempotent, and re-sending it heals a run whose grant failed to
//      apply;
//   4. emits ONE combined `.secret` reveal moment naming every secret
//      found in this run.
//
// Grant keys use the registered id "secrets." as prefix because
// FeatureHost drops grants outside the feature's own namespace (the
// design's `secret.<id>` spelling predates the stub's id).
//
// Depends on: GamificationFeature, SecretCatalog, SecretRules,
// XPAward+Features.
// Depended on by: GamificationFeatureRegistry, the app's SecretsSlotView.

import Foundation
import FoodLogCore

public actor SecretAchievementsFeature: GamificationFeature {
    public static let id = "secrets"

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { SecretCatalog.all }

    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The `RewardLedger` key of a secret's 50 XP, e.g.
    /// `secrets.secret.barista`.
    public static func grantKey(for secret: SecretAchievementId) -> String {
        "\(id).\(secret.badgeId)"
    }

    /// Total number of secrets (the keeper is not one of them).
    public static var secretCount: Int { SecretAchievementId.allCases.count }

    /// How many secrets `unlockedBadgeIds` contains (for the hub slot).
    public static func foundCount(unlockedBadgeIds: Set<String>) -> Int {
        SecretAchievementId.allCases.filter { unlockedBadgeIds.contains($0.badgeId) }.count
    }

    // MARK: - GamificationFeature

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        Self.evaluate(context)
    }

    /// The whole run as a pure function of the context (unit-tested).
    static func evaluate(_ context: FeatureContext) -> FeatureUpdate {
        let unlocked = context.unlockedBadgeIds
        let newlyFound = SecretAchievementId.allCases.filter { secret in
            !unlocked.contains(secret.badgeId)
                && SecretRules.holds(secret, in: context.snapshot, calendar: context.calendar)
        }
        let found = SecretAchievementId.allCases.filter { secret in
            unlocked.contains(secret.badgeId) || newlyFound.contains(secret)
        }

        var update = FeatureUpdate()
        update.grants = found.map { RewardGrant(key: grantKey(for: $0), kind: .xp(XPAward.secretUnlocked)) }
        update.unlockBadgeIds = newlyFound.map(\.badgeId)
        if found.count == secretCount, !unlocked.contains(SecretCatalog.keeperId) {
            update.unlockBadgeIds.append(SecretCatalog.keeperId)
        }
        if let moment = revealMoment(for: newlyFound) {
            update.moments = [moment]
        }
        update.summary = summary(found: found.count)
        return update
    }

    /// One moment naming every secret revealed in this run; `nil` for none.
    static func revealMoment(for secrets: [SecretAchievementId]) -> FeatureMoment? {
        guard let first = secrets.first else { return nil }
        let names = secrets.map { SecretCatalog.title(for: $0) }
        let title = secrets.count == 1
            ? String(localized: "Secret revealed!", bundle: .module, comment: "Reveal moment title when one secret achievement unlocks.")
            : String(localized: "Secrets revealed!", bundle: .module, comment: "Reveal moment title when several secret achievements unlock at once.")
        return FeatureMoment(
            featureId: Self.id,
            title: title,
            message: names.formatted(.list(type: .and)),
            symbol: secrets.count == 1 ? SecretCatalog.symbol(for: first) : "key.fill",
            style: .secret,
            xpAwarded: secrets.count * (XPAward.secretUnlocked + XPAward.achievementBonus)
        )
    }

    /// "Secrets" hub card: "Found: 3 of 15".
    static func summary(found: Int) -> FeatureSummary {
        FeatureSummary(
            title: String(localized: "Secrets", bundle: .module, comment: "Hub card title of the secret achievements feature."),
            subtitle: String(
                format: String(localized: "Found: %lld of %lld", bundle: .module, comment: "Secret achievements hub card: secrets found / total."),
                found,
                secretCount
            ),
            fraction: Double(found) / Double(secretCount),
            symbol: "key.fill"
        )
    }
}
