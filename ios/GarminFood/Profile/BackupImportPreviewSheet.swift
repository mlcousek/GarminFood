// BackupImportPreviewSheet.swift
//
// add-data-safety D5: what an imported backup file contains, shown BEFORE
// anything changes -- the backup's date and app version, item counts per
// area (food log, custom foods, presets, favourites, weigh-ins, drinks,
// notes), the number of progress/history files, and the promise that the
// current data is saved as a safety backup first. "Restore" stages the
// restore for the next launch (design D4); "Cancel" changes nothing.
//
// The file was already decoded and version-checked by
// `DataSafetyController.readImport`; the counts come from FoodLogCore's
// `BackupPreview` (unit-tested). This view only lays them out.
//
// Depends on: FoodLogCore (BackupPreview, BackupArea), ImportedBackup.
// Depended on by: DataSettingsView.

import SwiftUI
import FoodLogCore

@MainActor
struct BackupImportPreviewSheet: View {
    let imported: ImportedBackup
    let onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var manifest: BackupManifest { imported.container.manifest }
    private var preview: BackupPreview { imported.preview }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    if let appVersion = manifest.appVersion {
                        HStack {
                            Text("App version")
                            Spacer()
                            Text(verbatim: appVersion)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .contain)

                Section {
                    ForEach(BackupPreview.itemAreas, id: \.self) { area in
                        if let count = preview.itemCounts[area] {
                            HStack {
                                Text(Self.title(for: area))
                                Spacer()
                                Text("\(count)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    HStack {
                        Text("Progress and history files")
                        Spacer()
                        Text("\(preview.otherFileCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("In this backup")
                }

                Section {
                    Label {
                        Text("Your current data is replaced the next time you open GarminFood. It's saved as a safety backup first, so you can go back.", comment: "Import preview: what Restore does.")
                    } icon: {
                        Image(systemName: "lifepreserver")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .navigationTitle("Restore backup?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") { onRestore() }
                }
            }
        }
    }

    static func title(for area: BackupArea) -> String {
        switch area {
        case .foodLog: return String(localized: "Food log entries", comment: "Import preview row: logged foods kept on the phone (standalone mode), summed over all months.")
        case .customFoods: return String(localized: "Custom foods")
        case .mealPresets: return String(localized: "Meal presets")
        case .favorites: return String(localized: "Favorites")
        case .weight: return String(localized: "Weigh-ins")
        case .hydration: return String(localized: "Drinks")
        case .dayNotes: return String(localized: "Day notes")
        case .fasting: return String(localized: "Fasts")
        case .supplements: return String(localized: "Supplements")
        case .history, .progress, .deviceOnly, .other: return String(localized: "Other files")
        }
    }
}
