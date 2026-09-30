// ProjectionStore.swift
//
// The last good plan, always available, and an honest age (spec "The last
// good plan is always available and its age is honest", design D5):
//
//   - `validate(_:)` is the validator the app hands `ConditionalFileSync`
//     (add-vault-connection): the D2 decode, throwing for an invalid or a
//     too-new file, so neither ever replaces the last good copy and the
//     rejected ETag is remembered there;
//   - `loadCached()` decodes the last good bytes off the main actor,
//     without the network, so a cold launch offline shows the plan at
//     once; it decodes each new copy once and logs its dropped elements in
//     ONE Diagnostics line (design D2);
//   - `noteRefresh(_:)` folds a refresh's report in: a rejection is kept
//     (and reported on Today and Plan) until a good copy arrives;
//   - `refresh(via:inputs:force:)` is the app's one refresh step (the
//     coordinator's gated GET, this validator, `noteRefresh`), used for the
//     foreground fetch and the setup fetch (polish-training-today D1).
//
// There is no store file of its own: the only copy of the projection is
// VaultKit's cache (excluded from backups; the vault is the system of
// record). A rejection's reason lives in memory; the app keeps it across
// launches while VaultKit still remembers a rejected ETag.
//
// Freshness never uses `generatedAt` (the vault writes the file only when
// its content changes): `TrainingFreshness` below reads `asOf` against the
// training day and the last successful sync against a 24-hour threshold
// (owner decision 0.3, defaulted).
//
// Depended on by: the app's TrainingModel and VaultServices. Tests:
// ProjectionStoreTests (in-memory transport, real ConditionalFileSync).

import Foundation
import VaultKit

/// The last good copy, decoded.
public struct CachedProjection: Equatable, Sendable {
    public let decoded: DecodedProjection
    /// When VaultKit downloaded these bytes.
    public let fetchedAt: Date?

    public init(decoded: DecodedProjection, fetchedAt: Date?) {
        self.decoded = decoded
        self.fetchedAt = fetchedAt
    }

    public var projection: Projection { decoded.projection }
}

/// Where the plan stands before any screen logic (design D11's rows).
public enum ProjectionAvailability: Equatable, Sendable {
    /// Connection on, nothing cached, no answer yet: "Fetching your plan...".
    case waitingForFirstSync
    /// Repository reachable, file not there: "No plan data yet".
    case notGenerated
    /// Something was downloaded but refused, and there is no last good copy.
    case unreadable(ProjectionRejection)
    case loaded(CachedProjection)

    /// Pure rule over the store's and VaultKit's facts.
    public static func evaluate(
        cached: CachedProjection?,
        rejection: ProjectionRejection?,
        fileNotFound: Bool
    ) -> ProjectionAvailability {
        if let cached { return .loaded(cached) }
        if let rejection { return .unreadable(rejection) }
        return fileNotFound ? .notGenerated : .waitingForFirstSync
    }
}

public actor ProjectionStore {
    private let fetchSync: ConditionalFileSync
    private let path: HubPath

    private var cached: CachedProjection?
    /// (byte count, fetch date) of the bytes `cached` came from.
    private var cachedSignature: String?
    public private(set) var rejection: ProjectionRejection?

    public init(fetchSync: ConditionalFileSync, path: HubPath = VaultHub.projectionPath) {
        self.fetchSync = fetchSync
        self.path = path
    }

    /// The validator for `ConditionalFileSync.refresh` (design D5).
    public static func validate(_ bytes: Data) throws {
        try ProjectionDecoder.validate(bytes)
    }

    /// The last good copy, decoded; `nil` when there is none (or it no
    /// longer decodes -- then it is logged once and treated as absent).
    public func loadCached() async -> CachedProjection? {
        guard let file = await fetchSync.cachedFile(path) else {
            cached = nil
            cachedSignature = nil
            return nil
        }
        let signature = "\(file.bytes.count)|\(file.fetchedAt?.timeIntervalSince1970 ?? 0)"
        if signature == cachedSignature, let cached { return cached }
        cachedSignature = signature
        switch ProjectionDecoder.decode(file.bytes) {
        case .success(let decoded):
            if let summary = decoded.issues.summary {
                VaultLog.log(.warning, "projection: \(summary)")
            }
            let result = CachedProjection(decoded: decoded, fetchedAt: file.fetchedAt)
            cached = result
            return result
        case .failure(let rejection):
            // Only possible if a build with a different contract stored it.
            VaultLog.log(.error, "projection: the cached copy no longer reads (\(rejection))")
            cached = nil
            return nil
        }
    }

    /// Folds one refresh's report in (design D5, D11).
    public func noteRefresh(_ report: FetchReport) {
        switch report {
        case .updated:
            rejection = nil
        case .rejected(let reason):
            rejection = ProjectionRejection(reportReason: reason) ?? .invalid(reason: reason)
        case .unchanged, .failed:
            break
        }
    }

    /// One foreground (or setup) refresh through VaultKit's coordinator,
    /// validated with this store's decoder and folded in -- the app's whole
    /// refresh step, here so it is tested (polish-training-today D1).
    @discardableResult
    public func refresh(via coordinator: VaultSyncCoordinator, inputs: VaultSyncInputs, force: Bool, now: Date = Date()) async -> VaultRefreshReport {
        let report = await coordinator.refreshProjection(inputs, force: force, now: now) { bytes in
            try ProjectionStore.validate(bytes)
        }
        if case .ran(let fetch) = report {
            noteRefresh(fetch)
        }
        return report
    }

    /// The app restores a rejection across launches (see the header).
    public func restoreRejection(_ rejection: ProjectionRejection?) {
        self.rejection = rejection
    }

    /// Whether VaultKit still remembers a refused copy of the file.
    public func hasRejectedCopy() async -> Bool {
        await fetchSync.entry(for: path)?.rejectedETag != nil
    }

    /// Disconnect: forget the decoded copy (VaultKit clears the bytes).
    public func clear() {
        cached = nil
        cachedSignature = nil
        rejection = nil
    }
}

// MARK: - Freshness

/// How much to trust what is shown (design D5, D11): subtle lines, never
/// banners. Auth problems are VaultKit's loud banner, not this.
public struct TrainingFreshness: Equatable, Sendable {
    /// Owner decision 0.3 (defaulted): stale after 24 h without a sync.
    public static let staleAfter: TimeInterval = 24 * 3600

    /// The training day the file describes.
    public var asOf: LocalDate?
    /// `asOf` is before the current training day: statuses may lag.
    public var isBehind: Bool
    /// Whole days since the last successful sync, when that is 24 h or
    /// more; `nil` when fresh or unknown.
    public var staleDays: Int?
    /// The latest file was refused; what is shown is the last good one.
    public var rejection: ProjectionRejection?
    /// The file carries a `supersededBy` hint (quiet).
    public var hasNewerVersionHint: Bool

    public init(asOf: LocalDate? = nil, isBehind: Bool = false, staleDays: Int? = nil, rejection: ProjectionRejection? = nil, hasNewerVersionHint: Bool = false) {
        self.asOf = asOf
        self.isBehind = isBehind
        self.staleDays = staleDays
        self.rejection = rejection
        self.hasNewerVersionHint = hasNewerVersionHint
    }

    /// Never reads `generatedAt`.
    public static func evaluate(
        asOf: LocalDate?,
        trainingToday: LocalDate,
        lastSuccessAt: Date?,
        now: Date,
        rejection: ProjectionRejection? = nil,
        hasNewerVersionHint: Bool = false
    ) -> TrainingFreshness {
        var staleDays: Int?
        if let lastSuccessAt {
            let age = now.timeIntervalSince(lastSuccessAt)
            if age >= staleAfter {
                staleDays = max(1, Int(age / 86_400))
            }
        }
        return TrainingFreshness(
            asOf: asOf,
            isBehind: asOf.map { $0 < trainingToday } ?? false,
            staleDays: staleDays,
            rejection: rejection,
            hasNewerVersionHint: hasNewerVersionHint
        )
    }
}
