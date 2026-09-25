// LocalFoodLog.swift
//
// The local system of record for standalone mode (add-standalone-mode D2):
// every food entry a standalone install logs, kept on this phone only, for
// good. In Garmin-connected mode nothing reads or writes it -- Garmin is the
// system of record there and the outbox is the only local food state.
//
// Why a separate store and not "the outbox with a fake delivery": a local
// commit IS the durable write, so there is nothing pending, sent or
// reconciled, and zero-network-wait holds structurally (design D3's rejected
// alternative explains the rest).
//
// Shape decisions:
//   - One JSON file per calendar month (`FoodLog/2026-09.json`), so a
//     commit rewrites one small file instead of a whole-history file that
//     grows forever (a heavy logger writes ~3 MB a year).
//   - Every file goes through `FoodLogCoreStorage.loadPersistedJSON`: a
//     month that no longer decodes is quarantined (moved aside), never
//     silently wiped; a month that exists but can't be READ yet (before
//     first unlock) is not latched as loaded, reads throw, and saves are
//     refused by `ensureSafeToWrite` (fix-silent-store-wipe,
//     fix/store-unreadable-latch). Every mutation loads its month first, so
//     a save on a fresh actor never trips the "never loaded" guard.
//   - Writes are atomic (`.atomic`), one file per call; the in-memory copy
//     changes only after the write succeeded.
//   - Nutrients are a SNAPSHOT of the logged amount (serving x quantity)
//     taken at confirm time, keyed by `NutrientKind.rawValue` strings rather
//     than the enum itself: a nutrient kind added by a later build must not
//     make an older build's decode fail (and quarantine a month). Same for
//     every field that isn't identity: optional, so older/newer files decode.
//
// Depended on by: LocalLogEntryCoordinator (writes), LocalNutritionReader
// (reads, as Garmin-shaped DTOs), AppServices (the one instance per
// process). Tests: LocalFoodLogStoreTests.

import Foundation
import GarminKit

// MARK: - Entry

/// The food a local entry was logged from, as it was at confirm time.
public struct LocalFoodRef: Codable, Sendable, Equatable, Hashable {
    /// `Food.id` -- or, for a custom food, `CustomFoodDraft.id.uuidString`
    /// (the same id usage history records it under, so "Log again" and
    /// quick picks resolve it identically in both modes).
    public let id: String
    /// `nil` when the stored raw value is unknown to this build.
    public let source: FoodSource?
    public let name: String
    public let brandName: String?
    public let barcode: String?
    public let regionCode: String?
    public let languageCode: String?

    public init(
        id: String,
        source: FoodSource?,
        name: String,
        brandName: String? = nil,
        barcode: String? = nil,
        regionCode: String? = nil,
        languageCode: String? = nil
    ) {
        self.id = id
        self.source = source
        self.name = name
        self.brandName = brandName
        self.barcode = barcode
        self.regionCode = regionCode
        self.languageCode = languageCode
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, name, brandName, barcode, regionCode, languageCode
    }

    /// Lenient on `source`: an unknown raw value (a source added by a later
    /// build) decodes as `nil` instead of failing the whole month file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = (try container.decodeIfPresent(String.self, forKey: .source)).flatMap(FoodSource.init(rawValue:))
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        brandName = try container.decodeIfPresent(String.self, forKey: .brandName)
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode)
        regionCode = try container.decodeIfPresent(String.self, forKey: .regionCode)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(source?.rawValue, forKey: .source)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(brandName, forKey: .brandName)
        try container.encodeIfPresent(barcode, forKey: .barcode)
        try container.encodeIfPresent(regionCode, forKey: .regionCode)
        try container.encodeIfPresent(languageCode, forKey: .languageCode)
    }
}

/// One food logged in standalone mode (design D2).
public struct LocalLogEntry: Codable, Sendable, Equatable, Identifiable {
    /// Also the `logId` the dashboard shows it under
    /// (`MealEntry.Status.synced(logId: id.uuidString)`).
    public let id: UUID
    /// The nutrition day, `yyyy-MM-dd` (`NutritionDate.string`) -- the same
    /// day string Garmin mode logs under.
    public let day: String
    public var mealType: MealType
    public let loggedAt: Date
    public let food: LocalFoodRef
    public let servingId: String
    /// `Serving.unit` / `Serving.numberOfUnits` / `Serving.displayLabel` of
    /// the serving logged ("g" / 100 / "100 g").
    public let servingUnit: String?
    public let servingNumberOfUnits: Double?
    public let servingLabel: String?
    /// How many servings, validated by `LogQuantity.isValid` before commit.
    public var quantity: Double
    /// For the LOGGED amount (serving x quantity), keyed by
    /// `NutrientKind.rawValue`. Absent key = the food didn't say.
    public var nutrients: [String: Double]
    public let customFoodId: UUID?
    public let presetId: UUID?
    public var editedAt: Date?

    public init(
        id: UUID = UUID(),
        day: String,
        mealType: MealType,
        loggedAt: Date,
        food: LocalFoodRef,
        servingId: String,
        servingUnit: String? = nil,
        servingNumberOfUnits: Double? = nil,
        servingLabel: String? = nil,
        quantity: Double,
        nutrients: [String: Double],
        customFoodId: UUID? = nil,
        presetId: UUID? = nil,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.day = day
        self.mealType = mealType
        self.loggedAt = loggedAt
        self.food = food
        self.servingId = servingId
        self.servingUnit = servingUnit
        self.servingNumberOfUnits = servingNumberOfUnits
        self.servingLabel = servingLabel
        self.quantity = quantity
        self.nutrients = nutrients
        self.customFoodId = customFoodId
        self.presetId = presetId
        self.editedAt = editedAt
    }

    /// An entry for `quantity` of `serving`, its nutrients snapshotted now.
    public init(
        id: UUID = UUID(),
        day: String,
        mealType: MealType,
        loggedAt: Date,
        food: LocalFoodRef,
        serving: Serving,
        quantity: Double,
        customFoodId: UUID? = nil,
        presetId: UUID? = nil
    ) {
        self.init(
            id: id,
            day: day,
            mealType: mealType,
            loggedAt: loggedAt,
            food: food,
            servingId: serving.id,
            servingUnit: serving.unit,
            servingNumberOfUnits: serving.numberOfUnits,
            servingLabel: serving.displayLabel,
            quantity: quantity,
            nutrients: Self.nutrients(of: serving, quantity: quantity),
            customFoodId: customFoodId,
            presetId: presetId
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, day, mealType, loggedAt, food, servingId, servingUnit, servingNumberOfUnits
        case servingLabel, quantity, nutrients, customFoodId, presetId, editedAt
    }

    /// Only identity is required (id, day, meal, time, food, serving,
    /// quantity); everything else decodes as absent when missing, so a file
    /// written by an older or newer build still reads. Unknown keys are
    /// ignored. Encoding is synthesized from the same `CodingKeys`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        day = try container.decode(String.self, forKey: .day)
        mealType = try container.decode(MealType.self, forKey: .mealType)
        loggedAt = try container.decode(Date.self, forKey: .loggedAt)
        food = try container.decode(LocalFoodRef.self, forKey: .food)
        servingId = try container.decode(String.self, forKey: .servingId)
        servingUnit = try container.decodeIfPresent(String.self, forKey: .servingUnit)
        servingNumberOfUnits = try container.decodeIfPresent(Double.self, forKey: .servingNumberOfUnits)
        servingLabel = try container.decodeIfPresent(String.self, forKey: .servingLabel)
        quantity = try container.decode(Double.self, forKey: .quantity)
        nutrients = try container.decodeIfPresent([String: Double].self, forKey: .nutrients) ?? [:]
        customFoodId = try container.decodeIfPresent(UUID.self, forKey: .customFoodId)
        presetId = try container.decodeIfPresent(UUID.self, forKey: .presetId)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
    }

    /// Every nutrient `serving` carries, times `quantity`.
    public static func nutrients(of serving: Serving, quantity: Double) -> [String: Double] {
        var result: [String: Double] = [:]
        for amount in serving.detailedNutrients {
            result[amount.kind.rawValue] = amount.value * quantity
        }
        return result
    }

    /// The logged amount of `kind`, or `nil` when the food didn't say.
    public func amount(_ kind: NutrientKind) -> Double? {
        nutrients[kind.rawValue]
    }

    /// The nutrients rescaled to `newQuantity` servings (an edit, design
    /// D4). `nil` if this entry's own quantity can't be divided by.
    public func nutrients(rescaledTo newQuantity: Double) -> [String: Double]? {
        guard quantity.isFinite, quantity > 0 else { return nil }
        let ratio = newQuantity / quantity
        return nutrients.mapValues { $0 * ratio }
    }
}

// MARK: - Errors

/// Why a local food-log read or write was refused. Nothing was changed.
public enum LocalFoodLogError: Error, Sendable, Equatable, LocalizedError {
    /// The day isn't a `yyyy-MM-dd` string.
    case invalidDay(String)
    /// No entry with that id on that day.
    case entryNotFound
    /// Writing the month file failed; the detail is the system's own words.
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDay:
            return String(localized: "This day can't be saved in the food log on this phone.", bundle: .module, comment: "Error when a food entry has an invalid date (standalone mode, food log kept on the phone).")
        case .entryNotFound:
            return String(localized: "This entry changed in the meantime. Pull to refresh and try again.", bundle: .module, comment: "Error shown when editing a logged food entry fails.")
        case .saveFailed(let detail):
            return String(localized: "Couldn't save the food log on this phone: \(detail)", bundle: .module, comment: "Error when writing the on-phone food log fails (standalone mode). %@ is the system's reason.")
        }
    }
}

// MARK: - Store

/// Month-sharded, JSON-file-backed, actor-isolated (design D2).
public actor LocalFoodLogStore {
    private let directoryURL: URL
    /// Entries per month (`yyyy-MM`), in commit order, for every month read
    /// so far this process (including one that couldn't be read: empty).
    private var shards: [String: [LocalLogEntry]] = [:]
    /// Months whose file was read (or found missing / quarantined). A month
    /// that exists but couldn't be read stays out, so it is retried.
    private var loadedMonths: Set<String> = []

    public init(directoryURL: URL = LocalFoodLogStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    public static func defaultDirectoryURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("FoodLog", isDirectory: true)
    }

    // MARK: Reads

    /// The day's entries in commit order. Throws when its month's file
    /// exists but can't be read yet -- an honest "couldn't load", never an
    /// empty day that isn't.
    public func entries(forDay day: String) throws -> [LocalLogEntry] {
        let month = try Self.month(ofDay: day)
        return try readableShard(month).filter { $0.day == day }
    }

    /// Every entry on days `startDay...endDay` (inclusive), oldest day
    /// first, commit order within a day.
    public func entries(fromDay startDay: String, toDay endDay: String) throws -> [LocalLogEntry] {
        let first = try Self.month(ofDay: startDay)
        let last = try Self.month(ofDay: endDay)
        guard first <= last else { return [] }
        var result: [LocalLogEntry] = []
        for month in Self.months(from: first, to: last) {
            result.append(contentsOf: try readableShard(month).filter { $0.day >= startDay && $0.day <= endDay })
        }
        // Stable: entries of one day keep their commit order.
        return result.enumerated()
            .sorted { lhs, rhs in
                lhs.element.day != rhs.element.day ? lhs.element.day < rhs.element.day : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    public func entry(id: UUID, day: String) throws -> LocalLogEntry? {
        let month = try Self.month(ofDay: day)
        return try readableShard(month).first { $0.id == id && $0.day == day }
    }

    /// Looks `id` up without knowing its day ("Copy from…" hands over only
    /// the source row's id): months already in memory first, then every
    /// month file on disk, newest first. `nil` if it's nowhere.
    public func entry(id: UUID) -> LocalLogEntry? {
        for month in shards.keys.sorted(by: >) {
            if let found = shards[month]?.first(where: { $0.id == id }) { return found }
        }
        for month in monthsOnDisk().sorted(by: >) where shards[month] == nil {
            loadIfNeeded(month)
            if let found = shards[month]?.first(where: { $0.id == id }) { return found }
        }
        return nil
    }

    // MARK: Writes

    /// Appends `newEntries`, one atomic write per month touched.
    public func append(_ newEntries: [LocalLogEntry]) throws {
        guard !newEntries.isEmpty else { return }
        var byMonth: [String: [LocalLogEntry]] = [:]
        var monthOrder: [String] = []
        for entry in newEntries {
            let month = try Self.month(ofDay: entry.day)
            if byMonth[month] == nil { monthOrder.append(month) }
            byMonth[month, default: []].append(entry)
        }
        for month in monthOrder {
            loadIfNeeded(month)
            try write((shards[month] ?? []) + (byMonth[month] ?? []), month: month)
        }
    }

    /// Replaces the stored entry with the same id and day, in place.
    public func update(_ entry: LocalLogEntry) throws {
        let month = try Self.month(ofDay: entry.day)
        // An unreadable month throws its own error, not a misleading
        // `.entryNotFound` ("changed in the meantime").
        var entries = try readableShard(month)
        guard let index = entries.firstIndex(where: { $0.id == entry.id && $0.day == entry.day }) else {
            throw LocalFoodLogError.entryNotFound
        }
        entries[index] = entry
        try write(entries, month: month)
    }

    /// Removes the entry and returns it.
    @discardableResult
    public func delete(id: UUID, day: String) throws -> LocalLogEntry {
        let month = try Self.month(ofDay: day)
        loadIfNeeded(month)
        var entries = shards[month] ?? []
        guard let index = entries.firstIndex(where: { $0.id == id && $0.day == day }) else {
            throw LocalFoodLogError.entryNotFound
        }
        let removed = entries.remove(at: index)
        try write(entries, month: month)
        return removed
    }

    // MARK: Files

    func fileURL(month: String) -> URL {
        directoryURL.appendingPathComponent("\(month).json")
    }

    private func loadIfNeeded(_ month: String) {
        guard !loadedMonths.contains(month) else { return }
        let result = FoodLogCoreStorage.loadPersistedJSON(
            [LocalLogEntry].self,
            from: fileURL(month: month),
            decoder: JSONDecoder(),
            category: "LocalFoodLogStore"
        )
        shards[month] = result.value ?? []
        // Unreadable (e.g. before first unlock): retry on next access.
        if !result.isUnreadable { loadedMonths.insert(month) }
    }

    private func readableShard(_ month: String) throws -> [LocalLogEntry] {
        loadIfNeeded(month)
        guard loadedMonths.contains(month) else {
            throw PersistedJSONUnreadFileError(fileName: fileURL(month: month).lastPathComponent)
        }
        return shards[month] ?? []
    }

    /// The one place a month file is written. Callers load the month first;
    /// this refuses a month that exists but was never read this process.
    private func write(_ entries: [LocalLogEntry], month: String) throws {
        let url = fileURL(month: month)
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loadedMonths.contains(month), fileURL: url, category: "LocalFoodLogStore")
        let data: Data
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            DiagnosticsLog.log(.error, category: "LocalFoodLogStore", "could not save \(url.lastPathComponent): \(error)")
            throw LocalFoodLogError.saveFailed(error.localizedDescription)
        }
        shards[month] = entries
    }

    private func monthsOnDisk() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? []
        return names.compactMap { name -> String? in
            guard name.hasSuffix(".json") else { return nil }
            let month = String(name.dropLast(5))
            return Self.isMonth(month) ? month : nil
        }
    }

    // MARK: Day / month strings

    /// `yyyy-MM` of a `yyyy-MM-dd` day, or `.invalidDay`.
    static func month(ofDay day: String) throws -> String {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let monthNumber = Int(parts[1]), (1...12).contains(monthNumber),
              let dayNumber = Int(parts[2]), (1...31).contains(dayNumber)
        else { throw LocalFoodLogError.invalidDay(day) }
        return "\(parts[0])-\(parts[1])"
    }

    static func isMonth(_ value: String) -> Bool {
        (try? month(ofDay: value + "-01")) == value
    }

    /// Every `yyyy-MM` from `first` to `last`, inclusive (both valid).
    static func months(from first: String, to last: String) -> [String] {
        guard var year = Int(first.prefix(4)), var month = Int(first.suffix(2)) else { return [] }
        var result: [String] = []
        while true {
            let yearText = String(year)
            let monthText = month < 10 ? "0\(month)" : String(month)
            let current = String(repeating: "0", count: max(0, 4 - yearText.count)) + yearText + "-" + monthText
            guard current <= last else { break }
            result.append(current)
            // A generous cap: nobody asks for more than a few years at once.
            guard result.count < 1200 else { break }
            month += 1
            if month > 12 { month = 1; year += 1 }
        }
        return result
    }
}
