// BackupVault.swift
//
// add-data-safety D3/D4/D5: every file operation behind the Data screen --
// daily snapshots with retention, the single-file export, and the two-step
// restore (stage now, apply at the next launch). Pure file I/O over a data
// directory passed in (Application Support in the app, a temp directory in
// tests), so the whole thing is tested with real files and `swift test`.
//
// Why it works on FILES, generically, rather than on decoded stores: a store
// added later (supplements, a future goals store) is snapshotted, exported
// and restored the day it ships, without registering anywhere; and a restore
// writes back the exact original bytes, so each store's own decoder, shims
// and quarantine (#36) apply unchanged when it next loads.
//
// Why restore is staged and applied at launch (design D4): every store is
// loaded once per process and saved from memory; replacing files under a
// running app would be undone by the next save. `applyPendingRestore` must
// therefore run before `AppServices.shared` exists -- see the app's
// `DataSafetyLaunch`.
//
// Layout under `<data>/Backups/`:
//   <id>/manifest.json, <id>/preferences.json, <id>/data/<relative path>
//   .pending-restore/   (same layout; the staged restore)
//   .tmp-<uuid>/        (in-progress writes, renamed into place when done)
//   status.json         (BackupStatus)
//
// Not thread-safe by itself: the app runs at most one operation at a time
// (DataSafetyController serialises them). Tokens are never here -- they live
// in the Keychain -- and BackupExclusions/BackupSecretPolicy keep anything
// token-shaped out anyway.
//
// Depends on: BackupExclusions, BackupSecretPolicy, BackupManifest,
// PreferenceValue, StoreCatalog.
// Depended on by: the app's DataSafetyController and DataSafetyLaunch.

import Foundation

/// One snapshot directory on disk.
public struct BackupSnapshot: Equatable, Sendable, Identifiable {
    /// The directory name: `yyyy-MM-dd` for daily/manual snapshots,
    /// `safety-yyyy-MM-dd-HHmmss-xxxx` for safety snapshots.
    public let id: String
    public let manifest: BackupManifest

    public init(id: String, manifest: BackupManifest) {
        self.id = id
        self.manifest = manifest
    }
}

/// The outcome of writing a snapshot.
public struct BackupSnapshotResult: Equatable, Sendable {
    public let snapshot: BackupSnapshot
    /// Files left out because their content looked like a credential
    /// (`BackupSecretPolicy`). The app logs them.
    public let skippedPaths: [String]
}

/// What `applyPendingRestore` did, for the app to finish (preferences) and
/// report.
public struct AppliedRestore: Equatable, Sendable {
    public let manifest: BackupManifest
    /// The backup's preferences, to apply with
    /// `PreferencesBackup.restoredDomain`. `nil` when the backup had no
    /// preferences file, in which case the current preferences stay.
    public let preferences: [String: PreferenceValue]?
    public let safetySnapshotId: String
}

/// `Backups/status.json`: the outcome of the last attempts, shown on the
/// Data screen (design D3/D6).
public struct BackupStatus: Codable, Equatable, Sendable {
    public struct RestoreRecord: Codable, Equatable, Sendable {
        public var at: Date
        public var succeeded: Bool
        /// When the restored backup was created.
        public var backupCreatedAt: Date?
        /// `BackupError.diagnosticDescription` on failure.
        public var message: String?
        /// Set once the Data screen has shown the result.
        public var acknowledged: Bool?

        public init(at: Date, succeeded: Bool, backupCreatedAt: Date?, message: String?, acknowledged: Bool? = nil) {
            self.at = at
            self.succeeded = succeeded
            self.backupCreatedAt = backupCreatedAt
            self.message = message
            self.acknowledged = acknowledged
        }
    }

    /// Last automatic or manual snapshot attempt.
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    /// The last attempt's error, `nil` once an attempt succeeds.
    public var lastError: String?
    public var lastRestore: RestoreRecord?

    public init(lastAttemptAt: Date? = nil, lastSuccessAt: Date? = nil, lastError: String? = nil, lastRestore: RestoreRecord? = nil) {
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
        self.lastRestore = lastRestore
    }
}

public struct BackupVault: Sendable {
    /// Automatic + manual snapshots kept (one per day at most).
    public static let regularRetention = 14
    /// Safety snapshots kept.
    public static let safetyRetention = 5
    /// A failed automatic attempt isn't retried sooner than this.
    public static let retryInterval: TimeInterval = 60 * 60

    static let pendingRestoreName = ".pending-restore"
    static let temporaryPrefix = ".tmp-"
    static let manifestName = "manifest.json"
    static let preferencesName = "preferences.json"
    static let dataName = "data"
    static let statusName = "status.json"

    /// The directory backed up: Application Support in the app.
    public let dataDirectory: URL

    public init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory
    }

    /// The app's real data directory.
    public static func applicationSupport() -> BackupVault {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return BackupVault(dataDirectory: base)
    }

    public var backupsDirectory: URL {
        dataDirectory.appendingPathComponent(BackupExclusions.backupsDirectoryName, isDirectory: true)
    }

    var pendingRestoreDirectory: URL {
        backupsDirectory.appendingPathComponent(Self.pendingRestoreName, isDirectory: true)
    }

    private var statusURL: URL {
        backupsDirectory.appendingPathComponent(Self.statusName)
    }

    // MARK: - Data files

    /// Every file a backup includes right now, relative to `dataDirectory`,
    /// sorted. Generic: a recursive walk filtered by
    /// `BackupExclusions.includesFile`.
    public func includedDataFiles() throws -> [String] {
        try Self.includedFiles(under: dataDirectory)
    }

    static func includedFiles(under root: URL) throws -> [String] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        var result: [String] = []
        try walk(root: root, relative: "", into: &result)
        return result.sorted()
    }

    private static func walk(root: URL, relative: String, into result: inout [String]) throws {
        let fileManager = FileManager.default
        let directory = relative.isEmpty ? root : root.appendingPathComponent(relative, isDirectory: true)
        for name in try fileManager.contentsOfDirectory(atPath: directory.path) {
            let childRelative = relative.isEmpty ? name : relative + "/" + name
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.appendingPathComponent(name).path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                // Never descend into our own backups.
                if childRelative == BackupExclusions.backupsDirectoryName { continue }
                try walk(root: root, relative: childRelative, into: &result)
            } else if BackupExclusions.includesFile(relativePath: childRelative) {
                result.append(childRelative)
            }
        }
    }

    private func fileURL(_ relativePath: String, under root: URL) -> URL {
        root.appendingPathComponent(relativePath, isDirectory: false)
    }

    // MARK: - Snapshots

    /// Every readable snapshot, newest first. A directory whose manifest
    /// can't be read is skipped (and never pruned).
    public func listSnapshots() -> [BackupSnapshot] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: backupsDirectory.path) else { return [] }
        var snapshots: [BackupSnapshot] = []
        for name in names where !name.hasPrefix(".") {
            let directory = backupsDirectory.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            guard let manifest = try? readManifest(in: directory) else { continue }
            snapshots.append(BackupSnapshot(id: name, manifest: manifest))
        }
        return snapshots.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    /// Whether the once-a-day automatic snapshot should run: no automatic
    /// or manual snapshot from today's calendar day, and no attempt within
    /// `retryInterval` (so a failing or empty data set doesn't retry on
    /// every foreground).
    public func isAutomaticSnapshotDue(now: Date, calendar: Calendar = .current) -> Bool {
        let takenToday = listSnapshots().contains {
            $0.manifest.kind != .safety && calendar.isDate($0.manifest.createdAt, inSameDayAs: now)
        }
        if takenToday { return false }
        if let lastAttempt = status().lastAttemptAt, now.timeIntervalSince(lastAttempt) >= 0, now.timeIntervalSince(lastAttempt) < Self.retryInterval {
            return false
        }
        return true
    }

    /// The job the app runs when a scene becomes active (design D3): an
    /// automatic snapshot when `isAutomaticSnapshotDue`, otherwise nothing.
    /// `preferences` is an autoclosure so the UserDefaults domain is only
    /// read when a snapshot is actually taken. Returns `nil` when nothing
    /// was written (not due, or an empty data set).
    @discardableResult
    public func writeAutomaticSnapshotIfDue(
        preferences: @autoclosure () -> [String: PreferenceValue],
        appVersion: String?,
        now: Date,
        calendar: Calendar = .current
    ) throws -> BackupSnapshotResult? {
        guard isAutomaticSnapshotDue(now: now, calendar: calendar) else { return nil }
        return try writeSnapshot(kind: .automatic, preferences: preferences(), appVersion: appVersion, now: now, calendar: calendar)
    }

    /// Copies every included data file plus `preferences` into a new
    /// snapshot, written to a temp directory and renamed into place, then
    /// prunes old ones. A daily or manual snapshot replaces the same day's
    /// (so there is at most one per day). Returns `nil`, writing nothing,
    /// for a daily or manual snapshot of an EMPTY data set -- a wiped or
    /// brand-new container must not rotate good snapshots out.
    /// Automatic and manual attempts are recorded in `status.json`.
    @discardableResult
    public func writeSnapshot(
        kind: BackupKind,
        preferences: [String: PreferenceValue],
        appVersion: String?,
        now: Date,
        calendar: Calendar = .current
    ) throws -> BackupSnapshotResult? {
        let recordsStatus = kind == .automatic || kind == .manual
        do {
            let result = try writeSnapshotUnrecorded(kind: kind, preferences: preferences, appVersion: appVersion, now: now, calendar: calendar)
            if recordsStatus {
                updateStatus { status in
                    status.lastAttemptAt = now
                    if result != nil {
                        status.lastSuccessAt = now
                    }
                    status.lastError = nil
                }
            }
            return result
        } catch {
            if recordsStatus {
                updateStatus { status in
                    status.lastAttemptAt = now
                    status.lastError = Self.describe(error)
                }
            }
            throw error
        }
    }

    private func writeSnapshotUnrecorded(
        kind: BackupKind,
        preferences: [String: PreferenceValue],
        appVersion: String?,
        now: Date,
        calendar: Calendar
    ) throws -> BackupSnapshotResult? {
        let paths = try includedDataFiles()
        if paths.isEmpty && kind != .safety { return nil }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let temporary = backupsDirectory.appendingPathComponent(Self.temporaryPrefix + UUID().uuidString, isDirectory: true)
        let dataRoot = temporary.appendingPathComponent(Self.dataName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: dataRoot, withIntermediateDirectories: true)
            var records: [BackupFileRecord] = []
            var skipped: [String] = []
            for path in paths {
                let contents = try Data(contentsOf: fileURL(path, under: dataDirectory))
                if BackupSecretPolicy.containsSecret(contents) {
                    skipped.append(path)
                    continue
                }
                try Self.write(contents, to: fileURL(path, under: dataRoot))
                records.append(.make(path: path, byteCount: contents.count))
            }
            let manifest = BackupManifest(kind: kind, createdAt: now, appVersion: appVersion, files: records)
            try writeManifest(manifest, preferences: preferences, in: temporary)

            let id = Self.snapshotId(kind: kind, now: now, calendar: calendar)
            try Self.install(temporary, at: backupsDirectory.appendingPathComponent(id, isDirectory: true), temporaryParent: backupsDirectory)
            prune()
            return BackupSnapshotResult(snapshot: BackupSnapshot(id: id, manifest: manifest), skippedPaths: skipped)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    /// `yyyy-MM-dd` (local calendar day) for daily/manual snapshots;
    /// safety snapshots get a time and a random suffix so two restores on
    /// one day keep both.
    static func snapshotId(kind: BackupKind, now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let day = pad(parts.year, 4) + "-" + pad(parts.month, 2) + "-" + pad(parts.day, 2)
        guard kind == .safety else { return day }
        let time = pad(parts.hour, 2) + pad(parts.minute, 2) + pad(parts.second, 2)
        return "safety-\(day)-\(time)-\(UUID().uuidString.prefix(4).lowercased())"
    }

    private static func pad(_ value: Int?, _ width: Int) -> String {
        let digits = String(value ?? 0)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    /// The snapshot ids retention removes: beyond the newest
    /// `regularRetention` daily/manual ones and the newest
    /// `safetyRetention` safety ones.
    public static func idsToPrune(_ snapshots: [BackupSnapshot], keepRegular: Int = regularRetention, keepSafety: Int = safetyRetention) -> [String] {
        let newestFirst = snapshots.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
        let regular = newestFirst.filter { $0.manifest.kind != .safety }
        let safety = newestFirst.filter { $0.manifest.kind == .safety }
        return regular.dropFirst(keepRegular).map(\.id) + safety.dropFirst(keepSafety).map(\.id)
    }

    /// Applies retention and removes leftover `.tmp-*` directories (a
    /// write interrupted by a crash). Best effort.
    public func prune() {
        let fileManager = FileManager.default
        for id in Self.idsToPrune(listSnapshots()) {
            try? fileManager.removeItem(at: backupsDirectory.appendingPathComponent(id, isDirectory: true))
        }
        if let names = try? fileManager.contentsOfDirectory(atPath: backupsDirectory.path) {
            for name in names where name.hasPrefix(Self.temporaryPrefix) {
                try? fileManager.removeItem(at: backupsDirectory.appendingPathComponent(name, isDirectory: true))
            }
        }
    }

    // MARK: - Export

    /// The single-file export (design D5): every included data file's
    /// exact bytes plus `preferences`.
    public func makeExportContainer(preferences: [String: PreferenceValue], appVersion: String?, now: Date) throws -> (container: BackupContainer, skippedPaths: [String]) {
        var files: [BackupContainer.File] = []
        var records: [BackupFileRecord] = []
        var skipped: [String] = []
        for path in try includedDataFiles() {
            let contents = try Data(contentsOf: fileURL(path, under: dataDirectory))
            if BackupSecretPolicy.containsSecret(contents) {
                skipped.append(path)
                continue
            }
            files.append(BackupContainer.File(path: path, contents: contents))
            records.append(.make(path: path, byteCount: contents.count))
        }
        let manifest = BackupManifest(kind: .export, createdAt: now, appVersion: appVersion, files: records)
        return (BackupContainer(manifest: manifest, files: files, preferences: preferences), skipped)
    }

    /// `GarminFood-backup-yyyy-MM-dd.json`.
    public static func exportFileName(now: Date, calendar: Calendar = .current) -> String {
        "GarminFood-backup-\(snapshotId(kind: .export, now: now, calendar: calendar)).json"
    }

    // MARK: - Staging a restore (step 1 of design D4)

    /// The staged restore's manifest, if one is waiting for the next launch.
    public func pendingRestore() -> BackupManifest? {
        try? readManifest(in: pendingRestoreDirectory)
    }

    /// Stages snapshot `snapshotId` for the next launch. Refuses an
    /// incompatible snapshot with nothing changed.
    @discardableResult
    public func stageRestore(snapshotId: String) throws -> BackupManifest {
        guard BackupPath.isSafe(snapshotId), !snapshotId.contains("/"), !snapshotId.hasPrefix(".") else {
            throw BackupError.snapshotNotFound(snapshotId)
        }
        let source = backupsDirectory.appendingPathComponent(snapshotId, isDirectory: true)
        guard let manifest = try? readManifest(in: source) else {
            throw BackupError.snapshotNotFound(snapshotId)
        }
        try BackupCompatibility.check(manifest)
        let preferences = readPreferences(in: source)

        var files: [BackupContainer.File] = []
        for path in try Self.includedFiles(under: source.appendingPathComponent(Self.dataName, isDirectory: true)) {
            files.append(BackupContainer.File(path: path, contents: try Data(contentsOf: fileURL(path, under: source.appendingPathComponent(Self.dataName, isDirectory: true)))))
        }
        return try stage(manifest: manifest, files: files, preferences: preferences)
    }

    /// Stages an imported file for the next launch. Refuses an
    /// incompatible or unsafe container with nothing changed.
    @discardableResult
    public func stageRestore(container: BackupContainer) throws -> BackupManifest {
        try BackupCompatibility.check(container.manifest)
        return try stage(manifest: container.manifest, files: container.files, preferences: container.preferences)
    }

    /// Removes the staged restore; the data stays exactly as it is.
    public func cancelPendingRestore() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: pendingRestoreDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: pendingRestoreDirectory)
        } catch {
            throw BackupError.fileOperationFailed(error.localizedDescription)
        }
    }

    private func stage(manifest: BackupManifest, files: [BackupContainer.File], preferences: [String: PreferenceValue]?) throws -> BackupManifest {
        for file in files where !BackupPath.isSafe(file.path) {
            throw BackupError.unsafePath(file.path)
        }
        let fileManager = FileManager.default
        let temporary = backupsDirectory.appendingPathComponent(Self.temporaryPrefix + UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: temporary.appendingPathComponent(Self.dataName, isDirectory: true), withIntermediateDirectories: true)
            var records: [BackupFileRecord] = []
            for file in files where BackupExclusions.includesFile(relativePath: file.path) && !BackupSecretPolicy.containsSecret(file.contents) {
                try Self.write(file.contents, to: fileURL(file.path, under: temporary.appendingPathComponent(Self.dataName, isDirectory: true)))
                // Keep the backup's own store id/version: they describe the
                // bytes, which this build's catalog might not.
                let original = manifest.files.first { $0.path == file.path }
                records.append(original ?? .make(path: file.path, byteCount: file.contents.count))
            }
            let staged = manifest.with(files: records)
            try writeManifest(staged, preferences: preferences, in: temporary)
            try Self.install(temporary, at: pendingRestoreDirectory, temporaryParent: backupsDirectory)
            return staged
        } catch let error as BackupError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw BackupError.fileOperationFailed(error.localizedDescription)
        }
    }

    // MARK: - Applying a staged restore (step 2 of design D4)

    /// Applies the staged restore, if any. Must run before any store is
    /// loaded (the app calls it from `GarminFoodApp.init`). Synchronous,
    /// file operations only.
    ///
    /// 1. Re-checks compatibility (this build may be older than the one
    ///    that staged it).
    /// 2. Writes a safety snapshot of the current data and
    ///    `currentPreferences`; if that fails nothing is touched.
    /// 3. Deletes the current included files -- excluded ones (outboxes,
    ///    diagnostics, offline index, health cache, Siri ledger) stay.
    /// 4. Copies the staged files in; on failure, puts the safety
    ///    snapshot's files back.
    /// 5. Removes the staged directory and records the outcome.
    ///
    /// Returns `nil` when nothing is staged. The caller applies the
    /// returned preferences with `PreferencesBackup.restoredDomain`. The
    /// staged restore is removed on success AND on failure, so a broken one
    /// can't fail on every launch; the original snapshot or file is still
    /// there to retry.
    public func applyPendingRestore(
        currentPreferences: [String: PreferenceValue],
        appVersion: String?,
        now: Date,
        calendar: Calendar = .current
    ) throws -> AppliedRestore? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: pendingRestoreDirectory.path) else { return nil }

        // Launched in the background before the first unlock after a
        // reboot, the staged files exist but can't be read yet: leave the
        // restore staged for the next launch rather than failing it.
        let manifestURL = pendingRestoreDirectory.appendingPathComponent(Self.manifestName)
        let manifestData = try? Data(contentsOf: manifestURL)
        if manifestData == nil && fileManager.fileExists(atPath: manifestURL.path) {
            return nil
        }

        var backupCreatedAt: Date?
        do {
            guard let manifestData,
                  let manifest = try? BackupCoding.decoder().decode(BackupManifest.self, from: manifestData) else {
                throw BackupError.notABackup
            }
            backupCreatedAt = manifest.createdAt
            try BackupCompatibility.check(manifest)
            let preferences = readPreferences(in: pendingRestoreDirectory)
            let stagedData = pendingRestoreDirectory.appendingPathComponent(Self.dataName, isDirectory: true)
            let stagedPaths = try Self.includedFiles(under: stagedData)

            let safety: BackupSnapshotResult
            do {
                guard let written = try writeSnapshot(kind: .safety, preferences: currentPreferences, appVersion: appVersion, now: now, calendar: calendar) else {
                    throw BackupError.safetySnapshotFailed("no snapshot written")
                }
                safety = written
            } catch let error as BackupError {
                throw error
            } catch {
                throw BackupError.safetySnapshotFailed(error.localizedDescription)
            }

            do {
                try replaceDataFiles(with: stagedPaths, from: stagedData)
            } catch {
                // Put the safety snapshot's files back.
                let safetyData = backupsDirectory
                    .appendingPathComponent(safety.snapshot.id, isDirectory: true)
                    .appendingPathComponent(Self.dataName, isDirectory: true)
                if let safetyPaths = try? Self.includedFiles(under: safetyData) {
                    try? replaceDataFiles(with: safetyPaths, from: safetyData)
                }
                throw BackupError.fileOperationFailed(error.localizedDescription)
            }

            try? fileManager.removeItem(at: pendingRestoreDirectory)
            updateStatus { status in
                status.lastRestore = BackupStatus.RestoreRecord(at: now, succeeded: true, backupCreatedAt: manifest.createdAt, message: nil)
            }
            return AppliedRestore(manifest: manifest, preferences: preferences, safetySnapshotId: safety.snapshot.id)
        } catch {
            try? fileManager.removeItem(at: pendingRestoreDirectory)
            let message = Self.describe(error)
            updateStatus { status in
                status.lastRestore = BackupStatus.RestoreRecord(at: now, succeeded: false, backupCreatedAt: backupCreatedAt, message: message)
            }
            throw error
        }
    }

    /// Deletes every data file a backup would hold, then copies `paths`
    /// from `source`. A file a backup would skip for its content
    /// (`BackupSecretPolicy`) is kept: it isn't in the safety snapshot
    /// either, so deleting it would lose it.
    private func replaceDataFiles(with paths: [String], from source: URL) throws {
        let fileManager = FileManager.default
        for path in try includedDataFiles() {
            let url = fileURL(path, under: dataDirectory)
            if let contents = try? Data(contentsOf: url), BackupSecretPolicy.containsSecret(contents) { continue }
            try fileManager.removeItem(at: url)
        }
        for path in paths where BackupPath.isSafe(path) && BackupExclusions.includesFile(relativePath: path) {
            let destination = fileURL(path, under: dataDirectory)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: fileURL(path, under: source), to: destination)
        }
    }

    // MARK: - Status

    public func status() -> BackupStatus {
        guard let data = try? Data(contentsOf: statusURL),
              let status = try? BackupCoding.decoder().decode(BackupStatus.self, from: data) else {
            return BackupStatus()
        }
        return status
    }

    /// Marks the last restore's result as shown.
    public func acknowledgeLastRestore() {
        updateStatus { status in
            status.lastRestore?.acknowledged = true
        }
    }

    private func updateStatus(_ change: (inout BackupStatus) -> Void) {
        var current = status()
        change(&current)
        guard let data = try? BackupCoding.encoder().encode(current) else { return }
        try? FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try? data.write(to: statusURL, options: .atomic)
    }

    // MARK: - Helpers

    static func describe(_ error: Error) -> String {
        if let backupError = error as? BackupError { return backupError.diagnosticDescription }
        return error.localizedDescription
    }

    private func readManifest(in directory: URL) throws -> BackupManifest {
        let data = try Data(contentsOf: directory.appendingPathComponent(Self.manifestName))
        return try BackupCoding.decoder().decode(BackupManifest.self, from: data)
    }

    /// `nil` when the file is missing or unreadable.
    private func readPreferences(in directory: URL) -> [String: PreferenceValue]? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(Self.preferencesName)) else { return nil }
        return try? BackupCoding.decoder().decode([String: PreferenceValue].self, from: data)
    }

    private func writeManifest(_ manifest: BackupManifest, preferences: [String: PreferenceValue]?, in directory: URL) throws {
        let encoder = BackupCoding.encoder()
        try encoder.encode(manifest).write(to: directory.appendingPathComponent(Self.manifestName), options: .atomic)
        if let preferences {
            try encoder.encode(preferences).write(to: directory.appendingPathComponent(Self.preferencesName), options: .atomic)
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Moves the finished `temporary` directory to `destination`. An
    /// existing destination is first moved aside and deleted only after the
    /// new one is in place, so a crash never leaves neither.
    private static func install(_ temporary: URL, at destination: URL, temporaryParent: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            let aside = temporaryParent.appendingPathComponent(temporaryPrefix + "old-" + UUID().uuidString, isDirectory: true)
            try fileManager.moveItem(at: destination, to: aside)
            do {
                try fileManager.moveItem(at: temporary, to: destination)
            } catch {
                try? fileManager.moveItem(at: aside, to: destination)
                throw error
            }
            try? fileManager.removeItem(at: aside)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }
}
