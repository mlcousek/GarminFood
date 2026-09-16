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

import Foundation
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
        isWorking = true
        defer { isWorking = false }
        do {
            let session = GarminAuthSession()
            _ = try await session.completeBootstrap(withPastedTicket: Self.normalizedTicket(rawTicket))
            environment.authState.markAuthenticated()
            dismiss()
        } catch {
            errorMessage = GarminErrorPresentation.bootstrapErrorMessage(for: error)
        }
    }

    /// The footer above tells the user to copy a value "from the redirect
    /// URL", so some will reasonably paste the whole URL, and a hand-copied
    /// value picks up stray whitespace either way. Accept both shapes rather
    /// than failing the exchange and then blaming the paste.
    private static func normalizedTicket(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("ticket=") else { return trimmed }
        return URLComponents(string: trimmed)?
            .queryItems?
            .first(where: { $0.name == "ticket" })?
            .value ?? trimmed
    }
}
