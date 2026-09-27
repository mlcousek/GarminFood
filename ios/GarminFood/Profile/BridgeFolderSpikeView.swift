// BridgeFolderSpikeView.swift
//
// THROWAWAY SPIKE -- openspec/changes/add-mcp-server task 1.1. Delete this
// file (and the menu item in DiagnosticsLogView that opens it) in task 4.1,
// when the real PC bridge replaces it.
//
// Why it exists: the whole PC bridge (design.md D2) rests on one unverified
// assumption -- that an app signed by a FREE Apple Personal Team (no iCloud
// entitlement, no App Group) can keep read/write access to a folder in
// iCloud Drive that the user picked once with the document picker, across
// relaunches and AltStore's weekly re-sign, and that files written by
// iCloud for Windows show up here (and ours show up there). None of that can
// be tried in CI or a simulator, so this screen does each step by hand on
// the device and reports every outcome, success or failure, both on screen
// and in DiagnosticsLog (category `bridge-spike`), so the owner can copy
// the log and paste it back. The four buttons map to tasks 1.2-1.4:
//
//   - Choose folder: `.fileImporter(allowedContentTypes: [.folder])`; the
//     returned URL is security-scoped, so access is started and held while
//     this screen is open, and two bookmarks are saved (see below).
//   - Write spike.txt: a coordinated write of the current time (1.2).
//   - List folder: a coordinated read of the folder; iCloud items that are
//     not downloaded yet (a real name with status "not downloaded", or the
//     older hidden `.name.icloud` stub) get
//     `FileManager.startDownloadingUbiquitousItem(at:)` and are reported as
//     "try again shortly", not as an error; small downloaded files are read
//     and previewed (1.3).
//   - Reopen from bookmark: resolves each saved bookmark, reports
//     stale/ok and whether security-scoped access starts, then lists the
//     folder -- run after a force-quit and after a re-sign (1.4).
//
// Bookmark options: `.withSecurityScope` / `.securityScopeAllowOnlyReadAccess`
// are macOS-only. On iOS a bookmark of a document-picker URL carries its
// security scope implicitly. Apple's "Providing access to directories"
// sample uses `.minimalBookmark`; the plain default (`[]`) is the other
// common choice. Which one survives a re-sign on this account is exactly
// what the spike is for, so it saves and tries BOTH.
//
// Depends on: GarminKit.DiagnosticsLog only. Deliberately not wired through
// AppServices/AppEnvironment -- nothing else reads what it stores (two
// UserDefaults keys under `spike.bridge.`), and it is deleted in wave 4.

import SwiftUI
import UniformTypeIdentifiers
import GarminKit

@MainActor
struct BridgeFolderSpikeView: View {
    @State private var isPicking = false
    /// The folder URL whose security-scoped access this screen currently
    /// holds (started, not yet stopped).
    @State private var folderURL: URL?
    @State private var lines: [BridgeSpikeLine] = []
    @State private var isBusy = false

    var body: some View {
        List {
            Section {
                Button("Choose folder…") { isPicking = true }
                Button("Write spike.txt") { writeSpike() }
                    .disabled(folderURL == nil || isBusy)
                Button("List folder") { listFolder() }
                    .disabled(folderURL == nil || isBusy)
                Button("Reopen from bookmark") { reopenFromBookmark() }
                    .disabled(isBusy)
            } footer: {
                Text("Testing only. Pick iCloud Drive › GarminFood Bridge. Every result is also written to the diagnostics log under bridge-spike.")
            }

            Section("Folder") {
                Text(verbatim: folderURL?.path ?? "—")
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }

            Section("Results") {
                if lines.isEmpty {
                    Text("No results yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(lines.reversed()) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Text(verbatim: line.text)
                                .font(.footnote)
                                .foregroundStyle(line.isError ? Theme.over : Color.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bridge folder spike")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
            handlePick(result)
        }
        .onDisappear { releaseFolder() }
    }

    // MARK: - Actions

    private func handlePick(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            record(.error, "Picker failed: \(BridgeSpikeFiles.describe(error))")
        case .success(let url):
            releaseFolder()
            let granted = url.startAccessingSecurityScopedResource()
            record(granted ? .info : .warning, "Picked \(url.path) -- startAccessingSecurityScopedResource() = \(granted)")
            folderURL = url
            for kind in BridgeSpikeBookmarkKind.allCases {
                do {
                    let data = try BridgeSpikeFiles.makeBookmark(for: url, kind: kind)
                    UserDefaults.standard.set(data, forKey: kind.defaultsKey)
                    record(.info, "Saved \(kind.label) bookmark (\(data.count) bytes).")
                } catch {
                    record(.error, "Could not create \(kind.label) bookmark: \(BridgeSpikeFiles.describe(error))")
                }
            }
        }
    }

    private func writeSpike() {
        guard let folder = folderURL else { return }
        runOffMain { try BridgeSpikeFiles.writeSpike(in: folder) }
    }

    private func listFolder() {
        guard let folder = folderURL else { return }
        runOffMain { try BridgeSpikeFiles.list(folder) }
    }

    private func reopenFromBookmark() {
        releaseFolder()
        var reopened: URL?
        for kind in BridgeSpikeBookmarkKind.allCases {
            guard let data = UserDefaults.standard.data(forKey: kind.defaultsKey) else {
                record(.warning, "No \(kind.label) bookmark saved -- choose the folder first.")
                continue
            }
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                let granted = url.startAccessingSecurityScopedResource()
                let level: DiagnosticsLevel = (isStale || !granted) ? .warning : .info
                record(level, "\(kind.label) bookmark resolved to \(url.path) -- stale: \(isStale), access: \(granted)")
                if isStale, granted {
                    // Apple's guidance: re-create a stale bookmark while access is held.
                    do {
                        let fresh = try BridgeSpikeFiles.makeBookmark(for: url, kind: kind)
                        UserDefaults.standard.set(fresh, forKey: kind.defaultsKey)
                        record(.info, "Re-saved the stale \(kind.label) bookmark (\(fresh.count) bytes).")
                    } catch {
                        record(.error, "Could not re-save the \(kind.label) bookmark: \(BridgeSpikeFiles.describe(error))")
                    }
                }
                if reopened == nil, granted {
                    reopened = url
                } else if granted {
                    url.stopAccessingSecurityScopedResource()
                }
            } catch {
                record(.error, "\(kind.label) bookmark did not resolve: \(BridgeSpikeFiles.describe(error))")
            }
        }
        if let reopened {
            folderURL = reopened
            listFolder()
        } else {
            record(.error, "No bookmark gave access to the folder -- the picker would be needed again.")
        }
    }

    private func releaseFolder() {
        folderURL?.stopAccessingSecurityScopedResource()
        folderURL = nil
    }

    // MARK: - Helpers

    /// File coordination blocks its thread, so every file operation runs in
    /// a detached task; the resulting lines are recorded back on the main actor.
    private func runOffMain(_ work: @escaping @Sendable () throws -> [BridgeSpikeLineDraft]) {
        isBusy = true
        Task {
            let drafts: [BridgeSpikeLineDraft]
            do {
                drafts = try await Task.detached(priority: .userInitiated) { try work() }.value
            } catch {
                drafts = [BridgeSpikeLineDraft(level: .error, text: "Failed: \(BridgeSpikeFiles.describe(error))")]
            }
            for draft in drafts { record(draft.level, draft.text) }
            isBusy = false
        }
    }

    private func record(_ level: DiagnosticsLevel, _ message: String) {
        lines.append(BridgeSpikeLine(text: message, isError: level == .error))
        DiagnosticsLog.log(level, category: "bridge-spike", message)
    }
}

// MARK: - Model

struct BridgeSpikeLine: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let text: String
    let isError: Bool
}

struct BridgeSpikeLineDraft: Sendable {
    let level: DiagnosticsLevel
    let text: String
}

enum BridgeSpikeBookmarkKind: CaseIterable {
    case minimal, standard

    var label: String {
        switch self {
        case .minimal: "minimal"
        case .standard: "default"
        }
    }

    var options: URL.BookmarkCreationOptions {
        switch self {
        case .minimal: return [.minimalBookmark]
        case .standard: return []
        }
    }

    var defaultsKey: String {
        switch self {
        case .minimal: "spike.bridge.bookmark.minimal"
        case .standard: "spike.bridge.bookmark.default"
        }
    }
}

// MARK: - File operations (off the main actor)

enum BridgeSpikeFiles {
    /// Anything bigger is listed but not previewed.
    static let previewLimitBytes = 64 * 1024

    static func makeBookmark(for url: URL, kind: BridgeSpikeBookmarkKind) throws -> Data {
        try url.bookmarkData(options: kind.options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func writeSpike(in folder: URL) throws -> [BridgeSpikeLineDraft] {
        let target = folder.appendingPathComponent("spike.txt")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("GarminFood bridge spike\nwritten by the phone at \(stamp)\n".utf8)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        return [BridgeSpikeLineDraft(level: .info, text: "Wrote spike.txt (\(data.count) bytes), timestamp \(stamp).")]
    }

    static func list(_ folder: URL) throws -> [BridgeSpikeLineDraft] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        var items: [URL] = []
        var coordinationError: NSError?
        var listError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: folder, options: [], error: &coordinationError) { url in
            do {
                // No .skipsHiddenFiles: older iOS shows a not-downloaded
                // iCloud file as a hidden `.name.icloud` stub.
                items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
            } catch {
                listError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let listError { throw listError }

        var out = [BridgeSpikeLineDraft(level: .info, text: "Listed \(folder.lastPathComponent): \(items.count) item(s).")]
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            out.append(describeItem(item, in: folder, keys: Set(keys)))
        }
        return out
    }

    private static func describeItem(_ item: URL, in folder: URL, keys: Set<URLResourceKey>) -> BridgeSpikeLineDraft {
        let name = item.lastPathComponent

        // Legacy placeholder stub: ".spike.txt.icloud" stands for "spike.txt".
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            let realName = String(name.dropFirst().dropLast(".icloud".count))
            let real = folder.appendingPathComponent(realName)
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: real)
                return BridgeSpikeLineDraft(level: .info, text: "\(realName): placeholder (\(name)), download requested -- list again shortly.")
            } catch {
                return BridgeSpikeLineDraft(level: .error, text: "\(realName): placeholder (\(name)), download request failed: \(describe(error))")
            }
        }

        let values = try? item.resourceValues(forKeys: keys)
        let isDirectory = values?.isDirectory ?? false
        let size = values?.fileSize ?? 0
        let modified = values?.contentModificationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "?"
        let status = values?.ubiquitousItemDownloadingStatus
        let statusText = status.map { $0.rawValue } ?? "not ubiquitous"
        let summary = "\(name)\(isDirectory ? "/" : ""): \(isDirectory ? "folder" : "\(size) bytes"), modified \(modified), iCloud status \(statusText)"

        if status == .notDownloaded {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: item)
                return BridgeSpikeLineDraft(level: .info, text: "\(summary) -- not downloaded yet, download requested; list again shortly.")
            } catch {
                return BridgeSpikeLineDraft(level: .error, text: "\(summary) -- download request failed: \(describe(error))")
            }
        }
        guard !isDirectory else { return BridgeSpikeLineDraft(level: .info, text: summary) }
        guard size <= previewLimitBytes else { return BridgeSpikeLineDraft(level: .info, text: "\(summary) -- too big to preview.") }

        do {
            let text = try readCoordinated(item)
            let preview = text.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(120)
            return BridgeSpikeLineDraft(level: .info, text: "\(summary) -- read OK: \"\(preview)\"")
        } catch {
            return BridgeSpikeLineDraft(level: .error, text: "\(summary) -- read failed: \(describe(error))")
        }
    }

    private static func readCoordinated(_ url: URL) throws -> String {
        var data = Data()
        var coordinationError: NSError?
        var readError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do {
                data = try Data(contentsOf: readURL)
            } catch {
                readError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        return String(decoding: data, as: UTF8.self)
    }

    /// Domain + code + message, so a pasted log line is enough to look the
    /// error up (e.g. NSCocoaErrorDomain 257 = no permission).
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }
}
