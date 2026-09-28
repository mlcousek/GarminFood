// VaultBannerView.swift
//
// The loud vault banner (add-vault-connection task 4.4, design D10; spec
// "Failures that need the user are loud; everything else is quiet"). Placed
// on every tab by `withStatusBanners()`, under the Garmin banners, in the
// same visual pattern as `AuthBannerView`.
//
// Shown only on a Garmin-connected install, only while the connection is
// ENABLED, and only when it needs the user: the token was rejected, access
// is forbidden, the repository can't be found, no token is stored (e.g.
// after a restore on a new phone), or the token expires within 14 days.
// Never for being offline, rate limits, server errors or "no plan data
// yet" -- those stay in Settings -> Vault. Tapping it opens Settings ->
// Vault in a sheet.
//
// Every rule is `VaultConnectionState.bannerReason` (VaultKit, tested);
// this view only draws it.

import SwiftUI
import VaultKit

struct VaultBannerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isPresentingSettings = false

    var body: some View {
        if environment.dataMode == .garminConnected, !environment.needsOnboarding,
           let reason = environment.vault.bannerReason() {
            Button {
                isPresentingSettings = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(VaultErrorPresentation.bannerTitle(reason))
                            .font(.subheadline.weight(.semibold))
                        Text("Your training plan stays as last synced. Tap to fix.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .padding(.horizontal, Theme.Spacing.md)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the vault settings")
            .sheet(isPresented: $isPresentingSettings) {
                NavigationStack {
                    VaultSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { isPresentingSettings = false }
                            }
                        }
                }
            }
        }
    }
}
