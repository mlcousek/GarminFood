// OfflineIndexSettingsSection.swift
//
// Settings -> Offline food database (add-offline-czech-food-index task
// 3.5). It shows what's installed: product count, when it was updated and
// its size, or "Not downloaded" (spec "No index yet"). It offers
// "Download now", which skips the daily throttle, and the "Allow on
// cellular" switch (design.md D3). The last update failure appears in the
// footer, so a bad download is visible here as well as in Diagnostics
// (spec "Corrupted download"). It is never a modal: search works without
// the database.
//
// Its own Section view, embedded in SettingsView with one line, like
// GoalsSettingsSection. All state comes from `OfflineIndexLoader`
// (AppEnvironment); no logic lives here.

import SwiftUI
import FoodLogCore

@MainActor
struct OfflineIndexSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = environment.preferences
        let loader = environment.offlineIndexLoader
        let status = loader.status

        Section {
            HStack {
                Label("Czech foods", systemImage: "externaldrive")
                Spacer()
                if loader.isUpdating {
                    ProgressView()
                        .accessibilityLabel("Updating")
                } else {
                    Text(summaryText(status))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            if let installedAt = status.installedAt {
                HStack {
                    Text("Updated")
                    Spacer()
                    Text(installedAt, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if let bytes = status.installedBytes {
                HStack {
                    Text("Size")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            Button {
                Task { await loader.downloadNow() }
            } label: {
                Label(loader.isUpdating ? "Checking…" : "Download now", systemImage: "arrow.down.circle")
            }
            .disabled(loader.isUpdating)

            Toggle("Allow on cellular", isOn: $preferences.offlineIndexAllowsCellular)
        } header: {
            Text("Offline food database")
        } footer: {
            footer(status: status, outcome: loader.lastManualOutcome)
        }
        .task { await loader.refreshStatus() }
    }

    private func summaryText(_ status: OfflineIndexStatus) -> String {
        guard status.isInstalled, let count = status.installedCount else { return "Not downloaded" }
        return "\(count.formatted()) products"
    }

    @ViewBuilder
    private func footer(status: OfflineIndexStatus, outcome: OfflineIndexUpdateOutcome?) -> some View {
        if let error = status.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.warning)
        } else if let message = outcome.flatMap(Self.message(for:)) {
            Text(message)
        } else {
            Text("Search Czech products instantly, even offline. Updates weekly, on Wi-Fi unless cellular is allowed. Data from Open Food Facts (ODbL).")
        }
    }

    private static func message(for outcome: OfflineIndexUpdateOutcome) -> String? {
        switch outcome {
        case .checkedRecently, .alreadyRunning:
            return nil
        case .upToDate:
            return "Already up to date."
        case .installed(let count):
            return "Downloaded \(count.formatted()) products."
        case .waitingForWiFi:
            return "Waiting for Wi-Fi. Turn on “Allow on cellular” to download now."
        case .failed:
            // The store already recorded it; `status.lastError` shows it.
            return nil
        }
    }
}
