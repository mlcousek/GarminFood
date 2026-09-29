// VaultTokenTests.swift
//
// add-vault-connection task 2.6 (design D3): only fine-grained tokens are
// accepted (classic `ghp_` refused, owner decision 0.2 default), a paste's
// whitespace is trimmed, the token never prints itself, and the Keychain
// round trip works under its own service name. The Keychain part runs only
// where the macOS runner's Keychain allows `SecItemAdd` from a test
// process; elsewhere it is skipped (the prefix rules always run).

import XCTest
@testable import VaultKit

final class VaultTokenTests: XCTestCase {
    private static func fake(_ prefix: String, _ bodyLength: Int = 40) -> String {
        prefix + String(repeating: "A1b2", count: bodyLength / 4)
    }

    func testAcceptsFineGrainedTokensAndTrimsThePaste() throws {
        let token = try VaultToken(validating: "  " + TestSupport.plantedTokenString + "\n")
        XCTAssertEqual(token, TestSupport.token)
        XCTAssertEqual(token.lastFour, "zq9x")
        XCTAssertEqual(token.authorizationHeaderValue, "Bearer " + TestSupport.plantedTokenString)
    }

    func testRefusesClassicAndOtherTokens() {
        XCTAssertThrowsError(try VaultToken(validating: Self.fake("gh" + "p_"))) { error in
            XCTAssertEqual(error as? VaultTokenProblem, .classicToken)
        }
        for prefix in ["gh" + "o_", "gh" + "u_", "gh" + "s_", "gh" + "r_", "", "bearer "] {
            XCTAssertThrowsError(try VaultToken(validating: Self.fake(prefix)), prefix) { error in
                XCTAssertEqual(error as? VaultTokenProblem, .notFineGrained)
            }
        }
        XCTAssertThrowsError(try VaultToken(validating: "   \n")) { error in
            XCTAssertEqual(error as? VaultTokenProblem, .empty)
        }
    }

    func testRefusesMalformedFineGrainedTokens() {
        let prefix = VaultToken.fineGrainedPrefix
        for raw in [prefix, prefix + "short", Self.fake(prefix) + " tail", Self.fake(prefix) + "-dash", prefix + String(repeating: "a", count: 256), Self.fake(prefix) + "é"] {
            XCTAssertThrowsError(try VaultToken(validating: raw)) { error in
                XCTAssertEqual(error as? VaultTokenProblem, .malformed)
            }
        }
    }

    func testTheTokenNeverPrintsItself() {
        let token = TestSupport.token
        var dumped = ""
        dump(token, to: &dumped)
        for text in ["\(token)", String(describing: token), String(reflecting: token), dumped, "\([token])", "\(Optional(token) as Any)"] {
            XCTAssertFalse(text.contains(TestSupport.plantedTokenString), text)
            XCTAssertFalse(text.contains("PLANTED0"), text)
        }
        let credentials = TestSupport.credentials
        var dumpedCredentials = ""
        dump(credentials, to: &dumpedCredentials)
        XCTAssertFalse(dumpedCredentials.contains("PLANTED0"))
    }

    func testKnownPrefixesCoverEveryGitHubTokenKind() {
        XCTAssertEqual(Set(VaultToken.knownPrefixes), ["github_pat_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_"])
    }

    func testKeychainRoundTripUnderItsOwnService() throws {
        let store = VaultTokenStore(service: "com.mlcousek.garminfood.vault.tests.\(UUID().uuidString)")
        addTeardownBlock { store.delete() }
        do {
            try store.save(TestSupport.token)
        } catch VaultTokenStoreError.writeFailed(let status) {
            throw XCTSkip("Keychain not writable from this test process (OSStatus \(status))")
        }
        XCTAssertEqual(try store.load(), TestSupport.token)
        // Upsert, not add-that-fails.
        try store.save(TestSupport.token)
        XCTAssertEqual(try store.load(), TestSupport.token)
        store.delete()
        XCTAssertNil(try store.load())
        XCTAssertEqual(VaultTokenStore.defaultService, "com.mlcousek.garminfood.vault")
    }
}
