// VaultSettingsView.swift
//
// Settings -> Vault (add-vault-connection task 4.2, design D10; the
// vault-connection spec). Reached from Settings' Data section on
// Garmin-connected installs only (owner decision A26 / tasks 0.3: hidden on
// standalone installs), and from the loud vault banner.
//
// Top to bottom: the "Connect to my vault" switch (off by default; turning
// it off stops all vault traffic and keeps the settings); the repository
// typed in (owner, name, branch under "Advanced", owner decision 0.5); the
// token (SecureField + PasteButton, saved on "Save token", never shown
// again beyond its last four characters, fine-grained only); "Test
// connection" with its read-only checklist; the status (last sync, last
// problem, expiry countdown, pending writes); Details with the device id;
// Disconnect with a confirmation.
//
// polish-training-today D1: the status shows the first fetch that
// finishing the setup starts ("Fetching your plan…", then its answer).
//
// add-training-checkins 4.9: "Not uploaded" lists the event segments the
// write queue gave up on (from TrainingEventsService), each with Retry;
// the section is absent while there are none.
//
// No repository or token is ever built in: this repository is public
// (proposal "Why"). The help text says how to make a token limited to one
// repository with Contents read/write; docs/vault-connection.md has the
// long form. Everything here goes through `VaultController`; the rules
// live, tested, in VaultKit.

import SwiftUI
import VaultKit
import TrainingCore

@MainActor
struct VaultSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var owner = ""
    @State private var name = ""
    @State private var branch = VaultRepository.defaultBranch
    @State private var tokenDraft = ""
    @State private var repositoryMessage: String?
    @State private var repositorySaved = false
    @State private var tokenMessage: String?
    @State private var tokenSaved = false
    @State private var isConfirmingDisconnect = false
    @State private var showsAdvanced = false
    @State private var showsDetails = false
    @State private var failedWrites: [FailedWrite] = []
    @State private var retryingWrite: UUID?

    /// GitHub's page for creating a fine-grained token.
    private static let newTokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    var body: some View {
        let vault = environment.vault

        Form {
            Section {
                Toggle("Connect to my vault", isOn: Binding(
                    get: { vault.settings.enabled },
                    set: { enabled in Task { await vault.setEnabled(enabled) } }
                ))
            } footer: {
                Text("Reads your training plan from your Obsidian vault's GitHub repository. Nothing is sent to GitHub until you turn this on and save a token.")
            }

            if vault.settings.enabled {
                repositorySection(vault)
                tokenSection(vault)
                testSection(vault)
                statusSection(vault)
                if !failedWrites.isEmpty {
                    failedWritesSection
                }
                detailsSection(vault)
                Section {
                    Button("Disconnect", role: .destructive) {
                        isConfirmingDisconnect = true
                    }
                } footer: {
                    Text("Removes the token from this iPhone, clears the cached plan and turns the connection off. The device id is kept.")
                }
            }
        }
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vault.reload()
            owner = vault.settings.owner
            name = vault.settings.name
            branch = vault.settings.branch
            failedWrites = await TrainingEventsService.shared.failedWrites()
        }
        .confirmationDialog(
            "Disconnect from the vault?",
            isPresented: $isConfirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task {
                    await vault.disconnect()
                    tokenDraft = ""
                }
            }
        } message: {
            Text("The token is removed from this iPhone's Keychain and the cached plan is deleted.")
        }
    }

    // MARK: - Repository

    private func repositorySection(_ vault: VaultController) -> some View {
        Section {
            TextField("Owner", text: $owner)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
            TextField("Repository name", text: $name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                TextField("Branch", text: $branch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Button("Save repository") {
                Task {
                    let problem = await vault.saveRepository(owner: owner, name: name, branch: branch)
                    repositoryMessage = problem.map(VaultErrorPresentation.repositoryProblem)
                    repositorySaved = problem == nil
                    if problem == nil {
                        owner = vault.settings.owner
                        name = vault.settings.name
                        branch = vault.settings.branch
                    }
                }
            }
            .disabled(owner.isEmpty || name.isEmpty)
            if let repositoryMessage {
                Text(repositoryMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            } else if repositorySaved {
                Label("Repository saved.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.success)
            }
        } header: {
            Text("Repository")
        } footer: {
            Text("The GitHub account and repository that hold your vault. They are typed in here only; the app has none built in.")
        }
    }

    // MARK: - Token

    private func tokenSection(_ vault: VaultController) -> some View {
        Section {
            if vault.hasToken {
                LabeledContent("Saved token") {
                    Text("ends in …\(vault.tokenLastFour ?? "")")
                        .monospaced()
                }
                if let savedAt = vault.status.tokenSavedAt {
                    LabeledContent("Saved on") {
                        Text(savedAt, format: .dateTime.day().month().year())
                    }
                }
                Button("Remove token", role: .destructive) {
                    Task { await vault.removeToken() }
                }
            }
            SecureField("Paste a fine-grained token", text: $tokenDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            PasteButton(payloadType: String.self) { strings in
                tokenDraft = strings.first ?? ""
            }
            Button("Save token") {
                let draft = tokenDraft
                Task {
                    let error = await vault.saveToken(draft)
                    tokenMessage = error.map(VaultErrorPresentation.tokenSaveError)
                    tokenSaved = error == nil
                    if error == nil { tokenDraft = "" }
                }
            }
            .disabled(tokenDraft.isEmpty)
            if let tokenMessage {
                Text(tokenMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            } else if tokenSaved {
                Label("Token saved.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.success)
            }
            Link(destination: Self.newTokenURL) {
                Label("Create a token on GitHub", systemImage: "arrow.up.forward.app")
            }
        } header: {
            Text("Token")
        } footer: {
            Text("Create a fine-grained personal access token with access to this one repository only and the Contents permission set to Read and write, expiring in 180 days. It is kept only in this iPhone's Keychain, never in a backup, an export or the diagnostics log.")
        }
    }

    // MARK: - Test connection

    private func testSection(_ vault: VaultController) -> some View {
        Section {
            Button {
                Task { await vault.testConnection() }
            } label: {
                HStack {
                    Label("Test connection", systemImage: "checkmark.shield")
                    Spacer()
                    if vault.isTesting {
                        ProgressView()
                    }
                }
            }
            .disabled(vault.isTesting)
            if let result = vault.lastTest {
                VaultTestChecklist(result: result, expiryDays: vault.connectionState.daysUntilTokenExpiry(now: Date()))
            }
        } header: {
            Text("Check")
        } footer: {
            Text("Only reads from GitHub: checks the token, the repository and the plan file. Nothing is written.")
        }
    }

    // MARK: - Status

    private func statusSection(_ vault: VaultController) -> some View {
        let state = vault.connectionState
        return Section("Status") {
            // polish-training-today D1: the first fetch after the setup.
            if vault.isSyncingPlan {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Fetching your plan…")
                    Spacer()
                    ProgressView()
                }
            } else if case .ran(let fetch)? = vault.lastSetupReport {
                switch fetch {
                case .updated, .unchanged:
                    Label("Plan fetched. Today and Plan show it.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.success)
                case .rejected:
                    Label("The plan file couldn't be read. Today and Plan say why.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                case .failed:
                    EmptyView()
                }
            }
            LabeledContent("Last sync") {
                if let last = vault.status.lastSuccessAt {
                    Text(last, format: .relative(presentation: .named))
                } else {
                    Text("Never")
                }
            }
            if let problem = vault.status.lastProblem {
                LabeledContent("Last problem") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(VaultErrorPresentation.outcome(problem))
                            .multilineTextAlignment(.trailing)
                        if let at = vault.status.lastOutcomeAt {
                            Text(at, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            LabeledContent("Token expiry") {
                Text(VaultErrorPresentation.expiry(days: state.daysUntilTokenExpiry(now: Date())))
            }
            LabeledContent("Pending writes") {
                Text(verbatim: "\(vault.status.pendingWrites ?? 0)")
            }
            if vault.status.blockedBy != nil {
                Button("Try again") {
                    Task { await vault.tryAgain() }
                }
            }
        }
    }

    // MARK: - Failed writes (add-training-checkins 4.9)

    /// Segments the write queue gave up on. They stay on the phone; Retry
    /// makes one pending again and sends it now.
    private var failedWritesSection: some View {
        Section {
            ForEach(failedWrites) { write in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(write.eventCount) events")
                        Text(write.createdAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let reason = write.lastError {
                            Text(verbatim: reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if retryingWrite == write.id {
                        ProgressView()
                    } else {
                        Button("Retry") {
                            retryingWrite = write.id
                            Task {
                                await TrainingEventsService.shared.retryFailedWrite(write.id)
                                failedWrites = await TrainingEventsService.shared.failedWrites()
                                await environment.vault.reload()
                                retryingWrite = nil
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(retryingWrite != nil)
                    }
                }
            }
        } header: {
            Text("Not uploaded")
        } footer: {
            Text("These couldn't be uploaded after several tries. They are still on this iPhone; Retry sends them again.")
        }
    }

    // MARK: - Details

    private func detailsSection(_ vault: VaultController) -> some View {
        Section {
            DisclosureGroup("Details", isExpanded: $showsDetails) {
                LabeledContent("Device id") {
                    if let id = vault.deviceID {
                        Text(verbatim: id.rawValue)
                            .monospaced()
                            .textSelection(.enabled)
                    } else {
                        Text("Created on the first successful test")
                            .foregroundStyle(.secondary)
                    }
                }
                if let id = vault.deviceID {
                    LabeledContent("Events folder") {
                        Text(verbatim: "\(VaultPathPolicy.eventsFolder)/\(id.rawValue)/")
                            .monospaced()
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

/// The "Test connection" checklist (design D10): token accepted,
/// repository reachable, plan file found (or not generated yet), expiry.
private struct VaultTestChecklist: View {
    let result: VaultConnectionTestResult
    let expiryDays: Int?

    private enum Mark {
        case ok, failed, info
    }

    var body: some View {
        if let probe = result.probe {
            switch probe.repository {
            case .success:
                row(.ok, String(localized: "Token accepted"))
                row(.ok, String(localized: "Repository reachable"))
                projectionRow(probe.projection)
                row(.info, VaultErrorPresentation.expiry(days: expiryDays))
            case .authFailed(.repositoryNotFound):
                row(.failed, VaultErrorPresentation.authProblem(.repositoryNotFound))
            default:
                row(.failed, VaultErrorPresentation.outcome(probe.repository))
            }
        } else {
            row(.failed, VaultErrorPresentation.outcome(.notConfigured))
        }
    }

    @ViewBuilder
    private func projectionRow(_ state: VaultProbeResult.FileState?) -> some View {
        switch state {
        case .found(let byteCount)?:
            let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
            row(.ok, String(localized: "Plan file found (\(size))"))
        case .notFound?, nil:
            row(.info, String(localized: "No plan data yet"))
        case .failed(let outcome)?:
            row(.failed, VaultErrorPresentation.outcome(outcome))
        }
    }

    private func row(_ mark: Mark, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            switch mark {
            case .ok:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
            case .failed:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.danger)
            case .info:
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            Text(text)
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }
}
