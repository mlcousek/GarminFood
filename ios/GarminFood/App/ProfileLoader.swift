// ProfileLoader.swift
//
// The Garmin data the Profile and Settings screens show (design D8): the
// social profile and the nutrition plan. Both are optional extras; a
// failure leaves the last good value (or nothing) and the screens still
// show everything local.

import Foundation
import Observation
import GarminKit
import FoodLogCore

@MainActor
@Observable
final class ProfileLoader {
    @ObservationIgnored private let client: GarminClient

    private(set) var profile: SocialProfile?
    private(set) var settings: NutritionSettings?
    private(set) var profileFailed = false
    private(set) var settingsFailed = false
    private(set) var isLoading = false

    init(client: GarminClient) {
        self.client = client
    }

    func refresh(now: Date = Date()) async {
        isLoading = true
        defer { isLoading = false }

        async let profileResult = loadProfile()
        async let settingsResult = loadSettings(date: NutritionDate.string(from: now))
        let (loadedProfile, loadedSettings) = await (profileResult, settingsResult)

        if let loadedProfile {
            profile = loadedProfile
            profileFailed = false
        } else {
            profileFailed = true
        }
        if let loadedSettings {
            settings = loadedSettings
            settingsFailed = false
        } else {
            settingsFailed = true
        }
    }

    func clear() {
        profile = nil
        settings = nil
    }

    private func loadProfile() async -> SocialProfile? {
        try? await client.socialProfile()
    }

    private func loadSettings(date: String) async -> NutritionSettings? {
        try? await client.nutritionSettings(date: date)
    }
}
