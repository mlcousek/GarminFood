// DiagnosticsLog.swift
//
// A small, persistent, IN-APP-VISIBLE log. Exists because this project has
// no Mac (openspec/config.yaml's hard constraint): there is no Console.app,
// no attached debugger, no Instruments -- when something goes wrong on the
// owner's real device, the only recourse today is re-describing symptoms
// from memory. Every entry also goes through `os.Logger` (so it's still
// visible via sysdiagnose or a Mac, if one is ever available), but the
// actual point of this type is the file-backed copy: capped, readable, and
// shareable straight from an in-app screen (`DiagnosticsLogView` in the app
// target) with zero extra tooling required.
//
// Lives in GarminKit (not FoodLogCore or the app target) because it has no
// dependencies of its own and everything else already depends on GarminKit
// transitively -- the same reason `MealType`/`Outbox` live here. Logging is
// wired into GarminClient's two central choke points (`perform`/
// `throwIfNotSuccessful`, covering every Garmin route in one place) and
// `Outbox.drain`; the app layer adds its own calls at confirm-screen error
// sites, where the user-facing message is necessarily generic ("couldn't
// save, try again") but the real underlying error is worth keeping.

import Foundation
import os

public enum DiagnosticsLevel: String, Codable, Sendable {
    case info, warning, error
}

public struct DiagnosticsEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: DiagnosticsLevel
    public let category: String
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: DiagnosticsLevel, category: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

public actor DiagnosticsLog {
    public static let shared = DiagnosticsLog()

    private let fileURL: URL
    private let maxEntries: Int
    private var entries: [DiagnosticsEntry] = []
    private var loaded = false
    private let osLog = Logger(subsystem: "com.mlcousek.garminfood", category: "diagnostics")

    public init(fileURL: URL = DiagnosticsLog.defaultFileURL(), maxEntries: Int = 500) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("GarminKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics-log.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([DiagnosticsEntry].self, from: data)) ?? []
    }

    private func persist() {
        loadIfNeeded()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Appends one entry, capped at `maxEntries` (oldest dropped first) --
    /// this is a rolling diagnostic window, not a durable audit log.
    public func log(_ level: DiagnosticsLevel, category: String, _ message: String) {
        loadIfNeeded()
        entries.append(DiagnosticsEntry(level: level, category: category, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
        switch level {
        case .info: osLog.info("\(category, privacy: .public): \(message, privacy: .public)")
        case .warning: osLog.warning("\(category, privacy: .public): \(message, privacy: .public)")
        case .error: osLog.error("\(category, privacy: .public): \(message, privacy: .public)")
        }
    }

    public func all() -> [DiagnosticsEntry] {
        loadIfNeeded()
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    public func clear() {
        loadIfNeeded()
        entries.removeAll()
        persist()
    }

    /// Fire-and-forget convenience for call sites that aren't already
    /// `async` (e.g. a synchronous `catch` block) -- logging must never
    /// require the caller to await it or change its own error-handling
    /// shape just to record a diagnostic.
    public static func log(_ level: DiagnosticsLevel, category: String, _ message: String) {
        Task { await shared.log(level, category: category, message) }
    }
}
