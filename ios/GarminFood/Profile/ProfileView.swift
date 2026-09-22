// ProfileView.swift
//
// Who the user is and what they've built up (profile-and-settings spec):
// the Garmin name and photo when available, plus local stats that never
// depend on the network. A failed Garmin profile load never hides the local
// stats -- it just falls back to a neutral placeholder for the name/photo.
//
// The "Fasting" row (2026-09-22) is the one STABLE entry point into
// `FastingView` -- `TodayView`'s own fasting card only renders once a fast
// is already active (it's a glance-while-running surface, not a launcher),
// so starting the very first fast has to be reachable from somewhere that's
// always on screen regardless of state. This list already plays that role
// for `SettingsView`, so it's the natural place for a second one rather
// than adding a fourth tab for a feature this size.

import SwiftUI
import GarminKit

@MainActor
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let engine = environment.gamificationEngine
        let profile = environment.profile

        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                ProfileHeader(profile: profile.profile, failed: profile.profileFailed, isLoading: profile.isLoading)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                    StatTile(value: "\(engine.levelProgress.level)", label: "Level", systemImage: "sparkles")
                    StatTile(value: "\(engine.streakStatus.length)", label: "Current streak", systemImage: "flame.fill", tint: Theme.ember)
                    StatTile(value: "\(engine.streakSummary.longestLength)", label: "Longest streak", systemImage: "trophy.fill")
                    StatTile(value: "\(engine.totalLogCount)", label: "Foods logged", systemImage: "fork.knife")
                    StatTile(value: "\(engine.streakSummary.loggedDayCount)", label: "Days logged", systemImage: "calendar")
                    StatTile(value: "\(engine.completedChallenges.count)", label: "Challenges done", systemImage: "checkmark.seal.fill")
                }

                NavigationLink {
                    FastingView()
                } label: {
                    HStack {
                        Label("Fasting", systemImage: "timer")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .card()
                }
                .buttonStyle(.plain)

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
            await profile.refresh()
        }
    }
}

private struct ProfileHeader: View {
    let profile: SocialProfile?
    let failed: Bool
    let isLoading: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            avatar
            Text(profile?.displayName ?? profile?.fullName ?? "GarminFood")
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
