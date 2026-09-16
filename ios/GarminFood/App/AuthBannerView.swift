// AuthBannerView.swift
//
// Wires `GarminAuthState` to actual app UI -- add-garmin-auth-and-sync's own
// task 11.1: "wiring it to actual app UI (banner...) is Phase 2/4's job."
// Per design.md D7, a `.needsSignIn` state must be LOUD (a persistent
// banner), never silently swallowed; `.signedOut` (never bootstrapped yet in
// this process) gets the same visible call-to-action, since the effect --
// no authenticated search, no delivery -- is identical from the user's
// point of view. `.authenticated` renders nothing at all.
//
// The sheet exposes two capture paths: the in-app `WKWebView` sign-in
// (`GarminSSOWebView`, which replaced an `ASWebAuthenticationSession` flow
// once a real device showed that flow could never complete), and the manual
// ticket-paste fallback (task 8.4, the "recovery path when the redirect
// contract changes"). Both stay exposed: capture is CONFIRMED working as of
// 2026-09-16, but the ticket EXCHANGE behind both of them is not, so the
// recovery path still earns its place. Both funnel through
// `GarminSSOEndpoints.ticket(in:)` so they cannot disagree about what a
// ticket looks like.

import SwiftUI
import GarminKit

struct AuthBannerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isPresentingSignIn = false

    var body: some View {
        let authState = environment.authState

        if authState.state != .authenticated {
            Button {
                isPresentingSignIn = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(authState.state == .needsSignIn ? "Garmin sign-in expired" : "Not connected to Garmin")
                            .font(.subheadline.weight(.semibold))
                        Text("Entries still save locally and will sync once you reconnect.")
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
            .sheet(isPresented: $isPresentingSignIn) {
                GarminSignInSheet()
            }
        }
    }
}

@MainActor
private struct GarminSignInSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var pastedTicket = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var isPresentingWebSSO = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isPresentingWebSSO = true
                    } label: {
                        Label("Sign in with Garmin", systemImage: "safari")
                    }
                    .disabled(isWorking)
                } footer: {
                    Text("Opens Garmin's real sign-in page in-app and captures the sign-in automatically once it completes.")
                }

                Section {
                    TextField("Paste service ticket", text: $pastedTicket)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Complete sign-in with pasted ticket") {
                        Task { await completeSignIn(withTicket: pastedTicket) }
                    }
                    .disabled(pastedTicket.isEmpty || isWorking)
                } header: {
                    Text("Manual fallback")
                } footer: {
                    Text("If the sign-in page above doesn't complete automatically, sign in to Garmin Connect in a regular browser instead, then copy the \"ticket\" value from the redirect URL here.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Connect Garmin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $isPresentingWebSSO) {
                GarminSSOWebView(
                    onTicket: { ticket in
                        isPresentingWebSSO = false
                        Task { await completeSignIn(withTicket: ticket) }
                    },
                    onCancel: {
                        isPresentingWebSSO = false
                    },
                    onFailure: { message in
                        isPresentingWebSSO = false
                        errorMessage = message
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    private func completeSignIn(withTicket rawTicket: String) async {
        guard let ticket = GarminSSOEndpoints.ticket(in: rawTicket) else {
            errorMessage = "That field is empty. Paste the redirect URL, or just the ticket value from it."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            // R5: handing the session the auth state is what makes a
            // successful bootstrap update the UI. Calling markAuthenticated()
            // here instead would re-introduce exactly the forget-to-wire-it
            // bug R5 was added to prevent -- and the WebView path routes
            // through this same function.
            let session = GarminAuthSession(authState: environment.authState)
            _ = try await session.completeBootstrap(withPastedTicket: ticket)
            dismiss()
        } catch {
            errorMessage = GarminErrorPresentation.bootstrapErrorMessage(for: error)
        }
    }
}
