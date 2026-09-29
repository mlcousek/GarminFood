// RetryBackoff.swift
//
// The one exponential-backoff-with-jitter formula every durable queue in
// this project uses. It used to be `Outbox.backoffDelay` (internal), reused
// by `WeightOutbox` and `HydrationOutbox` from inside this module. The
// vault connection (openspec/changes/add-vault-connection, design D7, task
// 2.2) adds a fourth queue in another package (VaultKit's `DurableQueue`),
// so the formula is public here under a neutral name instead of being
// copied a fourth time.
//
// Behaviour-preserving: the body is exactly the old `Outbox.backoffDelay`,
// which now forwards here so the existing GarminKit tests keep calling it
// unchanged; `RetryBackoffTests` pins this type to the same values.
//
// Depended on by: Outbox.swift, WeightSync.swift, HydrationSync.swift and
// VaultKit's DurableQueue.swift.

import Foundation

public enum RetryBackoff {
    /// Exponential backoff with full jitter, capped at `cap`
    /// (add-garmin-auth-and-sync task 9.3: "exponential backoff with jitter
    /// capped at 8 s" -- the Garmin outboxes pass base 0.5, cap 8). `jitter`
    /// must be in `[0, 1)` and is clamped to `[0, 1]`; the caller supplies
    /// it so this stays a pure, deterministic function rather than depending
    /// on the global RNG. `attempt` is 1-based (the count AFTER the failing
    /// attempt).
    public static func delay(attempt: Int, jitter: Double, base: TimeInterval, cap: TimeInterval) -> TimeInterval {
        let exponent = Double(max(0, attempt - 1))
        let exponential = base * pow(2.0, exponent)
        let capped = min(exponential, cap)
        let clampedJitter = min(max(jitter, 0), 1)
        return capped * clampedJitter
    }
}
