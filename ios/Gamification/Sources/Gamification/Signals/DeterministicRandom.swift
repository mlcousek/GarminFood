// DeterministicRandom.swift
//
// A tiny seeded, non-cryptographic generator: the same seed string always
// yields the same sequence, on every device and OS version (no
// `Array.shuffled()`/`SystemRandomNumberGenerator`). Wave-2 features use it
// so a bingo card or a boss pick for a given week is stable across launches
// and never has to be persisted just to stay the same, and
// `ChallengeRotation.pickNext` uses its weighted pick.
//
// Algorithm: djb2-style xor hash of the seed's unicode scalars as the
// state, then a 64-bit LCG step (`state * 6364136223846793005 + 1`) per
// draw, index = `state % count` -- exactly what
// `DailyChallengeEngine.seededShuffle` already does. That private copy is
// deliberately left untouched so today's daily-challenge picks do not
// change; `DeterministicRandomTests` pins that both produce the same
// sequence.
//
// Depended on by: ChallengeRotation (weighted pick), wave-2 features.

import Foundation

public struct DeterministicRandom: Sendable {
    public private(set) var state: UInt64

    public init(seed: String) {
        self.state = DeterministicRandom.hash(seed)
    }

    /// djb2 variant: `h = h * 33 ^ scalar`, starting at 5381.
    public static func hash(_ seed: String) -> UInt64 {
        seed.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) ^ UInt64($1.value) }
    }

    /// Advances the LCG and returns the new state.
    public mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }

    /// A value in `0..<upperBound`; 0 when `upperBound <= 0`.
    public mutating func nextInt(below upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    /// Index into `weights`, chosen with probability proportional to its
    /// weight. Zero/negative weights are never picked; `nil` when no weight
    /// is positive.
    public mutating func weightedIndex(_ weights: [Int]) -> Int? {
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return nil }
        var ticket = nextInt(below: total)
        for (index, weight) in weights.enumerated() where weight > 0 {
            if ticket < weight { return index }
            ticket -= weight
        }
        return nil
    }

    /// `items[weightedIndex(items.map(weight))]`.
    public mutating func weightedPick<T>(_ items: [T], weight: (T) -> Int) -> T? {
        weightedIndex(items.map(weight)).map { items[$0] }
    }

    /// A deterministic permutation (same draw order as
    /// `DailyChallengeEngine.seededShuffle`: pick an index, remove, repeat).
    /// The caller decides the input order; sort it first for stability.
    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var pool = items
        var result: [T] = []
        result.reserveCapacity(pool.count)
        while !pool.isEmpty {
            result.append(pool.remove(at: nextInt(below: pool.count)))
        }
        return result
    }
}
