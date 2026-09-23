// DecimalInputTests.swift
//
// `DecimalInput.parse` -- the shared typed-number parser. The Czech decimal
// comma is the real-device bug this exists for; the rest pins down what it
// must still refuse.

import XCTest
@testable import FoodLogCore

final class DecimalInputTests: XCTestCase {
    func testAcceptsTheCzechDecimalComma() {
        XCTAssertEqual(DecimalInput.parse("0,5"), 0.5)
        XCTAssertEqual(DecimalInput.parse("72,4"), 72.4)
    }

    func testAcceptsTheDecimalPoint() {
        XCTAssertEqual(DecimalInput.parse("0.5"), 0.5)
        XCTAssertEqual(DecimalInput.parse("250"), 250)
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(DecimalInput.parse("  1,5 "), 1.5)
        XCTAssertEqual(DecimalInput.parse("\t2\n"), 2)
    }

    func testAcceptsALeadingOrTrailingSeparator() {
        XCTAssertEqual(DecimalInput.parse(",5"), 0.5)
        XCTAssertEqual(DecimalInput.parse(".5"), 0.5)
        XCTAssertEqual(DecimalInput.parse("5,"), 5)
        XCTAssertEqual(DecimalInput.parse("-,5"), -0.5)
    }

    func testKeepsTheSignSoCallersCanRejectNegatives() {
        XCTAssertEqual(DecimalInput.parse("-3"), -3)
        XCTAssertEqual(DecimalInput.parse("+3"), 3)
    }

    func testRejectsEmptyAndGarbage() {
        XCTAssertNil(DecimalInput.parse(""))
        XCTAssertNil(DecimalInput.parse("   "))
        XCTAssertNil(DecimalInput.parse(","))
        XCTAssertNil(DecimalInput.parse("-"))
        XCTAssertNil(DecimalInput.parse("abc"))
        XCTAssertNil(DecimalInput.parse("1,2,3"))
        XCTAssertNil(DecimalInput.parse("1.000,5"), "two separators is ambiguous, not a guess")
        XCTAssertNil(DecimalInput.parse("1 5"))
        XCTAssertNil(DecimalInput.parse("12g"))
        XCTAssertNil(DecimalInput.parse("--3"))
    }

    func testRejectsWhatDoubleWouldOtherwiseAccept() {
        XCTAssertNil(DecimalInput.parse("1e5"))
        XCTAssertNil(DecimalInput.parse("inf"))
        XCTAssertNil(DecimalInput.parse("nan"))
        XCTAssertNil(DecimalInput.parse("0x10"))
    }

    func testRejectsANonFiniteResult() {
        XCTAssertNil(DecimalInput.parse(String(repeating: "9", count: 400)), "overflows Double")
    }
}
