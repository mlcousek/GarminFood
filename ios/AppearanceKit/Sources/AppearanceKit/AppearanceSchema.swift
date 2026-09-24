// AppearanceSchema — the one version constant shared by the persisted
// `AppearanceSettings` (design.md D7) and anything else in this package
// that is written to disk. Its own file so the schema version has a single
// obvious home (and so the task-1.1 package skeleton had a compilable
// source before the real types landed).
//
// Depended on by: AppearanceSettings / AppearanceMigration, LayoutConfig /
// LayoutMigration.

import Foundation

/// Versioning for everything AppearanceKit persists.
public enum AppearanceSchema {
    /// The current `AppearanceSettings` schema version. Bump together with a
    /// new step in `AppearanceMigration`.
    public static let currentVersion: Int = 1

    /// The current `LayoutConfig` schema version (design.md D7, D8). Bump
    /// together with a new step in `LayoutMigration`.
    public static let layoutVersion: Int = 1
}
