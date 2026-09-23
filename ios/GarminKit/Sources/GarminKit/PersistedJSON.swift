// PersistedJSON.swift
//
// The one shared "read this store's JSON file back from disk" routine for
// every JSON-file-backed store in GarminKit, FoodLogCore and Gamification
// (openspec/changes/fix-silent-store-wipe).
//
// Why this exists: every store used to load with
// `(try? decoder.decode(...)) ?? []` and then latch `loaded = true`. A file
// that existed but no longer decoded (a model change that isn't backward
// compatible, a truncated/corrupted write, a hand edit) therefore made the
// store silently start EMPTY -- and the very next `upsert`/`enqueue`/
// `record` atomically overwrote the original file with just the new data,
// permanently destroying unsent outbox entries, custom foods, meal presets,
// favorites, the XP ledger, achievements... with no log line anywhere.
// Several of those stores have no copy anywhere else (not in Garmin, not in
// iCloud -- there is none, see openspec/config.yaml), so that wipe was
// unrecoverable, and it violated CLAUDE.md's "failures must surface" rule.
//
// What this does instead, per outcome:
//   - no file yet            -> `nil`, silently (a normal first launch).
//   - file unreadable        -> `nil`, logged as an error, file left IN
//                               PLACE (it may just be locked by data
//                               protection before first unlock -- moving it
//                               would be wrong, and it will read fine later).
//   - file doesn't decode    -> `nil`, logged as an error, and the file is
//                               MOVED ASIDE to
//                               `<name>.unreadable-<yyyyMMdd-HHmmss>.json`
//                               in the same directory, so the store's next
//                               save writes a fresh file instead of
//                               clobbering the original bytes. The original
//                               stays on disk, recoverable by hand.
//   - success                -> the decoded value.
//
// Lives in GarminKit because it has no dependencies of its own and every
// other package already depends on GarminKit (FoodLogCore directly;
// Gamification via FoodLogCore's `FoodLogCoreStorage.loadPersistedJSON`
// passthrough, since Gamification deliberately does not depend on GarminKit
// -- see its Package.swift header). Logs through `DiagnosticsLog`'s
// fire-and-forget static entry point, so it's safe to call synchronously
// from inside any store actor's `loadIfNeeded()`.
//
// `DiagnosticsLog`'s OWN store deliberately does NOT use this: a decode
// failure there would log into the very log that's mid-load.

import Foundation

public enum PersistedJSON {
    /// Cap on how much of a decoding error's description goes into the
    /// diagnostics log -- `DecodingError` descriptions include the full
    /// coding path and can get long; the log is capped and shown on-device.
    static let maxLoggedErrorLength = 500

    /// Loads and decodes `type` from `fileURL`, quarantining a file that
    /// exists but cannot be decoded -- see this file's header for the exact
    /// per-outcome behaviour. Returns `nil` for every non-success outcome;
    /// callers fall back to their own empty state, exactly as before, but
    /// the original data is no longer at risk of being overwritten.
    ///
    /// `decoder` is passed in (not constructed here) so each store keeps its
    /// own existing configuration (e.g. `.iso8601` dates or not) -- changing
    /// that would break decoding of data already on the owner's phone.
    public static func load<T: Decodable>(
        _ type: T.Type,
        from fileURL: URL,
        decoder: JSONDecoder,
        category: String
    ) -> T? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            if isFileNotFound(error) {
                return nil
            }
            DiagnosticsLog.log(
                .error,
                category: category,
                "could not read \(fileURL.lastPathComponent) (left in place, store starts empty this launch): \(truncated(error))"
            )
            return nil
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            let quarantineURL = quarantineDestination(for: fileURL)
            do {
                try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
                DiagnosticsLog.log(
                    .error,
                    category: category,
                    "could not decode \(fileURL.lastPathComponent); moved it aside to \(quarantineURL.lastPathComponent) so it is not overwritten (store starts empty): \(truncated(error))"
                )
            } catch let moveError {
                DiagnosticsLog.log(
                    .error,
                    category: category,
                    "could not decode \(fileURL.lastPathComponent): \(truncated(error)) -- AND could not move it aside to \(quarantineURL.lastPathComponent): \(truncated(moveError)). The next save to this store may overwrite it."
                )
            }
            return nil
        }
    }

    // MARK: - Helpers

    private static func isFileNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(ENOENT)
        }
        return false
    }

    /// `<name-without-.json>.unreadable-<yyyyMMdd-HHmmss>.json`, next to the
    /// original. If that exact name is already taken (two quarantines of the
    /// same file within one second), a short random suffix is appended
    /// rather than failing the move.
    static func quarantineDestination(for fileURL: URL, now: Date = Date()) -> URL {
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.pathExtension.lowercased() == "json"
            ? fileURL.deletingPathExtension().lastPathComponent
            : fileURL.lastPathComponent

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)

        let candidate = directory.appendingPathComponent("\(baseName).unreadable-\(stamp).json")
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let suffix = UUID().uuidString.prefix(8)
        return directory.appendingPathComponent("\(baseName).unreadable-\(stamp)-\(suffix).json")
    }

    private static func truncated(_ error: Error) -> String {
        String(String(describing: error).prefix(maxLoggedErrorLength))
    }
}
