// PlanTabView.swift
//
// The Plan tab, shown only in the training experience (rebrand-to-jirkas-arc
// design.md D6, D9; `AppShell.tabs(for: .training)`). This change builds
// only its empty state: "Your plan shows here once a vault is connected".
// It is the same screen a connected install shows before its first plan
// arrives, so it is not throwaway work; add-training-today-and-plan fills
// the tab with the Week / Month views (and later Season, D7) and consumes
// `AppRouter.pendingPlanDate` from a `garminfood://plan?date=` link.
//
// Built from the design system only (`EmptyStateView` in a card over the
// gradient header background, as Today and Trends do), so it follows the
// theme and passes the design-token lint with no allowlist entry.
//
// Depended on by: ContentView (the Plan tab's root).

import SwiftUI

@MainActor
struct PlanTabView: View {
    var body: some View {
        ScrollView {
            EmptyStateView(
                systemImage: "calendar.badge.clock",
                title: "Your plan shows here once a vault is connected",
                message: "Jirka's Arc reads your training plan from your vault. Until then, log food on Today as always."
            )
            .card()
            .padding(Theme.Spacing.md)
        }
        .background { GradientHeaderBackground() }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PlanTabView()
    }
}
