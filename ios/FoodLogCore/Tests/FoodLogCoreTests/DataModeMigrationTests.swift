// DataModeMigrationTests.swift
//
// add-standalone-mode D1/D13: the silent launch classification must put
// every existing install (a Garmin token, or any local history) in Garmin
// mode, never touch a mode already stored, and leave only a truly fresh
// install undecided.

import XCTest
@testable import FoodLogCore

final class DataModeMigrationTests: XCTestCase {
    func testTokenAloneMeansGarminConnected() {
        XCTAssertEqual(
            DataModeMigration.decide(storedMode: nil, hasGarminToken: true, hasLocalHistory: false),
            .garminConnected
        )
    }

    func testHistoryAloneMeansGarminConnected() {
        XCTAssertEqual(
            DataModeMigration.decide(storedMode: nil, hasGarminToken: false, hasLocalHistory: true),
            .garminConnected
        )
    }

    func testTokenAndHistoryMeansGarminConnected() {
        XCTAssertEqual(
            DataModeMigration.decide(storedMode: nil, hasGarminToken: true, hasLocalHistory: true),
            .garminConnected
        )
    }

    func testFreshInstallStaysUndecided() {
        XCTAssertNil(DataModeMigration.decide(storedMode: nil, hasGarminToken: false, hasLocalHistory: false))
    }

    func testStoredModeAlwaysWins() {
        XCTAssertEqual(
            DataModeMigration.decide(storedMode: .standalone, hasGarminToken: true, hasLocalHistory: true),
            .standalone
        )
        XCTAssertEqual(
            DataModeMigration.decide(storedMode: .garminConnected, hasGarminToken: false, hasLocalHistory: false),
            .garminConnected
        )
    }

    func testRawValuesAreStable() {
        // Persisted in UserDefaults (`dataMode.v1`); renaming a case would
        // silently re-run classification on the owner's phone.
        XCTAssertEqual(DataMode.garminConnected.rawValue, "garminConnected")
        XCTAssertEqual(DataMode.standalone.rawValue, "standalone")
    }
}
