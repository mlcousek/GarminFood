// ProfileView.swift
//
// Who the user is and what they've built up (profile-and-settings spec):
// the Garmin name and photo when available, plus local stats that never
// depend on the network. A failed Garmin profile load never hides the local
// stats -- it just falls back to a neutral placeholder for the name/photo.
//
// (The "Fasting" row that used to live here was removed by
// redesign-fasting-schedule: fasting is now a daily window set in Settings,
// and its detail screen is reached from the always-on home card.)
//
// add-standalone-mode 5.2: in standalone mode there is no Garmin profile;
// the header shows the user's own display name (`AppPreferences.
// localDisplayName`), editable from a button under it, and nothing is read
// from Garmin (no pull-to-refresh).

import SwiftUI
import GarminKit

@MainActor
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isEditingName = false
    @State private var nameText = ""

    var body: some View {
        let engine = environment.gamificationEngine
        let profile = environment.profile
        let isStandalone = environment.dataMode == .standalone

        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                if isStandalone {
                    ProfileHeader(profile: nil, failed: false, isLoading: false, localName: environment.preferences.localDisplayName)
                    Button {
                        nameText = environment.preferences.localDisplayName ?? ""
                        isEditingName = true
                    } label: {
                        Label(environment.preferences.localDisplayName == nil ? String(localized: "Add your name") : String(localized: "Change name"), systemImage: "pencil")
                            .font(.subheadline)
                    }
                } else {
                    ProfileHeader(profile: profile.profile, failed: profile.profileFailed, isLoading: profile.isLoading)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                    StatTile(value: "\(engine.levelProgress.level)", label: String(localized: "Level"), systemImage: "sparkles")
                    StatTile(value: "\(engine.streakStatus.length)", label: String(localized: "Current streak"), systemImage: "flame.fill", tint: Theme.ember)
                    StatTile(value: "\(engine.streakSummary.longestLength)", label: String(localized: "Longest streak"), systemImage: "trophy.fill")
                    StatTile(value: "\(engine.totalLogCount)", label: String(localized: "Foods logged"), systemImage: "fork.knife")
                    StatTile(value: "\(engine.streakSummary.loggedDayCount)", label: String(localized: "Days logged"), systemImage: "calendar")
                    StatTile(value: "\(engine.completedChallenges.count)", label: String(localized: "Challenges done"), systemImage: "checkmark.seal.fill")
                }

                NavigationLink {
                    SettingsView()
                } label: {
                    HStack {
                        Label("Settings", systemImage: "gearshape.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .card()
                }
                .buttonStyle(.plain)

                AppSignatureView()
                    .padding(.top, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Profile")
        .refreshable {
            guard !isStandalone else { return }
            await profile.refresh()
        }
        .alert(String(localized: "Your name"), isPresented: $isEditingName) {
            TextField(String(localized: "Your display name"), text: $nameText)
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Save")) {
                environment.preferences.localDisplayName = nameText
            }
        } message: {
            Text("Shown on your profile. Stays on this phone.")
        }
    }
}

private struct ProfileHeader: View {
    let profile: SocialProfile?
    let failed: Bool
    let isLoading: Bool
    /// Standalone mode's own display name (`nil` = none set).
    var localName: String? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            avatar
            Text(headerName)
                .font(.title2.weight(.bold))
            if let location = profile?.location, !location.isEmpty {
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if failed {
                Label("Couldn't load from Garmin", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
    }

    /// `fullName` first (fix-testing-feedback-quick-wins): on the owner's
    /// account `socialProfile.displayName` is a UUID (live-probed
    /// 2026-09-23), so preferring it showed an opaque id instead of a name.
    /// An empty string counts as missing, so it falls through too.
    private var headerName: String {
        if let localName, !localName.isEmpty {
            return localName
        }
        if let fullName = profile?.fullName, !fullName.trimmingCharacters(in: .whitespaces).isEmpty {
            return fullName
        }
        if let displayName = profile?.displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            return displayName
        }
        return "GarminFood"
    }

    @ViewBuilder
    private var avatar: some View {
        let size: CGFloat = 96
        Group {
            if let urlString = profile?.profileImageUrlMedium, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if isLoading { ProgressView().tint(.white) }
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(Theme.accent.opacity(0.15))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.accent)
            }
    }
}
