// DiagnosticsLogView.swift
//
// Shows `GarminKit.DiagnosticsLog`'s recent entries in-app -- the whole
// reason that store exists (see its own header): no Mac means no
// Console.app, so this screen plus its "Copy all" action are the only way
// to see what actually happened on a real device and hand it off (e.g.
// pasted into a chat) without any other tooling.
//
// Its "..." menu also carries the hidden developer toggle "Force standalone
// mode (testing)" (add-standalone-mode 1.5): until onboarding exists, the
// only way to try standalone mode on a device. It just stores
// `AppPreferences.forceStandaloneMode`; wave 1 reads it nowhere.

import SwiftUI
import UIKit
import GarminKit

@MainActor
struct DiagnosticsLogView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [DiagnosticsEntry] = []
    @State private var isConfirmingClear = false
    @State private var didCopy = false

    var body: some View {
        @Bindable var preferences = environment.preferences
        List {
            if entries.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: String(localized: "Nothing logged"),
                    message: String(localized: "Errors and warnings from Garmin sync and logging actions will show up here.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            levelBadge(entry.level)
                            Text(entry.category)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Text(entry.message)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        copyAll()
                    } label: {
                        Label(didCopy ? String(localized: "Copied!") : String(localized: "Copy all"), systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label("Clear log", systemImage: "trash")
                    }
                    Divider()
                    Toggle("Force standalone mode (testing)", isOn: $preferences.forceStandaloneMode)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Clear the diagnostics log?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                Task {
                    await DiagnosticsLog.shared.clear()
                    entries = []
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        entries = await DiagnosticsLog.shared.all()
    }

    private func copyAll() {
        let text = entries.map { entry in
            "\(entry.timestamp.formatted(.iso8601)) [\(entry.level.rawValue.uppercased())] \(entry.category): \(entry.message)"
        }.joined(separator: "\n")
        UIPasteboard.general.string = text
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopy = false
        }
    }

    @ViewBuilder
    private func levelBadge(_ level: DiagnosticsLevel) -> some View {
        let (text, color): (String, Color) = switch level {
        case .info: ("INFO", .secondary)
        case .warning: ("WARN", Theme.warning)
        case .error: ("ERROR", Theme.over)
        }
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
