// StoreCatalogTests.swift
//
// add-data-safety task 3.1 (design D1): `StoreCatalog` is the one place a
// store's schema version lives, so a store missing from it would be backed
// up without a version and never refused by an older build. These tests
// keep it honest from the sources themselves: every literal `"<name>.json"`
// in GarminKit, FoodLogCore, Gamification and the app target must be
// covered by a catalog entry (or exempted here with a reason), and each
// entry's `inBackup` must agree with what `BackupExclusions` actually does.
//
// The sources are found via `#filePath` (ios/FoodLogCore/Tests/
// FoodLogCoreTests/ -> ios/), the same way the fixture tests find theirs.
// FoodLogCore/Backup is skipped: it names other stores' files, it doesn't
// persist them.

import XCTest
@testable import FoodLogCore

final class StoreCatalogTests: XCTestCase {
    private static let iosDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // FoodLogCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // FoodLogCore
        .deletingLastPathComponent() // ios

    private static let scannedDirectories = [
        "GarminKit/Sources",
        "FoodLogCore/Sources",
        "Gamification/Sources",
        "GarminFood",
        "Shared",
        "GarminFoodWidget"
    ]

    /// Literal `.json` names in the sources that are not a persisted store.
    private static let exempt: [String: String] = [
        "preview-day-notes.json": "a SwiftUI preview's throwaway store in the temp directory"
    ]

    /// Every file name a catalog entry covers.
    private static var catalogFileNames: Set<String> {
        var names = Set<String>()
        for entry in StoreCatalog.entries {
            switch entry.location {
            case .file(let path):
                names.insert(URL(fileURLWithPath: path).lastPathComponent)
            case .directory(_, let fileNames):
                names.formUnion(fileNames)
            case .prefixed:
                break
            }
        }
        return names
    }

    func testEveryStoreFileNameInTheSourcesIsInTheCatalog() throws {
        let fileManager = FileManager.default
        let literal = try NSRegularExpression(pattern: "\"([A-Za-z0-9_-]+\\.json)\"")
        var found = Set<String>()
        for relative in Self.scannedDirectories {
            let directory = Self.iosDirectory.appendingPathComponent(relative, isDirectory: true)
            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                if url.path.contains("/FoodLogCore/Sources/FoodLogCore/Backup/") { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                for match in literal.matches(in: text, range: range) {
                    if let captured = Range(match.range(at: 1), in: text) {
                        found.insert(String(text[captured]))
                    }
                }
            }
        }

        // The scan must see stores from every package, or it proves nothing.
        for known in ["diagnostics-log.json", "custom-foods.json", "xp-ledger.json", "donations.json"] {
            XCTAssertTrue(found.contains(known), "scan didn't find \(known); found \(found.sorted())")
        }

        let covered = Self.catalogFileNames
        for name in found.sorted() where Self.exempt[name] == nil {
            XCTAssertTrue(
                covered.contains(name),
                "\(name) is persisted but not in StoreCatalog -- add an entry with schemaVersion 1 (docs/data-compatibility.md)"
            )
        }
        for name in Self.exempt.keys {
            XCTAssertTrue(found.contains(name), "exempt lists \(name), which the sources no longer mention")
        }
    }

    func testCatalogAgreesWithTheExclusions() {
        for entry in StoreCatalog.entries {
            let samplePath: String
            switch entry.location {
            case .file(let path):
                samplePath = path
            case .directory(let directory, let fileNames):
                samplePath = directory + "/" + (fileNames.first ?? "sample.json")
            case .prefixed(let directory, let prefix):
                samplePath = directory + "/" + prefix + "app.json"
            }
            XCTAssertTrue(entry.location.matches(relativePath: samplePath), entry.id)
            XCTAssertEqual(
                BackupExclusions.includesFile(relativePath: samplePath), entry.inBackup,
                "\(entry.id): inBackup says \(entry.inBackup) but BackupExclusions disagrees for \(samplePath)"
            )
            XCTAssertEqual(entry.inBackup, entry.area != .deviceOnly, "\(entry.id): device-only stores are exactly the ones not backed up")
            XCTAssertGreaterThanOrEqual(entry.schemaVersion, 1, entry.id)
        }
    }

    func testCatalogIdsAreUniqueAndLookupsWork() {
        let ids = StoreCatalog.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(StoreCatalog.entry(forRelativePath: "FoodLogCore/FoodLog/2026-09.json")?.id, "foodlog.local-food-log")
        XCTAssertEqual(StoreCatalog.entry(forRelativePath: "Gamification/features/boss/streak-freezes.json")?.id, "gamification.features")
        XCTAssertEqual(StoreCatalog.entry(forRelativePath: "GarminKit/weight-outbox-widget.json")?.id, "garminkit.weight-outbox")
        XCTAssertEqual(StoreCatalog.entry(forRelativePath: "GarminKit/outbox-app.json")?.id, "garminkit.outbox")
        XCTAssertNil(StoreCatalog.entry(forRelativePath: "FoodLogCore/Supplements/x.json"))
        XCTAssertEqual(StoreCatalog.entry(id: "foodlog.custom-foods")?.area, .customFoods)
    }
}
