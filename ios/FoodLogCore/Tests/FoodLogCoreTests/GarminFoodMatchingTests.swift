// GarminFoodMatchingTests.swift
//
// Task 29.2: exact/near-exact name matches, diacritic-only differences,
// a name match with wildly different calories (should NOT match), and
// no-candidates-at-all. Also covers case-insensitivity and packaging-word
// stripping explicitly, since design.md D3 calls both out by name.

import XCTest
@testable import FoodLogCore

final class GarminFoodMatchingTests: XCTestCase {
    private func offFood(_ name: String, calories: Double? = 350) -> Food {
        Food(
            id: "off-1",
            name: name,
            source: .openFoodFacts,
            servings: [Serving(id: "100g", unit: "g", numberOfUnits: 100, calories: calories)]
        )
    }

    private func garminFood(_ id: String, _ name: String, calories: Double? = 350) -> Food {
        Food(
            id: id,
            name: name,
            source: .fatSecret,
            servings: [Serving(id: "s1", unit: "g", numberOfUnits: 100, calories: calories)]
        )
    }

    func testExactNormalizedNameMatch() {
        let result = GarminFoodMatching.match(offFood: offFood("Tvaroh"), garminCandidates: [garminFood("g1", "Tvaroh")])

        guard case .matched(let matched) = result else {
            return XCTFail("expected a match, got \(result)")
        }
        XCTAssertEqual(matched.id, "g1")
    }

    func testCaseInsensitiveMatch() {
        let result = GarminFoodMatching.match(offFood: offFood("tvaroh"), garminCandidates: [garminFood("g1", "TVAROH")])

        guard case .matched = result else {
            return XCTFail("expected a case-insensitive match, got \(result)")
        }
    }

    func testDiacriticOnlyDifferenceStillMatches() {
        // design.md D3's own example: "tvaroh" vs "Tvaroh" -- also covered
        // more strongly here with a real diacritic ("Šunka" vs "Sunka").
        let result = GarminFoodMatching.match(offFood: offFood("Šunka"), garminCandidates: [garminFood("g1", "Sunka")])

        guard case .matched(let matched) = result else {
            return XCTFail("expected a diacritic-insensitive match, got \(result)")
        }
        XCTAssertEqual(matched.id, "g1")
    }

    func testPackagingAndQuantityWordsAreIgnoredWhenComparing() {
        let result = GarminFoodMatching.match(
            offFood: offFood("Rohlíky Krehké Celozrné 250G"),
            garminCandidates: [garminFood("g1", "Rohlíky Krehké Celozrné")]
        )

        guard case .matched = result else {
            return XCTFail("expected packaging/quantity tokens to be stripped before comparing, got \(result)")
        }
    }

    func testNameMatchWithWildlyDifferentCaloriesDoesNotMatch() {
        let result = GarminFoodMatching.match(
            offFood: offFood("Tvaroh", calories: 100),
            garminCandidates: [garminFood("g1", "Tvaroh", calories: 350)]
        )

        XCTAssertEqual(result, .noMatch)
    }

    func testNameMatchWithCaloriesJustInsideToleranceStillMatches() {
        // 350 * 1.2 = 420 -- right at the boundary, should still match.
        let result = GarminFoodMatching.match(
            offFood: offFood("Tvaroh", calories: 420),
            garminCandidates: [garminFood("g1", "Tvaroh", calories: 350)]
        )

        guard case .matched = result else {
            return XCTFail("expected calories within the 20% tolerance to still match, got \(result)")
        }
    }

    func testMissingCaloriesOnEitherSideSkipsTheSanityCheck() {
        let result = GarminFoodMatching.match(
            offFood: offFood("Tvaroh", calories: nil),
            garminCandidates: [garminFood("g1", "Tvaroh", calories: 350)]
        )

        guard case .matched = result else {
            return XCTFail("expected a name-only match when calories aren't available on one side, got \(result)")
        }
    }

    func testNoCandidatesAtAllReturnsNoMatch() {
        let result = GarminFoodMatching.match(offFood: offFood("Tvaroh"), garminCandidates: [])

        XCTAssertEqual(result, .noMatch)
    }

    func testNoNameSimilarCandidateReturnsNoMatch() {
        let result = GarminFoodMatching.match(
            offFood: offFood("Tvaroh"),
            garminCandidates: [garminFood("g1", "Banán"), garminFood("g2", "Rohlík")]
        )

        XCTAssertEqual(result, .noMatch)
    }

    // 2026-09-21 bug fix: a genuinely zero-calorie Garmin candidate used to
    // skip the sanity check entirely (treated the same as "calories
    // missing"), so a name-similar but calorically very different OFF
    // product could match it with no check at all.
    func testZeroCalorieCandidateDoesNotMatchAWildlyDifferentOffCalorieCount() {
        let result = GarminFoodMatching.match(
            offFood: offFood("Cola", calories: 42),
            garminCandidates: [garminFood("g1", "Cola", calories: 0)]
        )

        XCTAssertEqual(result, .noMatch)
    }

    func testZeroCalorieCandidateStillMatchesAnAlsoNearZeroOffProduct() {
        let result = GarminFoodMatching.match(
            offFood: offFood("Cola Zero", calories: 1),
            garminCandidates: [garminFood("g1", "Cola Zero", calories: 0)]
        )

        guard case .matched = result else {
            return XCTFail("expected two near-zero-calorie products to still match, got \(result)")
        }
    }
}
