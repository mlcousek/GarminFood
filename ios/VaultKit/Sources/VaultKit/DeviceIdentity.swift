// DeviceIdentity.swift
//
// This install's identity towards the vault (add-vault-connection design
// D5): an id `ios-` + 8 lowercase hex characters, and a sequence counter
// that numbers the events this install will write (from
// add-training-checkins on). The id names the install's own events folder,
// the only place `VaultPathPolicy` lets it write -- so two installs must
// never share one.
//
// Why these choices:
//   - Created on the first SUCCESSFUL "Test connection", not on install:
//     an install that never connects never has one.
//   - Stored in the app container (`VaultKit/device-identity.json`), not the
//     Keychain: a fresh container (reinstall, new phone) must get a new id.
//     The Keychain can outlive a reinstall.
//   - Never restored from a backup (a `BackupExclusions` rule on
//     `VaultKit/`): restoring on a new phone therefore creates a new id,
//     restoring on the same phone keeps the file already there.
//   - `reserveSequence(count:)` persists the new counter BEFORE returning
//     the numbers, so a crash can skip numbers but never hand one out twice.
//
// Loaded through GarminKit's `PersistedJSON` (quarantine an undecodable
// file, never wipe; refuse to save over a file that exists but could not be
// read yet, e.g. before first unlock).
//
// Depended on by: VaultPathPolicy (the id), the app's VaultController
// (created after a successful test; shown under Details). Tests:
// DeviceIdentityTests, StoreFixtureTests.

import Foundation
import GarminKit

/// `ios-` followed by exactly 8 lowercase hex characters.
public struct VaultDeviceID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    /// A new random id from a UUID's first 8 hex digits.
    public static func random() -> VaultDeviceID {
        let hex = UUID().uuidString.lowercased().filter { $0 != "-" }
        // A UUID string always has 32 hex digits, so this cannot fail.
        return VaultDeviceID("ios-" + String(hex.prefix(8)))!
    }

    static func isValid(_ value: String) -> Bool {
        guard value.hasPrefix("ios-") else { return false }
        let hex = value.dropFirst(4).unicodeScalars
        guard hex.count == 8 else { return false }
        return hex.allSatisfy { scalar in
            switch scalar.value {
            case 0x30...0x39, 0x61...0x66: return true // 0-9 a-f
            default: return false
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let id = VaultDeviceID(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an ios-xxxxxxxx device id")
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `device-identity.json`'s content.
public struct DeviceIdentityRecord: Codable, Equatable, Sendable {
    public let deviceId: VaultDeviceID
    public let createdAt: Date
    /// The next sequence number `reserveSequence` will hand out (1-based).
    public var nextSequence: Int

    public init(deviceId: VaultDeviceID, createdAt: Date, nextSequence: Int = 1) {
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.nextSequence = nextSequence
    }
}

public enum DeviceIdentityError: Error, Equatable, Sendable {
    /// `reserveSequence` before `ensureIdentity`.
    case noIdentity
    case invalidCount
}

public actor DeviceIdentityStore {
    public static let fileName = "device-identity.json"

    private let fileURL: URL
    private let makeID: @Sendable () -> VaultDeviceID
    private var record: DeviceIdentityRecord?
    private var loaded = false

    public init(
        directory: URL = VaultStorage.defaultDirectory(),
        makeID: @escaping @Sendable () -> VaultDeviceID = { VaultDeviceID.random() }
    ) {
        self.fileURL = directory.appendingPathComponent("device-identity.json")
        self.makeID = makeID
    }

    /// See PersistedJSON.swift: `.unreadable` leaves `loaded` unset so the
    /// next access retries the read.
    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = PersistedJSON.load(DeviceIdentityRecord.self, from: fileURL, decoder: VaultStorage.makeDecoder(), category: VaultLog.category)
        record = result.value
        loaded = !result.isUnreadable
    }

    private func persist(_ newRecord: DeviceIdentityRecord) throws {
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: VaultLog.category)
        let data = try VaultStorage.makeEncoder().encode(newRecord)
        try VaultStorage.write(data, to: fileURL)
    }

    /// The identity, or `nil` before the first successful connection test.
    public func current() -> DeviceIdentityRecord? {
        loadIfNeeded()
        return record
    }

    public func currentID() -> VaultDeviceID? {
        current()?.deviceId
    }

    /// Returns the existing identity, or creates, persists and returns a new
    /// one. Only a successful write makes it the current identity.
    @discardableResult
    public func ensureIdentity(now: Date = Date()) throws -> DeviceIdentityRecord {
        loadIfNeeded()
        if let record { return record }
        let created = DeviceIdentityRecord(deviceId: makeID(), createdAt: now)
        try persist(created)
        record = created
        VaultLog.log(.info, "device identity created (\(created.deviceId.rawValue))")
        return created
    }

    /// Reserves `count` consecutive sequence numbers. The advanced counter
    /// is on disk before the numbers are returned (see this file's header).
    public func reserveSequence(count: Int) throws -> ClosedRange<Int> {
        guard count >= 1 else { throw DeviceIdentityError.invalidCount }
        loadIfNeeded()
        guard var updated = record else { throw DeviceIdentityError.noIdentity }
        let first = updated.nextSequence
        updated.nextSequence = first + count
        try persist(updated)
        record = updated
        return first...(first + count - 1)
    }
}
