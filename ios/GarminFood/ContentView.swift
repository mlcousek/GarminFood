// ContentView.swift
//
// The app shell (app-navigation spec, design D1): three tabs, each with its
// own navigation stack so switching away and back keeps its place. The shell
// owns `AppEnvironment`, applies external routes (widget link, barcode
// Control), drives foreground/background work, and hosts the celebration
// overlay above every tab.

import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = AppEnvironment()

    var body: some View {
        @Bindable var router = environment.router

        TabView(selection: $router.selectedTab) {
            NavigationStack {
                TodayView()
                    .withStatusBanners()
            }
            .tabItem { Label("Today", systemImage: "fork.knife") }
            .tag(AppRouter.Tab.today)

            NavigationStack {
                ProgressHomeView()
                    .withStatusBanners()
            }
            .tabItem { Label("Progress", systemImage: "flame.fill") }
            .tag(AppRouter.Tab.progress)

            NavigationStack {
                ProfileView()
                    .withStatusBanners()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            .tag(AppRouter.Tab.profile)
        }
        .tint(Theme.accent)
        .overlay { MomentOverlay() }
        .onOpenURL { url in
            environment.router.handle(url: url)
        }
        .task {
            environment.router.applyPendingRoute()
            await environment.refreshOnForeground()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                environment.router.applyPendingRoute()
                Task { await environment.refreshOnForeground() }
            case .background:
                environment.didEnterBackground()
            default:
                break
            }
        }
        .onChange(of: AppNavigationBridge.shared.pendingRoute) { _, _ in
            environment.router.applyPendingRoute()
        }
        // Outermost, so the overlay and every presented screen get it too.
        .environment(environment)
    }
}

extension View {
    /// The sign-in and delivery banners, kept visible on every tab
    /// (app-navigation 5.3).
    func withStatusBanners() -> some View {
        safeAreaInset(edge: .top) {
            VStack(spacing: Theme.Spacing.xs) {
                AuthBannerView()
                DeliveryBannerView()
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }
}

#Preview {
    ContentView()
}
