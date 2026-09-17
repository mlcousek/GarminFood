// LogDonations.swift
//
// Siri donations for logged foods (add-glanceable-surfaces 20.2, carried as
// add-app-shell-and-meal-dashboard 9.3). Every log, from any surface,
// donates "Log <food> in GarminFood" so Siri Suggestions and Spotlight learn
// what the user actually eats. Deleting an entry removes the donations made
// for that food on that day, so a mistaken log stops being suggested.
//
// `IntentDonationIdentifier` is Codable (Apple's documentation, checked
// 2026-09-16), and `IntentDonationManager.deleteDonations(matching:
// .donationIdentifiers(_:))` removes exactly those donations, so the
// identifiers are kept on disk, keyed by day and food.

import AppIntents
import Foundation
import FoodLogCore

@MainActor
final class LogDonations: LogObserving {
    private let ledger: DonationLedger

    init(ledger: DonationLedger = DonationLedger()) {
        self.ledger = ledger
    }

    func didLog(food: Food, date: String) async {
        // A custom food's name isn't something Garmin's search can find,
        // so suggesting "log it by name" would only fail.
        guard food.source != .custom else { return }
        var intent = LogNamedFoodIntent()
        intent.foodName = food.name
        guard let identifier = try? await IntentDonationManager.shared.donate(intent: intent) else { return }
        await ledger.add(identifier, date: date, foodId: food.id)
    }

    func entryDeleted(foodId: String, date: String) async {
        let identifiers = await ledger.remove(date: date, foodId: foodId)
        guard !identifiers.isEmpty else { return }
        _ = try? await IntentDonationManager.shared.deleteDonations(matching: .donationIdentifiers(identifiers))
    }
}

/// Donation identifiers by `"<yyyy-MM-dd>|<foodId>"`, kept to the most
/// recent days so the file stays small.
actor DonationLedger {
    static let maxStoredKeys = 300

    private let fileURL: URL
    private var byKey: [String: [IntentDonationIdentifier]] = [:]
    private var loaded = false

    init(fileURL: URL = DonationLedger.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("GarminFood", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("donations.json")
    }

    func add(_ identifier: IntentDonationIdentifier, date: String, foodId: String) {
        loadIfNeeded()
        byKey[Self.key(date: date, foodId: foodId), default: []].append(identifier)
        if byKey.count > Self.maxStoredKeys {
            // Keys start with the date, so sorting them sorts by day.
            for key in byKey.keys.sorted().prefix(byKey.count - Self.maxStoredKeys) {
                byKey.removeValue(forKey: key)
            }
        }
        persist()
    }

    func remove(date: String, foodId: String) -> [IntentDonationIdentifier] {
        loadIfNeeded()
        let removed = byKey.removeValue(forKey: Self.key(date: date, foodId: foodId)) ?? []
        if !removed.isEmpty {
            persist()
        }
        return removed
    }

    private static func key(date: String, foodId: String) -> String {
        "\(date)|\(foodId)"
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        byKey = (try? JSONDecoder().decode([String: [IntentDonationIdentifier]].self, from: data)) ?? [:]
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(byKey) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
