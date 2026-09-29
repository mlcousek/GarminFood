// VaultPathPolicyTests.swift
//
// add-vault-connection tasks 2.3 (design D4, D10): repository validation,
// `HubPath` normalisation (refuse, never fix) and the read/write
// allow-lists -- every allowed shape and every refused one the design
// lists: another device, prefix tricks, `..`, encoded dots, backslash,
// uppercase id, empty, absolute, wrong extension, reads outside
// `projection/`.

import XCTest
@testable import VaultKit

final class VaultPathPolicyTests: XCTestCase {
    private let own = VaultDeviceID("ios-7f3a91c2")!
    private var policy: VaultPathPolicy { VaultPathPolicy(ownDeviceID: own) }

    private func path(_ raw: String, file: StaticString = #filePath, line: UInt = #line) -> HubPath {
        guard let path = HubPath(raw) else {
            XCTFail("\(raw) should be a normal hub path", file: file, line: line)
            return VaultHub.projectionPath
        }
        return path
    }

    // MARK: - VaultRepository

    func testRepositoryAcceptsGitHubNamesAndTrimsWhitespace() throws {
        let repository = try VaultRepository(owner: "  example-owner\n", name: "example.vault_2-x ", branch: "")
        XCTAssertEqual(repository.owner, "example-owner")
        XCTAssertEqual(repository.name, "example.vault_2-x")
        XCTAssertEqual(repository.branch, "main")
        XCTAssertEqual(try VaultRepository(owner: "a", name: "b", branch: "test/synthetic-plan").branch, "test/synthetic-plan")
    }

    func testRepositoryRefusesInvalidParts() {
        for owner in ["", "-lead", "trail-", "has space", "has/slash", "dot.ted", String(repeating: "a", count: 40), "ümlaut"] {
            XCTAssertThrowsError(try VaultRepository(owner: owner, name: "vault"), owner) { error in
                XCTAssertEqual(error as? VaultRepositoryProblem, .invalidOwner)
            }
        }
        for name in ["", ".", "..", "a/b", "a b", "a?b", "a%2e", String(repeating: "n", count: 101)] {
            XCTAssertThrowsError(try VaultRepository(owner: "owner", name: name), name) { error in
                XCTAssertEqual(error as? VaultRepositoryProblem, .invalidName)
            }
        }
        for branch in ["-x", "a..b", "a//b", "/a", "a/", "a.lock", ".hidden", "a b", "a?b", "a~b"] {
            XCTAssertThrowsError(try VaultRepository(owner: "owner", name: "vault", branch: branch), branch) { error in
                XCTAssertEqual(error as? VaultRepositoryProblem, .invalidBranch)
            }
        }
    }

    func testConnectionSettingsRoundTripThroughUserDefaultsWithoutAToken() throws {
        let suite = "vaultkit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }

        XCTAssertEqual(VaultConnectionSettings.load(from: defaults), VaultConnectionSettings())
        let settings = VaultConnectionSettings(enabled: true, owner: "example-owner", name: "example-vault", branch: "main")
        settings.save(to: defaults)
        XCTAssertEqual(VaultConnectionSettings.load(from: defaults), settings)
        XCTAssertTrue(settings.isConfigured)

        let stored = try XCTUnwrap(defaults.dictionary(forKey: VaultConnectionSettings.storageKey))
        XCTAssertEqual(Set(stored.keys), ["enabled", "owner", "name", "branch"], "the token is never part of the settings")

        XCTAssertFalse(VaultConnectionSettings(enabled: true, owner: "", name: "x").isConfigured)
        // Unknown keys from a newer build are ignored.
        XCTAssertEqual(VaultConnectionSettings(propertyList: ["enabled": true, "future": 1]).enabled, true)
    }

    // MARK: - HubPath

    func testHubPathAcceptsNormalPaths() {
        for raw in ["projection/projection.v1.json", "events/ios-7f3a91c2/2026/10/20261001T101500Z-1.jsonl", "a", "a-b_c.d/e"] {
            XCTAssertNotNil(HubPath(raw), raw)
        }
    }

    func testHubPathRefusesAnythingNotNormal() {
        let refused = [
            "", "/", "/projection/projection.v1.json", "projection/", "projection//x.json",
            "./projection/x.json", "projection/./x.json", "events/../projection/x.json", "..",
            "projection\\x.json", "projection/%2e%2e/x.json", "projection/x%20y.json",
            "projection/x y.json", "projection/x\u{0}.json", "projection/x\n.json", "projection/ž.json",
            "projection/x?.json", "projection/x#.json", "projection/x:y.json",
            String(repeating: "a/", count: 250) + "x"
        ]
        for raw in refused {
            XCTAssertNil(HubPath(raw), raw.debugDescription)
        }
    }

    func testHubPathCodableRefusesAbnormalPaths() throws {
        let decoded = try JSONDecoder().decode(HubPath.self, from: Data(#""projection/projection.v1.json""#.utf8))
        XCTAssertEqual(decoded, VaultHub.projectionPath)
        XCTAssertThrowsError(try JSONDecoder().decode(HubPath.self, from: Data(#""../x.json""#.utf8)))
    }

    // MARK: - Reads

    func testReadAllowsProjectionFilesAndOwnFolderOnly() {
        XCTAssertTrue(policy.allowsRead(path("projection/projection.v1.json")))
        XCTAssertTrue(policy.allowsRead(path("projection/habits.json")))
        XCTAssertTrue(policy.allowsRead(path("events/ios-7f3a91c2/2026/10/x.jsonl")))

        let refused = [
            "projection/nested/projection.v1.json", // one level only
            "projection/.json",                      // no name
            "projection/projection.v1.jsonl",
            "projection/notes.md",
            "projection",
            "Daily/2026-10-01.md",                   // a daily note
            "events/ios-00000000/2026/10/x.jsonl",   // another device
            "events/ios-7f3a91c2",                   // the folder itself
            "events/ios-7F3A91C2/2026/x.jsonl",      // uppercase id
            "events/ios-7f3a91c2x/2026/x.jsonl",     // prefix trick
            "events/ios-7f3a91c/2026/x.jsonl",
            "scripts/sync.mjs",
            "x.json"
        ]
        for raw in refused {
            XCTAssertFalse(policy.allowsRead(path(raw)), raw)
        }
    }

    // MARK: - Writes

    func testWriteAllowsOnlyJsonlUnderOwnFolder() {
        XCTAssertTrue(policy.allowsWrite(path("events/ios-7f3a91c2/2026/10/20261001T101500Z-1.jsonl")))
        XCTAssertTrue(policy.allowsWrite(path("events/ios-7f3a91c2/x.jsonl")))

        let refused = [
            "events/ios-00000000/2026/10/x.jsonl",          // spec: another device's folder
            "events/ios-7f3a91c2/2026/10/x.json",           // wrong extension
            "events/ios-7f3a91c2/2026/10/x.jsonl.md",
            "events/ios-7f3a91c2/.jsonl",
            "events/ios-7f3a91c2x/2026/x.jsonl",
            "events/ios-7F3A91C2/2026/x.jsonl",
            "events/x.jsonl",
            "events/ios-7f3a91c2",
            "projection/projection.v1.json",                // reads only
            "projection/x.jsonl",
            "Sport/Training/_hub/events/ios-7f3a91c2/x.jsonl", // no full repository paths
            "scripts/x.jsonl"
        ]
        for raw in refused {
            XCTAssertFalse(policy.allowsWrite(path(raw)), raw)
        }
    }

    func testTraversalNeverBecomesAPath() {
        // spec: "events/ios-7f3a91c2/../../projection/projection.v1.json" is
        // refused before any check can be fooled by it.
        XCTAssertNil(HubPath("events/ios-7f3a91c2/../../projection/projection.v1.json"))
        XCTAssertNil(HubPath("events/ios-7f3a91c2/../ios-00000000/x.jsonl"))
    }

    func testWithoutADeviceIdNoEventsPathIsAllowed() {
        let noIdentity = VaultPathPolicy(ownDeviceID: nil)
        XCTAssertTrue(noIdentity.allowsRead(VaultHub.projectionPath))
        XCTAssertFalse(noIdentity.allowsRead(path("events/ios-7f3a91c2/x.jsonl")))
        XCTAssertFalse(noIdentity.allowsWrite(path("events/ios-7f3a91c2/x.jsonl")))
    }

    // MARK: - Device ids

    func testDeviceIdFormat() {
        XCTAssertNotNil(VaultDeviceID("ios-7f3a91c2"))
        for raw in ["ios-7F3A91C2", "ios-7f3a91c", "ios-7f3a91c2x", "ios-7f3a91cg", "android-7f3a91c2", "ios7f3a91c2", ""] {
            XCTAssertNil(VaultDeviceID(raw), raw)
        }
        for _ in 0..<50 {
            XCTAssertTrue(VaultDeviceID.isValid(VaultDeviceID.random().rawValue))
        }
    }
}
