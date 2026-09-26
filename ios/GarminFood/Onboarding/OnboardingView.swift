// OnboardingView.swift
//
// First-launch onboarding for a FRESH install (add-standalone-mode D10,
// task 5.1): welcome -> "How do you want to use GarminFood?" -> (standalone
// only) skippable goal setup -> a one-screen "Back up regularly" explainer.
//
// Shown only while `AppEnvironment.needsOnboarding` is true, which the
// launch classification sets only when no mode is stored AND there is no
// Garmin token AND no local history (`DataModeMigration`). The owner's
// phone -- token and history -- is classified Garmin-connected silently and
// never sees this screen.
//
// - "With my Garmin account" stores `.garminConnected` and opens today's
//   `GarminSignInSheet`; closing it without signing in ("not now") keeps
//   Garmin mode with today's signed-out banner (spec "Choosing Garmin but
//   postponing sign-in").
// - "Just on this phone" stores `.standalone`, then offers the goal editor
//   (Skip leaves no target) and the backup explainer.
//
// No Garmin work runs while this is up (`AppEnvironment.currentSyncPlan`).
// Thin: the mode and finish live in AppEnvironment (`chooseDataMode`,
// `finishOnboarding`).
//
// Depends on: AppEnvironment, GarminSignInSheet, LocalGoalEditorView.
// Depended on by: ContentView (full-screen cover).

import SwiftUI
import FoodLogCore

@MainActor
struct OnboardingView: View {
    private enum Step {
        case welcome, choice, goals, backup
    }

    @Environment(AppEnvironment.self) private var environment
    @State private var step: Step = .welcome
    @State private var isPresentingSignIn = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .choice: choice
                case .goals:
                    LocalGoalEditorView(context: .onboarding) {
                        step = .backup
                    }
                case .backup: backup
                }
            }
            .animation(.default, value: step)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $isPresentingSignIn, onDismiss: {
            // Signed in or "not now": Garmin mode either way.
            environment.finishOnboarding()
        }) {
            GarminSignInSheet()
        }
    }

    // MARK: Steps

    private var welcome: some View {
        page(
            symbol: "fork.knife.circle.fill",
            title: String(localized: "Welcome to GarminFood"),
            message: String(localized: "Log what you eat in two taps, keep a streak going and see how your days add up.")
        ) {
            Button(String(localized: "Get started")) {
                step = .choice
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var choice: some View {
        page(
            symbol: "person.crop.circle.badge.questionmark",
            title: String(localized: "How do you want to use GarminFood?"),
            message: String(localized: "You can change this later in Settings.")
        ) {
            Button {
                environment.chooseDataMode(.garminConnected)
                isPresentingSignIn = true
            } label: {
                choiceLabel(
                    title: String(localized: "With my Garmin account"),
                    detail: String(localized: "Your food goes to Garmin Connect, next to your activities.")
                )
            }
            .buttonStyle(.bordered)

            Button {
                environment.chooseDataMode(.standalone)
                step = .goals
            } label: {
                choiceLabel(
                    title: String(localized: "Just on this phone"),
                    detail: String(localized: "No account needed. Everything stays on this phone.")
                )
            }
            .buttonStyle(.bordered)
        }
    }

    private var backup: some View {
        page(
            symbol: "externaldrive.badge.checkmark",
            title: String(localized: "Back up regularly"),
            message: String(localized: "Your food log lives only on this phone. If you delete the app or lose the phone, everything since your last backup is gone. Make a backup from Settings every week or two and keep it in Files or send it to yourself.")
        ) {
            Button(String(localized: "Start logging")) {
                environment.finishOnboarding()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Layout

    private func page<Actions: View>(symbol: String, title: String, message: String, @ViewBuilder actions: () -> Actions) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: symbol)
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                    .padding(.top, Theme.Spacing.xl)
                Text(title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: Theme.Spacing.md) {
                    actions()
                }
                .padding(.top, Theme.Spacing.md)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.groupedBackground)
    }

    private func choiceLabel(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.xs)
    }
}
