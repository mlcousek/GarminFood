// SealedFile.swift
//
// One vault write, sealed (add-vault-connection design D7): the bytes are
// fixed when the record is created, together with their git blob SHA, so
// every retry sends exactly the same bytes and "did an earlier attempt
// already land?" has an exact answer -- the file at that path either has
// the same blob SHA or it doesn't. "Seal, then send."
//
// Git's blob id is `sha1("blob <byte count>\0" + bytes)`; the empty blob is
// `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391`. SHA-1 here is git's object
// naming, used for equality with what GitHub stores -- not for security.
//
// Paths, file names and commit messages are the caller's business
// (add-training-checkins defines them). Nothing in this change seals a file
// in production.
//
// Depended on by: CreateOnlyFileUploader, DurableQueue's write queue,
// VaultTransport. Tests: CreateOnlyFileUploaderTests (blob vectors).

import Foundation
import CryptoKit

public struct SealedFile: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let path: HubPath
    public let bytes: Data
    /// Lowercase hex git blob SHA-1 of `bytes`.
    public let blobSHA: String
    public let commitMessage: String
    public let createdAt: Date

    /// Seals `bytes` for `path`, computing the blob SHA now.
    public init(id: UUID = UUID(), path: HubPath, bytes: Data, commitMessage: String, createdAt: Date = Date()) {
        self.id = id
        self.path = path
        self.bytes = bytes
        self.blobSHA = GitBlob.sha1Hex(of: bytes)
        self.commitMessage = commitMessage
        self.createdAt = createdAt
    }
}

public enum GitBlob {
    /// `sha1("blob <n>\0" + bytes)` as 40 lowercase hex characters -- the
    /// id `git hash-object` prints for these bytes.
    public static func sha1Hex(of bytes: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(bytes.count)\u{0}".utf8))
        hasher.update(data: bytes)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
