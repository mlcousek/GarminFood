// DataSafetyLaunch.swift
//
// add-data-safety D3/D4: the two pieces of the backup machinery that run
// outside the Data screen.
//
// 1. `applyPendingRestoreIfNeeded()` -- step 2 of the staged restore. It
//    MUST run from `GarminFoodApp.init`, before `ContentView` creates
//    `AppEnvironment` and so before `AppServices.shared` loads any store:
//    every store is loaded once per process and saved from memory, so files
//    replaced under a loaded store would be overwritten by its next save
//    (the bug class `AppServices` exists to prevent). Synchronous, file
//    operations only, no network. With nothing staged it is one
//    `fileExists` check.
// 2. `snapshotIfDue()` -- the once-a-day automatic snapshot, started when a
//    scene becomes active, detached at background priority and never
//    awaited by anything the user sees.
//
// Both, and every Data-screen operation (`DataSafetyController`), go
// through `DataSafetyQueue`, an actor that runs one `BackupVault`
// operation at a time. All the logic is in FoodLogCore's `Backup/` (unit
// tested there); this file only binds it to UserDefaults, the bundle
// version and DiagnosticsLog.
//
// Depends on: FoodLogCore (BackupVault, PreferencesBackup), GarminKit
// (DiagnosticsLog -- infrastructure, not domain).
// Depended on by: GarminFoodApp (init), ContentView (scene phase),
// DataSafetyController.

import Foundation
import FoodLogCore
import GarminKit

enum DataSafetyLaunch {
    static let diagnosticsCategory = "DataSafety"

    /// Applies a restore staged from Settings → Data, if there is one, and
    /// then the backup's preferences. Failures are logged and recorded in
    /// `Backups/status.json`, which the Data screen shows; the app always
    /// goes on to launch normally.
    static func applyPendingRestoreIfNeeded() {
        let vault = BackupVault.applicationSupport()
        let defaults = UserDefaults.standard
        let currentDomain = DataSafetyPreferences.currentDomain()
        do {
            guard let applied = try vault.applyPendingRestore(
                currentPreferences: PreferencesBackup.capture(domain: currentDomain),
                appVersion: DataSafetyPreferences.appVersion,
                now: Date()
            ) else { return }
            if let backupPreferences = applied.preferences, let domainName = DataSafetyPreferences.domainName {
                defaults.setPersistentDomain(
                    PreferencesBackup.restoredDomain(current: currentDomain, backup: backupPreferences),
                    forName: domainName
                )
            }
            DiagnosticsLog.log(
                .info,
                category: diagnosticsCategory,
                "Restored the backup from \(applied.manifest.createdAt) (\(applied.manifest.files.count) files); safety snapshot \(applied.safetySnapshotId)."
            )
        } catch {
            DiagnosticsLog.log(.error, category: diagnosticsCategory, "Restore failed: \(describe(error))")
        }
    }

    /// The once-a-day automatic snapshot (design D3). Fire and forget.
    static func snapshotIfDue() {
        Task.detached(priority: .background) {
            await DataSafetyQueue.shared.snapshotIfDue()
        }
    }

    static func describe(_ error: Error) -> String {
        (error as? BackupError)?.diagnosticDescription ?? error.localizedDescription
    }
}

/// The app's UserDefaults domain as a backup sees it.
enum DataSafetyPreferences {
    static var domainName: String? { Bundle.main.bundleIdentifier }

    /// The persistent domain `UserDefaults.standard` writes to.
    static func currentDomain() -> [String: Any] {
        guard let domainName else { return [:] }
        return UserDefaults.standard.persistentDomain(forName: domainName) ?? [:]
    }

    /// The preferences a backup carries right now.
    static func capture() -> [String: PreferenceValue] {
        PreferencesBackup.capture(domain: currentDomain())
    }

    /// `CFBundleShortVersionString (CFBundleVersion)`, as in Settings → About.
    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Runs one backup operation at a time, off the main thread (design D3:
/// `BackupVault` isn't safe to run concurrently with itself).
actor DataSafetyQueue {
    static let shared = DataSafetyQueue()

    private let vault = BackupVault.applicationSupport()

    /// Runs `body` with exclusive use of the vault.
    func perform<T: Sendable>(_ body: @Sendable (BackupVault) throws -> T) rethrows -> T {
        try body(vault)
    }

    func snapshotIfDue() {
        do {
            let result = try vault.writeAutomaticSnapshotIfDue(
                preferences: DataSafetyPreferences.capture(),
                appVersion: DataSafetyPreferences.appVersion,
                now: Date()
            )
            if let result, !result.skippedPaths.isEmpty {
                DiagnosticsLog.log(.warning, category: DataSafetyLaunch.diagnosticsCategory, "Left out of the snapshot because they look like credentials: \(result.skippedPaths.joined(separator: ", "))")
            }
        } catch {
            DiagnosticsLog.log(.error, category: DataSafetyLaunch.diagnosticsCategory, "Automatic backup failed: \(DataSafetyLaunch.describe(error))")
        }
    }
}
