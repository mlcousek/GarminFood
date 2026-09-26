// BackupVaultTests.swift
//
// add-data-safety tasks 3.4-3.5: `BackupVault` against a real directory
// tree in a unique temp directory per test -- the same generic walk,
// renames and deletions the app does in Application Support. Covers:
// what a snapshot contains (and doesn't), retention, the once-a-day rule,
// no snapshot of an empty data set, export, staging, cancel, the
// next-launch apply (outboxes and diagnostics untouched, files missing from
// the backup removed, a safety snapshot first), version refusal at stage
// AND at apply, and the no-secrets scan over every byte written.

import XCTest
@testable import FoodLogCore

final class BackupVaultTests: XCTestCase {
    private var root: URL!
    private var vault: BackupVault!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }()

    /// 2026-09-20 12:00 Prague.
    private let noon = Date(timeIntervalSince1970: 1_789_898_400)
    private let day: TimeInterval = 24 * 60 * 60

    private static let plantedSecret = "PLANTED-SECRET-7f3a"
    private static let plantedPreferenceSecret = "PLANTED-PREF-SECRET-91c"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        vault = BackupVault(dataDirectory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    private func write(_ text: String, _ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(path)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    /// A realistic data directory: backed-up stores, device-only state, a
    /// store nobody registered, and two planted credentials.
    private func seedDataDirectory() throws {
        try write(#"[{"id":"cf1"},{"id":"cf2"}]"#, "FoodLogCore/custom-foods.json")
        try write(#"[{"id":"e1"},{"id":"e2"},{"id":"e3"}]"#, "FoodLogCore/FoodLog/2026-09.json")
        try write(#"[{"kg":80.1}]"#, "FoodLogCore/weight-entries.json")
        try write(#"{"totalXP":1200}"#, "Gamification/xp-ledger.json")
        try write(#"{"found":["night-owl"]}"#, "Gamification/features/secrets/state.json")
        try write(#"[{"name":"Magnesium"}]"#, "FoodLogCore/Supplements/supplements.json")
        // Device-only state (design D3/D8).
        try write(#"[{"id":"queued"}]"#, "GarminKit/outbox-app.json")
        try write(#"[{"id":"queued-weight"}]"#, "GarminKit/weight-outbox-app.json")
        try write(#"[{"message":"log"}]"#, "GarminKit/diagnostics-log.json")
        try write(#"{"days":{}}"#, "FoodLogCore/garmin-health-cache.json")
        try write(#"{"version":"v1"}"#, "FoodLogCore/OfflineIndex/offline-index-status.json")
        try write(#"[]"#, "GarminFood/donations.json")
        // Credentials that must never travel.
        try write(#"{"token":"\#(Self.plantedSecret)"}"#, "GarminKit/oauth-tokens.json")
        try write(#"{"oauth_token_secret":"\#(Self.plantedSecret)","note":"harmless name"}"#, "FoodLogCore/misc-state.json")
    }

    private var preferences: [String: PreferenceValue] {
        PreferencesBackup.capture(domain: [
            "preferences.haptics": true,
            "goals.water.overrideML": 2500,
            "garmin.oauthToken": Self.plantedPreferenceSecret,
            "dataSafety.lastExportAt": Date(timeIntervalSince1970: 1)
        ])
    }

    private static let backedUp: Set<String> = [
        "FoodLogCore/custom-foods.json",
        "FoodLogCore/FoodLog/2026-09.json",
        "FoodLogCore/weight-entries.json",
        "Gamification/xp-ledger.json",
        "Gamification/features/secrets/state.json",
        "FoodLogCore/Supplements/supplements.json"
    ]

    /// Every byte of every file under `directory`.
    private func allBytes(under directory: URL) throws -> [(String, Data)] {
        var result: [(String, Data)] = []
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                result.append((url.lastPathComponent, try Data(contentsOf: url)))
            }
        }
        return result
    }

    private func assertNoSecrets(in data: Data, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        for needle in [Self.plantedSecret, Self.plantedPreferenceSecret, "oauth_token", "oauthToken"] {
            XCTAssertNil(data.range(of: Data(needle.utf8)), "\(label) contains \(needle)", file: file, line: line)
        }
    }

    // MARK: - Snapshots

    func testSnapshotCopiesIncludedFilesGenericallyAndLeavesTheRestOut() throws {
        try seedDataDirectory()

        let result = try XCTUnwrap(vault.writeSnapshot(kind: .automatic, preferences: preferences, appVersion: "1.0 (1)", now: noon, calendar: calendar))

        XCTAssertEqual(result.snapshot.id, "2026-09-20")
        XCTAssertEqual(Set(result.snapshot.manifest.files.map(\.path)), Self.backedUp)
        XCTAssertEqual(result.skippedPaths, ["FoodLogCore/misc-state.json"])
        let customFoods = try XCTUnwrap(result.snapshot.manifest.files.first { $0.path == "FoodLogCore/custom-foods.json" })
        XCTAssertEqual(customFoods.storeId, "foodlog.custom-foods")
        XCTAssertEqual(customFoods.storeVersion, 1)
        let supplements = try XCTUnwrap(result.snapshot.manifest.files.first { $0.path == "FoodLogCore/Supplements/supplements.json" })
        XCTAssertNil(supplements.storeId, "an unregistered store is included, just without a version")

        let snapshotData = vault.backupsDirectory.appendingPathComponent("2026-09-20/data", isDirectory: true)
        XCTAssertEqual(try BackupVault.includedFiles(under: snapshotData), Self.backedUp.sorted())
        XCTAssertEqual(try String(contentsOf: snapshotData.appendingPathComponent("FoodLogCore/custom-foods.json"), encoding: .utf8), #"[{"id":"cf1"},{"id":"cf2"}]"#)

        XCTAssertEqual(vault.listSnapshots().map(\.id), ["2026-09-20"])
        XCTAssertEqual(vault.status().lastSuccessAt, noon)
        XCTAssertNil(vault.status().lastError)
    }

    func testEmptyDataSetIsNotSnapshotted() throws {
        try write(#"[{"id":"queued"}]"#, "GarminKit/outbox-app.json")
        XCTAssertNil(try vault.writeSnapshot(kind: .automatic, preferences: [:], appVersion: nil, now: noon, calendar: calendar))
        XCTAssertTrue(vault.listSnapshots().isEmpty)
    }

    func testAutomaticSnapshotIsDueOncePerDay() throws {
        try seedDataDirectory()
        XCTAssertTrue(vault.isAutomaticSnapshotDue(now: noon, calendar: calendar))
        try vault.writeSnapshot(kind: .automatic, preferences: [:], appVersion: nil, now: noon, calendar: calendar)
        XCTAssertFalse(vault.isAutomaticSnapshotDue(now: noon.addingTimeInterval(3 * 60 * 60), calendar: calendar))
        XCTAssertTrue(vault.isAutomaticSnapshotDue(now: noon.addingTimeInterval(day), calendar: calendar))
    }

    func testAutomaticSnapshotIfDueWritesOncePerDayAndReadsPreferencesOnlyWhenDue() throws {
        try seedDataDirectory()
        var preferenceReads = 0
        func currentPreferences() -> [String: PreferenceValue] {
            preferenceReads += 1
            return preferences
        }

        let first = try vault.writeAutomaticSnapshotIfDue(preferences: currentPreferences(), appVersion: nil, now: noon, calendar: calendar)
        XCTAssertEqual(first?.snapshot.manifest.kind, .automatic)
        let second = try vault.writeAutomaticSnapshotIfDue(preferences: currentPreferences(), appVersion: nil, now: noon.addingTimeInterval(5 * 60 * 60), calendar: calendar)
        XCTAssertNil(second, "the second foreground on the same day writes nothing")
        XCTAssertEqual(preferenceReads, 1)
        XCTAssertEqual(vault.listSnapshots().map(\.id), ["2026-09-20"])

        XCTAssertNotNil(try vault.writeAutomaticSnapshotIfDue(preferences: currentPreferences(), appVersion: nil, now: noon.addingTimeInterval(day), calendar: calendar))
        XCTAssertEqual(vault.listSnapshots().map(\.id), ["2026-09-21", "2026-09-20"])
    }

    func testEmptyAttemptIsNotRetriedWithinTheRetryInterval() throws {
        XCTAssertNil(try vault.writeSnapshot(kind: .automatic, preferences: [:], appVersion: nil, now: noon, calendar: calendar))
        XCTAssertFalse(vault.isAutomaticSnapshotDue(now: noon.addingTimeInterval(60), calendar: calendar))
        XCTAssertTrue(vault.isAutomaticSnapshotDue(now: noon.addingTimeInterval(BackupVault.retryInterval + 1), calendar: calendar))
    }

    func testManualSnapshotReplacesTheSameDaysSnapshot() throws {
        try seedDataDirectory()
        try vault.writeSnapshot(kind: .automatic, preferences: [:], appVersion: nil, now: noon, calendar: calendar)
        try write(#"[{"id":"cf1"},{"id":"cf2"},{"id":"cf3"}]"#, "FoodLogCore/custom-foods.json")
        try vault.writeSnapshot(kind: .manual, preferences: [:], appVersion: nil, now: noon.addingTimeInterval(60), calendar: calendar)

        let snapshots = vault.listSnapshots()
        XCTAssertEqual(snapshots.map(\.id), ["2026-09-20"])
        XCTAssertEqual(snapshots.first?.manifest.kind, .manual)
        let copy = vault.backupsDirectory.appendingPathComponent("2026-09-20/data/FoodLogCore/custom-foods.json")
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), #"[{"id":"cf1"},{"id":"cf2"},{"id":"cf3"}]"#)
    }

    func testRetentionKeepsFourteenRegularAndFiveSafetySnapshotsAndRemovesTempDirectories() throws {
        try seedDataDirectory()
        for offset in 0..<16 {
            try vault.writeSnapshot(kind: .automatic, preferences: [:], appVersion: nil, now: noon.addingTimeInterval(Double(offset) * day), calendar: calendar)
        }
        for offset in 0..<6 {
            try vault.writeSnapshot(kind: .safety, preferences: [:], appVersion: nil, now: noon.addingTimeInterval(Double(offset) * 60), calendar: calendar)
        }
        try FileManager.default.createDirectory(at: vault.backupsDirectory.appendingPathComponent(".tmp-leftover", isDirectory: true), withIntermediateDirectories: true)
        vault.prune()

        let snapshots = vault.listSnapshots()
        let regular = snapshots.filter { $0.manifest.kind != .safety }
        XCTAssertEqual(regular.count, 14)
        XCTAssertEqual(regular.last?.id, "2026-09-22", "the two oldest days were pruned")
        XCTAssertEqual(snapshots.filter { $0.manifest.kind == .safety }.count, 5)
        let names = try FileManager.default.contentsOfDirectory(atPath: vault.backupsDirectory.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".tmp-") })
    }

    func testIdsToPruneIsPureAndPerKind() {
        func snapshot(_ id: String, _ kind: BackupKind, _ seconds: Double) -> BackupSnapshot {
            BackupSnapshot(id: id, manifest: BackupManifest(kind: kind, createdAt: Date(timeIntervalSince1970: seconds), appVersion: nil, files: []))
        }
        let snapshots = [snapshot("a", .automatic, 1), snapshot("b", .manual, 2), snapshot("c", .automatic, 3), snapshot("s1", .safety, 1), snapshot("s2", .safety, 2)]
        XCTAssertEqual(Set(BackupVault.idsToPrune(snapshots, keepRegular: 2, keepSafety: 1)), ["a", "s1"])
    }

    // MARK: - Export

    func testExportContainerHoldsIncludedFilesAndRoundTrips() throws {
        try seedDataDirectory()
        let (container, skipped) = try vault.makeExportContainer(preferences: preferences, appVersion: "1.0 (1)", now: noon)
        XCTAssertEqual(Set(container.files.map(\.path)), Self.backedUp)
        XCTAssertEqual(skipped, ["FoodLogCore/misc-state.json"])
        XCTAssertEqual(container.manifest.kind, .export)
        XCTAssertEqual(container.preferences["preferences.haptics"], .bool(true))
        XCTAssertNil(container.preferences["garmin.oauthToken"])

        let decoded = try BackupContainer.decode(container.encoded())
        XCTAssertEqual(decoded, container)
        let preview = BackupPreview.make(container: decoded)
        XCTAssertEqual(preview.itemCounts[.foodLog], 3)
        XCTAssertEqual(preview.itemCounts[.customFoods], 2)
        XCTAssertEqual(preview.itemCounts[.weight], 1)
        XCTAssertEqual(BackupVault.exportFileName(now: noon, calendar: calendar), "GarminFood-backup-2026-09-20.json")
    }

    // MARK: - Staged restore

    func testImportedBackupIsStagedThenAppliedAtNextLaunch() throws {
        try seedDataDirectory()
        let (container, _) = try vault.makeExportContainer(preferences: preferences, appVersion: "1.0 (1)", now: noon)

        // Life goes on: data changes, a new file appears, the outbox moves.
        try write(#"[]"#, "FoodLogCore/custom-foods.json")
        try write(#"[{"note":"after"}]"#, "FoodLogCore/day-notes.json")
        try write(#"[{"id":"queued-later"}]"#, "GarminKit/outbox-app.json")
        try write(#"[{"message":"later log"}]"#, "GarminKit/diagnostics-log.json")

        let staged = try vault.stageRestore(container: container)
        XCTAssertEqual(vault.pendingRestore(), staged)
        // Staging touches nothing.
        XCTAssertEqual(read("FoodLogCore/custom-foods.json"), "[]")

        let applied = try XCTUnwrap(vault.applyPendingRestore(currentPreferences: ["preferences.haptics": .bool(false)], appVersion: "1.1 (2)", now: noon.addingTimeInterval(day), calendar: calendar))

        XCTAssertEqual(read("FoodLogCore/custom-foods.json"), #"[{"id":"cf1"},{"id":"cf2"}]"#)
        XCTAssertEqual(read("FoodLogCore/Supplements/supplements.json"), #"[{"name":"Magnesium"}]"#)
        XCTAssertFalse(exists("FoodLogCore/day-notes.json"), "restore replaces: a file the backup lacks is removed")
        // Device-only state is exactly as it was.
        XCTAssertEqual(read("GarminKit/outbox-app.json"), #"[{"id":"queued-later"}]"#)
        XCTAssertEqual(read("GarminKit/weight-outbox-app.json"), #"[{"id":"queued-weight"}]"#)
        XCTAssertEqual(read("GarminKit/diagnostics-log.json"), #"[{"message":"later log"}]"#)
        XCTAssertEqual(read("FoodLogCore/OfflineIndex/offline-index-status.json"), #"{"version":"v1"}"#)
        XCTAssertTrue(exists("GarminKit/oauth-tokens.json"))
        XCTAssertTrue(exists("FoodLogCore/misc-state.json"), "a file backups skip is not deleted by a restore either")

        XCTAssertEqual(applied.preferences?["preferences.haptics"], .bool(true))
        XCTAssertNil(vault.pendingRestore())
        XCTAssertEqual(vault.status().lastRestore?.succeeded, true)
        XCTAssertEqual(vault.status().lastRestore?.backupCreatedAt, container.manifest.createdAt)

        // The safety snapshot holds what was there before the restore.
        let safety = try XCTUnwrap(vault.listSnapshots().first { $0.id == applied.safetySnapshotId })
        XCTAssertEqual(safety.manifest.kind, .safety)
        let safetyNotes = vault.backupsDirectory.appendingPathComponent("\(safety.id)/data/FoodLogCore/day-notes.json")
        XCTAssertEqual(try String(contentsOf: safetyNotes, encoding: .utf8), #"[{"note":"after"}]"#)

        // Nothing staged any more: the next launch does nothing.
        XCTAssertNil(try vault.applyPendingRestore(currentPreferences: [:], appVersion: nil, now: noon, calendar: calendar))
    }

    func testSnapshotCanBeStagedAndRestored() throws {
        try seedDataDirectory()
        try vault.writeSnapshot(kind: .automatic, preferences: preferences, appVersion: nil, now: noon, calendar: calendar)
        try write(#"[]"#, "Gamification/xp-ledger.json")

        try vault.stageRestore(snapshotId: "2026-09-20")
        let applied = try XCTUnwrap(vault.applyPendingRestore(currentPreferences: [:], appVersion: nil, now: noon.addingTimeInterval(day), calendar: calendar))

        XCTAssertEqual(read("Gamification/xp-ledger.json"), #"{"totalXP":1200}"#)
        XCTAssertEqual(applied.preferences?["goals.water.overrideML"], .int(2500))
        XCTAssertTrue(vault.listSnapshots().contains { $0.id == "2026-09-20" }, "the restored snapshot itself is kept")
    }

    func testCancelledRestoreChangesNothing() throws {
        try seedDataDirectory()
        let (container, _) = try vault.makeExportContainer(preferences: [:], appVersion: nil, now: noon)
        try write(#"[]"#, "FoodLogCore/custom-foods.json")
        try vault.stageRestore(container: container)
        try vault.cancelPendingRestore()

        XCTAssertNil(vault.pendingRestore())
        XCTAssertNil(try vault.applyPendingRestore(currentPreferences: [:], appVersion: nil, now: noon, calendar: calendar))
        XCTAssertEqual(read("FoodLogCore/custom-foods.json"), "[]")
    }

    func testUnknownSnapshotAndUnsafeIdsAreRefused() {
        for id in ["2020-01-01", "../x", ".pending-restore", ""] {
            XCTAssertThrowsError(try vault.stageRestore(snapshotId: id), id)
        }
    }

    func testNewerStoreVersionIsRefusedAtStage() throws {
        try seedDataDirectory()
        let bytes = Data("[]".utf8)
        let manifest = BackupManifest(kind: .export, createdAt: noon, appVersion: "9.0", files: [
            BackupFileRecord(path: "FoodLogCore/custom-foods.json", byteCount: bytes.count, storeId: "foodlog.custom-foods", storeVersion: 2)
        ])
        let container = BackupContainer(manifest: manifest, files: [BackupContainer.File(path: "FoodLogCore/custom-foods.json", contents: bytes)], preferences: [:])

        XCTAssertThrowsError(try vault.stageRestore(container: container)) { error in
            XCTAssertEqual(error as? BackupError, .newerStoreVersion(storeId: "foodlog.custom-foods", found: 2, supported: 1))
        }
        XCTAssertNil(vault.pendingRestore())
    }

    func testNewerStoreVersionIsRefusedAtApplyWithNothingChanged() throws {
        try seedDataDirectory()
        let (container, _) = try vault.makeExportContainer(preferences: [:], appVersion: nil, now: noon)
        try vault.stageRestore(container: container)
        try write(#"[{"id":"current"}]"#, "FoodLogCore/custom-foods.json")

        // Simulate staging by a newer build: rewrite the staged manifest.
        let newer = BackupManifest(kind: .export, createdAt: noon, appVersion: "9.0", files: [
            BackupFileRecord(path: "FoodLogCore/custom-foods.json", byteCount: 2, storeId: "foodlog.custom-foods", storeVersion: 5)
        ])
        try BackupCoding.encoder().encode(newer).write(to: vault.pendingRestoreDirectory.appendingPathComponent("manifest.json"))

        XCTAssertThrowsError(try vault.applyPendingRestore(currentPreferences: [:], appVersion: nil, now: noon, calendar: calendar)) { error in
            XCTAssertTrue((error as? BackupError)?.needsNewerApp ?? false)
        }
        XCTAssertEqual(read("FoodLogCore/custom-foods.json"), #"[{"id":"current"}]"#)
        XCTAssertNil(vault.pendingRestore(), "a refused restore doesn't fail again on every launch")
        XCTAssertEqual(vault.status().lastRestore?.succeeded, false)
        XCTAssertFalse(vault.listSnapshots().contains { $0.manifest.kind == .safety }, "refused before the safety snapshot")
    }

    func testFailedApplyRollsBackToTheSafetySnapshot() throws {
        try seedDataDirectory()
        let (exported, _) = try vault.makeExportContainer(preferences: [:], appVersion: nil, now: noon)
        // A file sorted last, so earlier files are already copied in when
        // the copy fails partway.
        let poisonPath = "Gamification/zzz-unreadable.json"
        let container = BackupContainer(
            manifest: exported.manifest,
            files: exported.files.map { file in
                file.path == "FoodLogCore/custom-foods.json"
                    ? BackupContainer.File(path: file.path, contents: Data(#"[{"id":"from-backup"}]"#.utf8))
                    : file
            } + [BackupContainer.File(path: poisonPath, contents: Data("[]".utf8))],
            preferences: [:]
        )
        try vault.stageRestore(container: container)
        try write(#"[{"id":"current"}]"#, "FoodLogCore/custom-foods.json")
        try write(#"[{"note":"current"}]"#, "FoodLogCore/day-notes.json")

        // Make the staged copy of the last file unreadable so copying it fails.
        let staged = vault.pendingRestoreDirectory.appendingPathComponent("data/\(poisonPath)")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: staged.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: staged.path) }
        if FileManager.default.isReadableFile(atPath: staged.path) {
            throw XCTSkip("running with privileges that ignore file permissions")
        }

        XCTAssertThrowsError(try vault.applyPendingRestore(currentPreferences: [:], appVersion: nil, now: noon.addingTimeInterval(day), calendar: calendar))

        XCTAssertEqual(read("FoodLogCore/custom-foods.json"), #"[{"id":"current"}]"#, "the safety snapshot's files are put back")
        XCTAssertEqual(read("FoodLogCore/day-notes.json"), #"[{"note":"current"}]"#)
        XCTAssertEqual(read("Gamification/xp-ledger.json"), #"{"totalXP":1200}"#)
        XCTAssertFalse(exists(poisonPath))
        XCTAssertEqual(read("GarminKit/outbox-app.json"), #"[{"id":"queued"}]"#)
        XCTAssertNil(vault.pendingRestore())
        XCTAssertEqual(vault.status().lastRestore?.succeeded, false)
        XCTAssertTrue(vault.listSnapshots().contains { $0.manifest.kind == .safety })
    }

    func testStagingSkipsExcludedPathsFromACraftedFile() throws {
        try seedDataDirectory()
        let manifest = BackupManifest(kind: .export, createdAt: noon, appVersion: nil, files: [])
        let container = BackupContainer(manifest: manifest, files: [
            BackupContainer.File(path: "GarminKit/outbox-app.json", contents: Data(#"[{"id":"replayed"}]"#.utf8)),
            BackupContainer.File(path: "FoodLogCore/custom-foods.json", contents: Data(#"[{"id":"imported"}]"#.utf8))
        ], preferences: [:])
        try vault.stageRestore(container: container)
        _ = try vault.applyPendingRestore(currentPreferences: [:], appVersion: nil, now: noon, calendar: calendar)

        XCTAssertEqual(read("GarminKit/outbox-app.json"), #"[{"id":"queued"}]"#, "an outbox is never restored (design D8)")
        XCTAssertEqual(read("FoodLogCore/custom-foods.json"), #"[{"id":"imported"}]"#)
    }

    // MARK: - No secrets anywhere

    func testNoSecretsInSnapshotExportOrStagedRestore() throws {
        try seedDataDirectory()

        try vault.writeSnapshot(kind: .automatic, preferences: preferences, appVersion: nil, now: noon, calendar: calendar)
        let (container, _) = try vault.makeExportContainer(preferences: preferences, appVersion: nil, now: noon)
        try vault.stageRestore(container: container)

        for (name, data) in try allBytes(under: vault.backupsDirectory.appendingPathComponent("2026-09-20", isDirectory: true)) {
            assertNoSecrets(in: data, "snapshot \(name)")
        }
        for (name, data) in try allBytes(under: vault.pendingRestoreDirectory) {
            assertNoSecrets(in: data, "staged \(name)")
        }
        let exported = try container.encoded()
        assertNoSecrets(in: exported, "export file")
        for file in container.files {
            assertNoSecrets(in: file.contents, "export \(file.path) (base64-decoded)")
        }
    }
}
