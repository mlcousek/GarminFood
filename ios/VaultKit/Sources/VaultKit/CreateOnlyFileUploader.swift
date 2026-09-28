// CreateOnlyFileUploader.swift
//
// Delivers one `SealedFile` so that a retry can never create a second file
// or overwrite anything (add-vault-connection design D7, spec "Vault writes
// are durable, create-only and idempotent"):
//
//   1. create-only PUT (no `sha`). 201 -> delivered.
//   2. 422 "already exists" -> GET the same path (allowed: the install's own
//      folder) and compare git blob SHAs. Equal -> delivered: an earlier
//      attempt landed but its response was lost. Different ->
//      `.failedPermanently("a different file already exists")`, logged as an
//      error -- that can only be a bug, because paths embed the device id
//      and a timestamp.
//   3. 409 (writes racing on the branch ref) and 5xx -> retry with backoff.
//   Auth -> stop the cycle; offline -> stop the cycle; rate limit -> stop
//   the cycle until the reset. None of those spend an attempt
//   (`DurableQueue`).
//
// It takes a `VaultTransport`, never GitHub directly, so the same code
// delivers through a later iCloud bridge. The blob SHA is computed from
// the bytes the GET returns, which works for any transport (GitHub's raw
// media type returns the bytes, not the JSON with a `sha` field).
//
// Also: `VaultWriteQueue`, the factory for the vault's own queue file
// (`VaultKit/write-queue.json`, lazily created, excluded from backups,
// design D12). Not instantiated in production in this change.
//
// Tests: CreateOnlyFileUploaderTests.

import Foundation

public struct CreateOnlyFileUploader: DurableQueueDelivering {
    public typealias Record = SealedFile

    private let transport: VaultTransport

    public init(transport: VaultTransport) {
        self.transport = transport
    }

    public static let differentFileReason = "a different file already exists"

    public func deliver(_ file: SealedFile) async -> DurableQueueDelivery {
        let write = await transport.createOnly(file)
        switch write.outcome {
        case .created:
            return .delivered
        case .alreadyExists:
            return await compareExisting(file)
        case .failed(let outcome):
            return Self.delivery(for: outcome)
        }
    }

    /// Step 2: is what's already there exactly our file?
    private func compareExisting(_ file: SealedFile) async -> DurableQueueDelivery {
        let existing = await transport.fetch(file.path, ifNoneMatch: nil)
        switch existing.outcome {
        case .fetched(let bytes, _):
            if GitBlob.sha1Hex(of: bytes) == file.blobSHA {
                VaultLog.log(.info, "\(file.path.rawValue): already there with the same content; treating as delivered")
                return .delivered
            }
            VaultLog.log(.error, "\(file.path.rawValue): \(Self.differentFileReason) (\(bytes.count) bytes); not overwritten")
            return .failedPermanently(reason: Self.differentFileReason)
        case .notModified:
            // We sent no If-None-Match, so this shouldn't happen; try later.
            return .retry(after: nil, reason: "unexpected 304 while checking an existing file")
        case .failed(let outcome):
            return Self.delivery(for: outcome)
        }
    }

    /// How a failed request maps onto the queue's rules.
    static func delivery(for outcome: VaultOutcome) -> DurableQueueDelivery {
        switch outcome {
        case .authFailed:
            return .stopCycle(.auth)
        case .notConfigured:
            // No token or repository: the user must act, like auth.
            return .stopCycle(.auth)
        case .offline:
            return .stopCycle(.offline)
        case .rateLimited(let until):
            return .stopCycle(.rateLimited(until: until))
        case .refusedByPolicy:
            return .failedPermanently(reason: "refused by the path policy")
        case .redirectRefused:
            return .failedPermanently(reason: "redirect to another host refused")
        case .conflict, .serverError, .unexpected, .transportError, .fileNotFound, .alreadyExists, .success:
            return .retry(after: nil, reason: outcome.logLabel)
        }
    }
}

/// The vault's own write queue (design D7/D12).
public enum VaultWriteQueue {
    public static let fileName = "write-queue.json"

    public static func make(directory: URL = VaultStorage.defaultDirectory()) -> DurableQueue<SealedFile> {
        DurableQueue<SealedFile>(fileURL: directory.appendingPathComponent("write-queue.json"))
    }
}
