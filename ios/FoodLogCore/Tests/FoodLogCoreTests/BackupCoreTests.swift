// BackupCoreTests.swift
//
// add-data-safety tasks 3.1-3.3: the pure pieces under FoodLogCore/Backup --
// the exclusion and path-safety rules, typed preferences (including a real
// UserDefaults round trip, since the whole point of `PreferenceValue` is that
// Bool/Int/Double/Date/Data survive the property-list bridge), the manifest
// and container coding, the version check, the import preview counts and the
// export reminder's 14-day edges. The file-system side (snapshots, staging,
// restore) is in BackupVaultTests; the catalog's coverage of every store in
// the sources is in StoreCatalogTests.

import XCTest
@testable import FoodLogCore

final class BackupCoreTests: XCTestCase {
    // MARK: - Path safety and exclusions

    func testPathSafetyRejectsEscapesAndOddComponents() {
        XCTAssertTrue(BackupPath.isSafe("FoodLogCore/custom-foods.json"))
        XCTAssertTrue(BackupPath.isSafe("Gamification/features/boss/boss.json"))
        for unsafe in ["", "/etc/passwd", "../x.json", "FoodLogCore/../../x.json", "a//b.json", "./a.json", "a\\b.json", "a/b/"] {
            XCTAssertFalse(BackupPath.isSafe(unsafe), unsafe)
        }
    }

    func testIncludesOrdinaryStoresAndNewUnregisteredOnes() {
        XCTAssertTrue(BackupExclusions.includesFile(relativePath: "FoodLogCore/custom-foods.json"))
        XCTAssertTrue(BackupExclusions.includesFile(relativePath: "FoodLogCore/FoodLog/2026-09.json"))
        XCTAssertTrue(BackupExclusions.includesFile(relativePath: "Gamification/features/boss/streak-freezes.json"))
        // The secret-achievements feature directory is legitimate data.
        XCTAssertTrue(BackupExclusions.includesFile(relativePath: "Gamification/features/secrets/state.json"))
        // A store nobody registered (e.g. supplements) is backed up anyway.
        XCTAssertTrue(BackupExclusions.includesFile(relativePath: "FoodLogCore/Supplements/supplement-log.json"))
    }

    func testExcludesDeviceStateCredentialsAndBackups() {
        let excluded = [
            "Backups/2026-09-20/data/FoodLogCore/custom-foods.json",
            "GarminKit/outbox-app.json",
            "GarminKit/weight-outbox-app.json",
            "GarminKit/hydration-outbox-widget.json",
            "GarminKit/diagnostics-log.json",
            "FoodLogCore/garmin-health-cache.json",
            "FoodLogCore/OfflineIndex/offline-index-status.json",
            "FoodLogCore/OfflineIndex/shards/0001.json",
            "GarminFood/donations.json",
            "GarminKit/oauth-tokens.json",
            "Something/Token/x.json",
            "Web/cookies.json",
            "Auth/credentials.json",
            "Auth/password.json",
            "FoodLogCore/custom-foods.txt",
            "../FoodLogCore/custom-foods.json"
        ]
        for path in excluded {
            XCTAssertFalse(BackupExclusions.includesFile(relativePath: path), path)
        }
    }

    func testPreferenceKeyRules() {
        XCTAssertTrue(BackupExclusions.includesPreference(key: "preferences.haptics"))
        XCTAssertTrue(BackupExclusions.includesPreference(key: "goals.water.overrideML"))
        for key in ["", "dataSafety.lastExportAt", "developer.fakeGarmin", "AppleLanguages", "NSInterfaceStyle", "com.apple.foo", "WebKitCache", "garmin.oauthToken", "session.cookie", "accessToken"] {
            XCTAssertFalse(BackupExclusions.includesPreference(key: key), key)
        }
    }

    func testSecretPolicyScansContent() {
        XCTAssertTrue(BackupSecretPolicy.containsSecret(Data(#"{"oauth_token_secret":"x"}"#.utf8)))
        XCTAssertTrue(BackupSecretPolicy.containsSecret(Data(#"[{"accessToken":"x"}]"#.utf8)))
        XCTAssertFalse(BackupSecretPolicy.containsSecret(Data(#"[{"name":"token bar","kcal":120}]"#.utf8)))
    }

    // MARK: - Preferences

    func testPreferenceValueFromPropertyListKeepsTypes() {
        XCTAssertEqual(PreferenceValue(propertyListValue: true), .bool(true))
        XCTAssertEqual(PreferenceValue(propertyListValue: 3), .int(3))
        XCTAssertEqual(PreferenceValue(propertyListValue: 2.5), .double(2.5))
        XCTAssertEqual(PreferenceValue(propertyListValue: "cs"), .string("cs"))
        let date = Date(timeIntervalSince1970: 1_758_000_000)
        XCTAssertEqual(PreferenceValue(propertyListValue: date), .date(date))
        XCTAssertEqual(PreferenceValue(propertyListValue: Data([1, 2, 3])), .data(Data([1, 2, 3])))
        XCTAssertEqual(PreferenceValue(propertyListValue: ["a", "b"]), .array([.string("a"), .string("b")]))
        XCTAssertEqual(PreferenceValue(propertyListValue: ["k": 1] as [String: Any]), .dictionary(["k": .int(1)]))
    }

    func testPreferenceValueCodableRoundTrip() throws {
        let values: [String: PreferenceValue] = [
            "b": .bool(false),
            "i": .int(-7),
            "d": .double(0.1),
            "s": .string("ahoj"),
            "t": .date(Date(timeIntervalSince1970: 1_758_000_000.5)),
            "x": .data(Data([0, 255])),
            "a": .array([.int(1), .bool(true)]),
            "m": .dictionary(["nested": .string("v")])
        ]
        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([String: PreferenceValue].self, from: data)
        XCTAssertEqual(decoded, values)
    }

    func testPreferencesCaptureAndRestoreThroughRealUserDefaults() throws {
        let suite = "garminfood.backup-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "preferences.haptics")
        defaults.set(2500, forKey: "goals.water.overrideML")
        defaults.set(72.5, forKey: "goals.weight.overrideKg")
        defaults.set(Date(timeIntervalSince1970: 1_758_000_000), forKey: "preferences.fasting.trackedSince")
        defaults.set(Date(timeIntervalSince1970: 1), forKey: "dataSafety.lastExportAt")
        defaults.set("secret", forKey: "garmin.oauthToken")

        let domain = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        let captured = PreferencesBackup.capture(domain: domain)
        XCTAssertEqual(captured["preferences.haptics"], .bool(true))
        XCTAssertEqual(captured["goals.water.overrideML"], .int(2500))
        XCTAssertEqual(captured["goals.weight.overrideKg"], .double(72.5))
        XCTAssertNil(captured["dataSafety.lastExportAt"])
        XCTAssertNil(captured["garmin.oauthToken"])

        // Through JSON, as a snapshot stores it.
        let stored = try JSONDecoder().decode([String: PreferenceValue].self, from: JSONEncoder().encode(captured))

        // The device now has different values.
        defaults.set(false, forKey: "preferences.haptics")
        defaults.set(1, forKey: "preferences.addedLater")
        defaults.set(Date(timeIntervalSince1970: 99), forKey: "dataSafety.lastExportAt")
        let current = try XCTUnwrap(defaults.persistentDomain(forName: suite))

        defaults.setPersistentDomain(PreferencesBackup.restoredDomain(current: current, backup: stored), forName: suite)

        XCTAssertEqual(defaults.object(forKey: "preferences.haptics") as? Bool, true)
        XCTAssertEqual(defaults.integer(forKey: "goals.water.overrideML"), 2500)
        XCTAssertEqual(defaults.double(forKey: "goals.weight.overrideKg"), 72.5)
        XCTAssertEqual(defaults.object(forKey: "preferences.fasting.trackedSince") as? Date, Date(timeIntervalSince1970: 1_758_000_000))
        // Replace, not merge: a backupable key the backup lacks is removed.
        XCTAssertNil(defaults.object(forKey: "preferences.addedLater"))
        // Excluded keys keep the device's values.
        XCTAssertEqual(defaults.object(forKey: "dataSafety.lastExportAt") as? Date, Date(timeIntervalSince1970: 99))
        XCTAssertEqual(defaults.string(forKey: "garmin.oauthToken"), "secret")
    }

    func testRestoredDomainIgnoresExcludedKeysInACraftedBackup() {
        let restored = PreferencesBackup.restoredDomain(
            current: ["dataSafety.lastExportAt": 5],
            backup: ["dataSafety.lastExportAt": .int(1), "developer.x": .bool(true), "preferences.haptics": .bool(true)]
        )
        XCTAssertEqual(restored["dataSafety.lastExportAt"] as? Int, 5)
        XCTAssertNil(restored["developer.x"])
        XCTAssertEqual(restored["preferences.haptics"] as? Bool, true)
    }

    // MARK: - Manifest, container, compatibility

    private func manifest(kind: BackupKind = .export, formatVersion: Int = BackupManifest.currentFormatVersion, files: [BackupFileRecord] = []) -> BackupManifest {
        BackupManifest(formatVersion: formatVersion, kind: kind, createdAt: Date(timeIntervalSince1970: 1_758_000_000), appVersion: "1.4 (42)", files: files)
    }

    func testContainerRoundTripKeepsExactBytes() throws {
        let bytes = Data(#"[{"name":"Rohlík","kcal":130.5}]"#.utf8)
        let container = BackupContainer(
            manifest: manifest(files: [.make(path: "FoodLogCore/custom-foods.json", byteCount: bytes.count)]),
            files: [BackupContainer.File(path: "FoodLogCore/custom-foods.json", contents: bytes)],
            preferences: ["preferences.haptics": .bool(true)]
        )
        let decoded = try BackupContainer.decode(container.encoded())
        XCTAssertEqual(decoded, container)
        XCTAssertEqual(decoded.files.first?.contents, bytes)
        XCTAssertEqual(decoded.manifest.files.first?.storeId, "foodlog.custom-foods")
        XCTAssertEqual(decoded.manifest.files.first?.storeVersion, 1)
    }

    func testNotABackupIsRefused() {
        for text in [#"{"hello":1}"#, "[1,2]", "not json", #"{"manifest":{"schema":"other.app","formatVersion":1,"kind":"export","createdAt":"2026-09-20T10:00:00Z","files":[]},"files":[],"preferences":{}}"#] {
            XCTAssertThrowsError(try BackupContainer.decode(Data(text.utf8)), text) { error in
                XCTAssertEqual(error as? BackupError, .notABackup)
            }
        }
    }

    func testNewerFormatIsRefusedBeforeTheBodyIsDecoded() {
        // Format 2 with a body this build couldn't decode at all.
        let text = #"{"manifest":{"schema":"garminfood.backup","formatVersion":2},"somethingNew":true}"#
        XCTAssertThrowsError(try BackupContainer.decode(Data(text.utf8))) { error in
            XCTAssertEqual(error as? BackupError, .newerFormat(found: 2, supported: BackupManifest.currentFormatVersion))
            XCTAssertTrue((error as? BackupError)?.needsNewerApp ?? false)
        }
    }

    func testNewerStoreVersionIsRefusedAndUnknownStoreIsAllowed() throws {
        let newer = manifest(files: [BackupFileRecord(path: "FoodLogCore/custom-foods.json", byteCount: 2, storeId: "foodlog.custom-foods", storeVersion: 99)])
        XCTAssertThrowsError(try BackupCompatibility.check(newer)) { error in
            XCTAssertEqual(error as? BackupError, .newerStoreVersion(storeId: "foodlog.custom-foods", found: 99, supported: 1))
        }
        let unknown = manifest(files: [BackupFileRecord(path: "FoodLogCore/Supplements/x.json", byteCount: 2, storeId: "supplements.log", storeVersion: 7)])
        XCTAssertNoThrow(try BackupCompatibility.check(unknown))
        XCTAssertNoThrow(try BackupCompatibility.check(manifest()))
    }

    func testUnsafePathInContainerIsRefused() throws {
        let container = BackupContainer(manifest: manifest(), files: [BackupContainer.File(path: "../escape.json", contents: Data("[]".utf8))], preferences: [:])
        XCTAssertThrowsError(try BackupContainer.decode(container.encoded())) { error in
            XCTAssertEqual(error as? BackupError, .unsafePath("../escape.json"))
        }
    }

    func testUnknownKindDecodesLeniently() throws {
        let text = #"{"schema":"garminfood.backup","formatVersion":1,"kind":"cloud","createdAt":"2026-09-20T10:00:00Z","files":[]}"#
        let decoded = try BackupCoding.decoder().decode(BackupManifest.self, from: Data(text.utf8))
        XCTAssertEqual(decoded.kind, .export)
    }

    // MARK: - Preview

    func testPreviewCountsTopLevelArraysPerArea() {
        let files: [(path: String, contents: Data)] = [
            ("FoodLogCore/FoodLog/2026-08.json", Data("[1,2,3]".utf8)),
            ("FoodLogCore/FoodLog/2026-09.json", Data("[1,2]".utf8)),
            ("FoodLogCore/custom-foods.json", Data(#"[{"a":1},{"b":2}]"#.utf8)),
            ("FoodLogCore/weight-entries.json", Data("[{}]".utf8)),
            ("FoodLogCore/day-notes.json", Data("{}".utf8)),
            ("Gamification/xp-ledger.json", Data(#"{"total":10}"#.utf8)),
            ("FoodLogCore/usage-history.json", Data("[]".utf8)),
            ("FoodLogCore/Supplements/x.json", Data("[]".utf8))
        ]
        let preview = BackupPreview.make(files: files, preferenceCount: 4)
        XCTAssertEqual(preview.itemCounts[.foodLog], 5)
        XCTAssertEqual(preview.itemCounts[.customFoods], 2)
        XCTAssertEqual(preview.itemCounts[.weight], 1)
        XCTAssertEqual(preview.itemCounts[.dayNotes], 0, "not an array: counted as zero items, not an error")
        XCTAssertNil(preview.itemCounts[.hydration])
        XCTAssertEqual(preview.otherFileCount, 3)
        XCTAssertEqual(preview.totalFileCount, 8)
        XCTAssertEqual(preview.preferenceCount, 4)
    }

    // MARK: - Reminder

    func testReminderShowsWhenNeverExportedOrOlderThanFourteenDays() {
        let now = Date(timeIntervalSince1970: 1_758_000_000)
        let day: TimeInterval = 24 * 60 * 60
        XCTAssertTrue(BackupReminderPolicy.shouldShow(lastExportAt: nil, dismissedAt: nil, now: now))
        XCTAssertFalse(BackupReminderPolicy.shouldShow(lastExportAt: now.addingTimeInterval(-13 * day), dismissedAt: nil, now: now))
        XCTAssertTrue(BackupReminderPolicy.shouldShow(lastExportAt: now.addingTimeInterval(-14 * day), dismissedAt: nil, now: now))
        XCTAssertFalse(BackupReminderPolicy.shouldShow(lastExportAt: nil, dismissedAt: now.addingTimeInterval(-2 * day), now: now))
        XCTAssertTrue(BackupReminderPolicy.shouldShow(lastExportAt: nil, dismissedAt: now.addingTimeInterval(-15 * day), now: now))
    }

    func testDaysSinceCountsCalendarDaysAndNeverGoesNegative() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        // 2026-09-20 23:30 and 2026-09-21 00:30 Prague: one calendar day apart.
        let lateEvening = Date(timeIntervalSince1970: 1_789_939_800)
        let justAfterMidnight = lateEvening.addingTimeInterval(60 * 60)
        XCTAssertEqual(BackupReminderPolicy.daysSince(lateEvening, now: lateEvening, calendar: calendar), 0)
        XCTAssertEqual(BackupReminderPolicy.daysSince(lateEvening, now: justAfterMidnight, calendar: calendar), 1)
        XCTAssertEqual(BackupReminderPolicy.daysSince(lateEvening, now: lateEvening.addingTimeInterval(10 * 24 * 60 * 60), calendar: calendar), 10)
        XCTAssertEqual(BackupReminderPolicy.daysSince(justAfterMidnight, now: lateEvening, calendar: calendar), 0)
    }

    func testReminderBookkeepingKeysNeverTravelWithABackup() {
        XCTAssertFalse(BackupExclusions.includesPreference(key: BackupReminderPolicy.lastExportAtKey))
        XCTAssertFalse(BackupExclusions.includesPreference(key: BackupReminderPolicy.dismissedAtKey))
    }
}
