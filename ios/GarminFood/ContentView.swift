// ContentView.swift
//
// The app's real root screen (add-food-log-core, tasks 12-16) -- replaces
// the earlier hello-world/Keychain-spike-adjacent placeholder (task 6.1).
// Hosts the food catalog as the primary screen, a loud auth banner
// (add-garmin-auth-and-sync task 11.1) above it, and triggers a best-effort
// outbox drain on foreground (task 9.5's foreground half -- see
// AppEnvironment.refreshOnForeground()'s doc comment for what's
// deliberately NOT done yet, i.e. BGAppRefreshTask registration).
//
// The Keychain-sharing spike itself (ios/Shared/KeychainSpike.swift,
// GarminFoodWidget/KeychainCheckWidget.swift) is untouched and still exists
// as its own files -- this view simply no longer triggers it, since its
// finding is already settled and recorded (openspec/config.yaml's Hard
// Constraints: confirmed 2026-09-14, `errSecMissingEntitlement`).

import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = AppEnvironment()

    var body: some View {
        NavigationStack {
            FoodCatalogView()
                .safeAreaInset(edge: .top) {
                    AuthBannerView()
                        .padding(.top, Theme.Spacing.xs)
                }
        }
        .environment(environment)
        .task {
            await environment.refreshOnForeground()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await environment.refreshOnForeground() }
        }
    }
}

#Preview {
    ContentView()
}
