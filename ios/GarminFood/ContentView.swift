// ContentView.swift
//
// The app shell (app-navigation spec, design D1): three tabs, each with its
// own navigation stack so switching away and back keeps its place. The shell
// owns `AppEnvironment`, applies external routes (widget link, barcode
// Control), drives foreground/background work (plus the day rollover at
// midnight while the app stays open), and hosts the celebration overlay
// above every tab.

import SwiftUI
import UIKit
import Combine

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
        // add-themes-and-layout R4: tint, forced scheme and accessibility
        // inputs for the theme (replaces `.tint(Theme.accent)`).
        .themed(environment.themeStore)
        .overlay { MomentOverlay() }
        // add-standalone-mode 5.1: a fresh install chooses Garmin or
        // "just on this phone" first. Never shown on an existing install.
        .fullScreenCover(isPresented: Binding(
            get: { environment.needsOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
                .themed(environment.themeStore)
                .environment(environment)
        }
        // A shared theme's link (AppRouter.handle(url:)): preview first,
        // Apply or Cancel -- never applied silently (design D11).
        .sheet(item: $router.pendingThemeImport) { request in
            ThemeImportPreviewSheet(code: request.code)
        }
        .onOpenURL { url in
            environment.router.handle(url: url)
        }
        .task {
            AppIconSwitcher.resetRemovedAlternateIfNeeded()
            environment.router.applyPendingRoute()
            DataSafetyLaunch.snapshotIfDue() // add-data-safety D3, detached
            await environment.refreshOnForeground()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                environment.router.applyPendingRoute()
                DataSafetyLaunch.snapshotIfDue() // add-data-safety D3, detached
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
        // The day changing while the app is open: `.NSCalendarDayChanged`
        // at midnight, `significantTimeChangeNotification` also for a
        // clock or time-zone change. Either may fire for the same event;
        // `dayDidChange()` is idempotent. Delivered on the main queue since
        // the calendar notification makes no thread promise.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)) { _ in
            handleDayChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification).receive(on: DispatchQueue.main)) { _ in
            handleDayChange()
        }
        // Outermost, so the overlay and every presented screen get it too.
        .environment(environment)
    }

    /// Only while active: in the background nothing is on screen, and the
    /// next `.active` runs `refreshOnForeground()`, which rolls over too.
    private func handleDayChange() {
        guard scenePhase == .active else { return }
        Task { await environment.dayDidChange() }
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
