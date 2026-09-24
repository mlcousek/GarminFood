// DeterministicRandomTests.swift
//
// add-gamification-signals 5.2: the shared seeded generator is stable per
// seed, uses the same djb2 + LCG steps as `DailyChallengeEngine`'s private
// shuffle (pinned by recomputing the first draw by hand), and its weighted
// pick never selects a zero weight.

import XCTest
@testable import Gamification

final class DeterministicRandomTests: XCTestCase {
    func testSameSeedSameSequence() {
        var a = DeterministicRandom(seed: "2026-09-24")
        var b = DeterministicRandom(seed: "2026-09-24")
        let first = (0..<10).map { _ in a.next() }
        let second = (0..<10).map { _ in b.next() }
        XCTAssertEqual(first, second)

        var c = DeterministicRandom(seed: "2026-09-25")
        XCTAssertNotEqual(first, (0..<10).map { _ in c.next() })
    }

    func testMatchesTheDailyChallengeAlgorithm() {
        // Same formula as DailyChallengeEngine.seededShuffle, written out.
        let seed = "2026-W39"
        var hash = seed.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) ^ UInt64($1.value) }
        hash = hash &* 6364136223846793005 &+ 1
        var random = DeterministicRandom(seed: seed)
        XCTAssertEqual(random.next(), hash)
        XCTAssertEqual(DeterministicRandom.hash(""), 5381)
    }

    func testNextIntStaysInRange() {
        var random = DeterministicRandom(seed: "range")
        for _ in 0..<200 {
            let value = random.nextInt(below: 7)
            XCTAssertTrue((0..<7).contains(value))
        }
        XCTAssertEqual(random.nextInt(below: 0), 0)
    }

    func testWeightedPickSkipsZeroWeights() {
        var random = DeterministicRandom(seed: "weights")
        for _ in 0..<300 {
            let index = random.weightedIndex([0, 3, 0, 1])
            XCTAssertTrue(index == 1 || index == 3, "picked \(String(describing: index))")
        }
        XCTAssertNil(random.weightedIndex([0, 0]))
        XCTAssertNil(random.weightedIndex([]))
        XCTAssertNil(random.weightedPick(["a", "b"]) { _ in 0 })
    }

    func testWeightedPickRoughlyFollowsWeights() {
        var random = DeterministicRandom(seed: "distribution")
        var counts = [0, 0]
        for _ in 0..<4000 {
            if let index = random.weightedIndex([1, 3]) { counts[index] += 1 }
        }
        // Expected 1000 / 3000; generous bounds, the point is "weighted".
        XCTAssertGreaterThan(counts[1], counts[0] * 2)
        XCTAssertEqual(counts[0] + counts[1], 4000)
    }

    func testShuffledIsADeterministicPermutation() {
        var a = DeterministicRandom(seed: "shuffle")
        var b = DeterministicRandom(seed: "shuffle")
        let items = Array(0..<20)
        let first = a.shuffled(items)
        XCTAssertEqual(first, b.shuffled(items))
        XCTAssertEqual(first.sorted(), items)
    }
}
