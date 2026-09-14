// KeychainSpike.swift
//
// Shared between the app and the widget extension — this is task 6.4's
// actual test subject, not production code. If both processes can read a
// value the other wrote to this Keychain access group, design.md D3's
// shared-token design proceeds as planned. If not, D3's degraded fallback
// (each process bootstraps independently) is what gets built instead.
//
// This is throwaway spike code. It does not belong in GarminKit and should
// not be copied forward — GarminKit's real TokenProvider (task 7.4) is a
// proper implementation; this is just a yes/no probe.

import Foundation
import Security

enum KeychainSpike {
    // Must match the keychain-access-groups entitlement on BOTH targets in
    // project.yml. The leading $(AppIdentifierPrefix) there is resolved by
    // the OS at signing time from the actual team/prefix — this constant is
    // deliberately just the group's own name, not the qualified form.
    private static let service = "com.mlcousek.garminfood.spike"
    private static let account = "keychain-sharing-test"
    private static let accessGroup = "com.mlcousek.garminfood.shared"

    /// Overwrites the stored test value. Called by the app on launch.
    @discardableResult
    static func write(_ value: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(query as CFDictionary) // clear any stale value first, ignore result

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    /// Reads the stored test value. Called by the widget extension.
    /// Returns (nil, status) on failure — status distinguishes "not found
    /// yet" (errSecItemNotFound) from "access denied" (errSecMissingEntitlement
    /// or similar), which matters for diagnosing *why* sharing failed if it does.
    static func read() -> (value: String?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return (nil, status)
        }
        return (value, status)
    }
}
