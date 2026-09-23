// CustomFoodSearchTests.swift
//
// The food-catalog spec's "Custom food found by typing while building a
// meal" scenario (fix-testing-feedback-quick-wins task 1.3): typing part of
// a custom food's name -- with or without Czech diacritics, in any case --
// finds it. Pure function, no stores involved.

import XCTest
@testable import FoodLogCore

final class CustomFoodSearchTests: XCTestCase {
    private func draft(_ name: String) -> CustomFoodDraft {
        CustomFoodDraft(
            name: name,
            servingUnit: "g",
            numberOfUnits: 100,
            calories: 100,
            backingFoodId: "backing",
            backingFoodName: "Backing food",
            backingServingId: "serving"
        )
    }

    func testAPartialNameMatches() {
        let drafts = [draft("Babiččin tvarohový koláč"), draft("Ovesná kaše")]

        let matches = CustomFoodSearch.filter(drafts, query: "koláč")

        XCTAssertEqual(matches.map(\.name), ["Babiččin tvarohový koláč"])
    }

    func testMatchingIgnoresDiacriticsAndCaseInBothDirections() {
        let drafts = [draft("Rohlík s máslem"), draft("chléba")]

        XCTAssertEqual(CustomFoodSearch.filter(drafts, query: "rohlik").map(\.name), ["Rohlík s máslem"])
        XCTAssertEqual(CustomFoodSearch.filter(drafts, query: "CHLEBA").map(\.name), ["chléba"])
        XCTAssertEqual(CustomFoodSearch.filter([draft("Rohlik")], query: "rohlík").map(\.name), ["Rohlik"])
    }

    func testSurroundingWhitespaceInTheQueryIsIgnored() {
        XCTAssertEqual(CustomFoodSearch.filter([draft("Ovesná kaše")], query: "  kase ").map(\.name), ["Ovesná kaše"])
    }

    func testABlankQueryMatchesNothing() {
        let drafts = [draft("Ovesná kaše")]

        XCTAssertTrue(CustomFoodSearch.filter(drafts, query: "").isEmpty)
        XCTAssertTrue(CustomFoodSearch.filter(drafts, query: "   ").isEmpty)
    }

    func testANonMatchingQueryMatchesNothingAndOrderIsKept() {
        let drafts = [draft("Kaše B"), draft("Polévka"), draft("Kaše A")]

        XCTAssertTrue(CustomFoodSearch.filter(drafts, query: "pizza").isEmpty)
        XCTAssertEqual(CustomFoodSearch.filter(drafts, query: "kase").map(\.name), ["Kaše B", "Kaše A"])
    }
}
