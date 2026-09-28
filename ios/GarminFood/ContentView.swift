// ContentView.swift
//
// The app shell (app-navigation spec, design D1): one navigation stack per
// tab, so switching away and back keeps its place. The shell owns
// `AppEnvironment`, applies external routes (widget link, barcode Control,
// `plan` link), drives foreground/background work (plus the day rollover at
// midnight while the app stays open), and hosts the celebration overlay
// above every tab.
//
// rebrand-to-jirkas-arc D6: the tab set comes from AppearanceKit's
// `AppShell.tabs(for:)`. Food-first (the default, every install without a
// vault connection): Today ("Food log", `fork.knife`), Progress, Profile --
// exactly the shell before. Training: Today ("Today", `sun.max`), Plan,
// Progress, Profile. Tabs are keyed by id, so a tab present in both sets
// keeps its stack when the experience flips.

import SwiftUI
import UIKit
import Combine
import AppearanceKit

@MainActor
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = AppEnvironment()

    var body: some View {
        @Bindable var router = environment.router

        TabView(selection: $router.selectedTab) {
            ForEach(AppShell.tabs(for: environment.experience), id: \.self) { tab in
                NavigationStack {
                    tabRoot(tab)
                        .withStatusBanners()
                }
                .tabItem { tabLabel(tab) }
                .tag(tab)
            }
        }
        // rebrand-to-jirkas-arc D8: leaving the training experience while
        // Plan is selected lands on Today.
        .onChange(of: environment.experience) { _, experience in
            environment.router.experienceDidChange(to: experience)
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

    @ViewBuilder
    private func tabRoot(_ tab: AppRouter.Tab) -> some View {
        switch tab {
        case .today: TodayView()
        case .plan: PlanTabView()
        case .progress: ProgressHomeView()
        case .profile: ProfileView()
        }
    }

    /// Titles and icons per design D6's table: only Today's icon differs
    /// between the experiences (its title is TodayView's business).
    @ViewBuilder
    private func tabLabel(_ tab: AppRouter.Tab) -> some View {
        switch tab {
        case .today:
            Label("Today", systemImage: environment.experience == .training ? "sun.max" : "fork.knife")
        case .plan:
            Label("Plan", systemImage: "calendar")
        case .progress:
            Label("Progress", systemImage: "flame.fill")
        case .profile:
            Label("Profile", systemImage: "person.crop.circle")
        }
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
