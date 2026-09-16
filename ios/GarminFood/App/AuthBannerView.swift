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
// The actual sign-in mechanism (`GarminAuthSession`, GarminKit) has two
// paths: the `ASWebAuthenticationSession` flow (task 8.1, whose exact
// redirect/ticket contract is explicitly UNCONFIRMED per that file's own
// header) and a manual ticket-paste fallback (task 8.4, the "recovery path
// when the redirect contract changes"). Both are exposed here rather than
// only the happier-looking one, because the redirect flow may simply not
// work yet -- this phase did not (and could not, without a device) verify
// it.

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
    private let presentationProvider = GarminAuthPresentationProvider()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        Task { await signInWithBrowser() }
                    } label: {
                        Label("Sign in with Garmin", systemImage: "safari")
                    }
                    .disabled(isWorking)
                } footer: {
                    Text("Opens Garmin's sign-in page. The redirect back to this app is unconfirmed on this account (design.md task 8.2) -- if it doesn't return here automatically, use the manual option below instead.")
                }

                Section {
                    TextField("Paste service ticket", text: $pastedTicket)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Complete sign-in with pasted ticket") {
                        Task { await signInWithPastedTicket() }
                    }
                    .disabled(pastedTicket.isEmpty || isWorking)
                } header: {
                    Text("Manual fallback")
                } footer: {
                    Text("Sign in to Garmin Connect in a regular browser, then copy the \"ticket\" value from the redirect URL here.")
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
        }
    }

    private func signInWithBrowser() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = GarminAuthSession()
            _ = try await session.signIn(presentationContextProvider: presentationProvider)
            environment.authState.markAuthenticated()
            dismiss()
        } catch {
            errorMessage = "Sign-in didn't complete. Try the manual ticket option below."
        }
    }

    private func signInWithPastedTicket() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = GarminAuthSession()
            _ = try await session.completeBootstrap(withPastedTicket: pastedTicket)
            environment.authState.markAuthenticated()
            dismiss()
        } catch {
            errorMessage = "That ticket didn't work. Double check it was copied in full."
        }
    }
}
