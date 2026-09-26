// BackupManifest.swift
//
// add-data-safety D3/D4/D5: the self-description every backup carries --
// an on-device snapshot (`Backups/<id>/manifest.json`), the staged restore
// (`Backups/.pending-restore/manifest.json`) and an exported file
// (`BackupContainer.manifest`). Why a manifest at all rather than just the
// copied files: a restore has to decide, BEFORE touching anything, whether
// this build can read what it is about to put back (`BackupCompatibility`),
// and the Data screen / import preview need a date, an app version and a
// kind without opening every store file.
//
// Also holds `BackupContainer` (the single exported `.json` file: manifest +
// every data file as base64 + typed preferences; design D5 explains why a
// JSON container and not a zip) and `BackupCompatibility` (the refusal rules
// of D4). Pure Codable -- testable with `swift test`, no UI, no network.
//
// Depends on: StoreCatalog (store ids and versions), PreferenceValue.
// Depended on by: BackupVault, BackupPreview, the app's DataSafetyController.

import Foundation

/// Why a backup was written. Decoded leniently (unknown -> `.export`) so a
/// newer app's new kind doesn't make an otherwise readable backup unreadable.
public enum BackupKind: String, Codable, Sendable, CaseIterable {
    /// The once-a-day snapshot taken when the app comes to the foreground.
    case automatic
    /// "Back up now" on the Data screen.
    case manual
    /// Taken right before a restore replaces the data (design D4).
    case safety
    /// A single-file export (`BackupContainer`).
    case export
}

/// One data file inside a backup, with the store it belongs to (when this
/// build's catalog knows it) and that store's schema version at backup time.
public struct BackupFileRecord: Codable, Equatable, Sendable {
    /// Relative to Application Support, `/`-separated.
    public let path: String
    public let byteCount: Int
    /// `nil` for a file no catalog entry matches (a store newer than the
    /// catalog, or not registered yet) -- it is still backed up.
    public let storeId: String?
    public let storeVersion: Int?

    public init(path: String, byteCount: Int, storeId: String?, storeVersion: Int?) {
        self.path = path
        self.byteCount = byteCount
        self.storeId = storeId
        self.storeVersion = storeVersion
    }

    /// A record for `path`, looked up in `catalog`.
    public static func make(path: String, byteCount: Int, catalog: [StoreCatalogEntry] = StoreCatalog.entries) -> BackupFileRecord {
        let entry = catalog.first { $0.location.matches(relativePath: path) }
        return BackupFileRecord(path: path, byteCount: byteCount, storeId: entry?.id, storeVersion: entry?.schemaVersion)
    }
}

public struct BackupManifest: Codable, Equatable, Sendable {
    /// Marks a file as a GarminFood backup at all.
    public static let schemaIdentifier = "garminfood.backup"
    /// Bumped when the backup layout itself (not a store) changes in a way
    /// an older build can't read.
    public static let currentFormatVersion = 1

    public let schema: String
    public let formatVersion: Int
    public let kind: BackupKind
    public let createdAt: Date
    /// `CFBundleShortVersionString (CFBundleVersion)` of the writing build.
    public let appVersion: String?
    public let files: [BackupFileRecord]

    public init(
        schema: String = BackupManifest.schemaIdentifier,
        formatVersion: Int = BackupManifest.currentFormatVersion,
        kind: BackupKind,
        createdAt: Date,
        appVersion: String?,
        files: [BackupFileRecord]
    ) {
        self.schema = schema
        self.formatVersion = formatVersion
        self.kind = kind
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.files = files
    }

    private enum CodingKeys: String, CodingKey {
        case schema, formatVersion, kind, createdAt, appVersion, files
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind) ?? BackupKind.export.rawValue
        kind = BackupKind(rawValue: rawKind) ?? .export
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        files = try container.decodeIfPresent([BackupFileRecord].self, forKey: .files) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        try container.encode(files, forKey: .files)
    }

    /// Same backup, different kind or file list (staging rewrites the file
    /// list to what it actually staged).
    func with(files newFiles: [BackupFileRecord]) -> BackupManifest {
        BackupManifest(schema: schema, formatVersion: formatVersion, kind: kind, createdAt: createdAt, appVersion: appVersion, files: newFiles)
    }
}

/// The exported single file (design D5): the manifest, every data file's
/// exact bytes (base64 -- JSONEncoder's default for `Data`) and the typed
/// preferences.
public struct BackupContainer: Codable, Equatable, Sendable {
    public struct File: Codable, Equatable, Sendable {
        public let path: String
        public let contents: Data

        public init(path: String, contents: Data) {
            self.path = path
            self.contents = contents
        }
    }

    public let manifest: BackupManifest
    public let files: [File]
    public let preferences: [String: PreferenceValue]

    public init(manifest: BackupManifest, files: [File], preferences: [String: PreferenceValue]) {
        self.manifest = manifest
        self.files = files
        self.preferences = preferences
    }

    /// The file's bytes: pretty-printed, sorted keys, ISO-8601 dates, so it
    /// is readable (and diffable) in a text editor.
    public func encoded() throws -> Data {
        try BackupCoding.encoder().encode(self)
    }

    /// Decodes an exported file, refusing (with `BackupError`) anything
    /// that isn't a GarminFood backup or that this build is too old for --
    /// before decoding the body, so a newer layout fails as "update the
    /// app", not as a decoding error.
    public static func decode(_ data: Data) throws -> BackupContainer {
        let decoder = BackupCoding.decoder()
        guard let header = try? decoder.decode(ContainerHeader.self, from: data),
              header.manifest.schema == BackupManifest.schemaIdentifier else {
            throw BackupError.notABackup
        }
        if header.manifest.formatVersion > BackupManifest.currentFormatVersion {
            throw BackupError.newerFormat(found: header.manifest.formatVersion, supported: BackupManifest.currentFormatVersion)
        }
        let container: BackupContainer
        do {
            container = try decoder.decode(BackupContainer.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
        try BackupCompatibility.check(container.manifest)
        for file in container.files where !BackupPath.isSafe(file.path) {
            throw BackupError.unsafePath(file.path)
        }
        return container
    }

    private struct ContainerHeader: Decodable {
        let manifest: ManifestHeader
    }
}

/// Just enough of a manifest to decide whether to read the rest.
struct ManifestHeader: Decodable {
    let schema: String
    let formatVersion: Int
}

/// The encoder/decoder every backup file uses (manifest, preferences,
/// status, container). Store files themselves are copied as raw bytes and
/// never re-encoded.
enum BackupCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Everything a backup operation can refuse or fail with. The app maps
/// these to user-facing text (DataSafetyController); `diagnosticDescription`
/// is what goes to DiagnosticsLog.
public enum BackupError: Error, Equatable, Sendable {
    /// Not a GarminFood backup (wrong schema, or not decodable at all).
    case notABackup
    /// Written by a newer app whose backup layout this build can't read.
    case newerFormat(found: Int, supported: Int)
    /// Contains a store in a newer format than this build knows.
    case newerStoreVersion(storeId: String, found: Int, supported: Int)
    /// A path that would escape the data directory.
    case unsafePath(String)
    case snapshotNotFound(String)
    /// The safety snapshot before a restore couldn't be written, so the
    /// restore was abandoned with nothing changed.
    case safetySnapshotFailed(String)
    /// A file operation failed; the message is the underlying error.
    case fileOperationFailed(String)

    public var diagnosticDescription: String {
        switch self {
        case .notABackup: return "not a GarminFood backup"
        case .newerFormat(let found, let supported): return "backup format \(found) is newer than supported \(supported)"
        case .newerStoreVersion(let storeId, let found, let supported): return "store \(storeId) version \(found) is newer than supported \(supported)"
        case .unsafePath(let path): return "unsafe path in backup: \(path)"
        case .snapshotNotFound(let id): return "snapshot \(id) not found"
        case .safetySnapshotFailed(let message): return "safety snapshot failed: \(message)"
        case .fileOperationFailed(let message): return "file operation failed: \(message)"
        }
    }

    /// Whether the fix is updating the app (versus a broken file).
    public var needsNewerApp: Bool {
        switch self {
        case .newerFormat, .newerStoreVersion: return true
        default: return false
        }
    }
}

/// Design D4's version check: a backup is refused, with nothing changed,
/// when it isn't a GarminFood backup, when its layout is newer than this
/// build, or when any file's store version is newer than this build's
/// catalog. A file whose store this build doesn't know is allowed -- it is
/// restored, ignored by this build, and read by a later update.
public enum BackupCompatibility {
    public static func check(_ manifest: BackupManifest, catalog: [StoreCatalogEntry] = StoreCatalog.entries) throws {
        guard manifest.schema == BackupManifest.schemaIdentifier else {
            throw BackupError.notABackup
        }
        guard manifest.formatVersion <= BackupManifest.currentFormatVersion else {
            throw BackupError.newerFormat(found: manifest.formatVersion, supported: BackupManifest.currentFormatVersion)
        }
        for file in manifest.files {
            guard let storeId = file.storeId, let found = file.storeVersion,
                  let known = catalog.first(where: { $0.id == storeId }) else { continue }
            if found > known.schemaVersion {
                throw BackupError.newerStoreVersion(storeId: storeId, found: found, supported: known.schemaVersion)
            }
        }
    }
}
