// VaultOutcome.swift
//
// How a GitHub answer is classified: loud, quiet, or retry
// (add-vault-connection design D6). The same split `DrainAuthOutcome` makes
// for Garmin, because the house rule is the same: failures that need the
// user are loud (a banner on every tab), everything else degrades quietly
// and is retried later -- and a rate limit means "stop and resume later",
// never "retry harder" (openspec/config.yaml).
//
//   2xx, 304                                  success
//   401                                       loud: token rejected
//   403 without rate-limit signals            loud: forbidden
//   404 on the repository (or on a write)     loud: repository not found
//   404 on a file                             quiet: file not found
//   429, or 403 with x-ratelimit-remaining: 0
//     or a retry-after header                 quiet: rate limited until ...
//   422 on a create                           already exists (design D7)
//   409                                       quiet retry (conflict)
//   5xx                                       quiet retry (server error)
//   ConnectivityFailure                       quiet, no attempt spent
//   a redirect to another host                refused (logged as an error)
//   anything else                             quiet, logged, shown in Details
//
// `classify` is pure and table-tested (VaultOutcomeTests). Headers come in
// through `VaultResponseHeaders` (case-insensitive), which also parses the
// token-expiry header (design D10; its exact name and format are "documented,
// not observed" until probe task 1.3, so parsing is tolerant and "absent" is
// a normal result).
//
// Nothing here can carry the token or the repository: outcomes hold status
// codes and dates only.

import Foundation
import GarminKit

public enum VaultAuthProblem: String, Codable, Sendable, Equatable, CaseIterable {
    /// 401: expired or revoked.
    case tokenRejected
    /// 403 without rate-limit signals: the token can't access the repository.
    case forbidden
    /// 404 on the repository: a typo, or the token can't see it.
    case repositoryNotFound
}

public enum VaultOutcome: Codable, Sendable, Equatable {
    case success
    case authFailed(VaultAuthProblem)
    case fileNotFound
    case rateLimited(until: Date)
    case alreadyExists
    case conflict
    case serverError(status: Int)
    case offline
    /// Refused by `VaultPathPolicy` before anything was sent.
    case refusedByPolicy
    /// A redirect to a host other than api.github.com was refused, so the
    /// token never followed it (design D2).
    case redirectRefused
    /// No token, or no valid repository, when a request was about to be
    /// built. Nothing was sent.
    case notConfigured
    case unexpected(status: Int)
    /// A transport error that is not a connectivity failure (cancelled,
    /// TLS, a malformed response). `code` is the `URLError` code, if any.
    case transportError(code: Int)

    /// Needs the user; stops vault requests until they act (design D6).
    public var isLoud: Bool {
        if case .authFailed = self { return true }
        return false
    }

    /// The request reached GitHub and GitHub answered usefully.
    public var isSuccess: Bool {
        self == .success
    }

    /// A short, English, redacted label for DiagnosticsLog lines.
    public var logLabel: String {
        switch self {
        case .success: return "ok"
        case .authFailed(let problem): return "auth failed (\(problem.rawValue))"
        case .fileNotFound: return "file not found"
        case .rateLimited(let until): return "rate limited until \(ISO8601DateFormatter().string(from: until))"
        case .alreadyExists: return "already exists"
        case .conflict: return "conflict (409)"
        case .serverError(let status): return "server error (\(status))"
        case .offline: return "offline"
        case .refusedByPolicy: return "refused by path policy"
        case .redirectRefused: return "redirect to another host refused"
        case .notConfigured: return "not configured"
        case .unexpected(let status): return "unexpected status \(status)"
        case .transportError(let code): return "transport error (URLError \(code))"
        }
    }

    /// Which request an HTTP status answers -- a 404 means different things
    /// for each (design D6).
    public enum RequestKind: Sendable, Equatable {
        case repository
        case file
        case create
    }

    /// Classifies an HTTP answer. `now` anchors a relative `retry-after`.
    public static func classify(status: Int, headers: VaultResponseHeaders, kind: RequestKind, now: Date) -> VaultOutcome {
        switch status {
        case 200..<300, 304:
            return .success
        case 300..<400:
            // Only a refused cross-host redirect reaches us as a 3xx: a
            // same-host one is followed by URLSession.
            return .redirectRefused
        case 401:
            return .authFailed(.tokenRejected)
        case 403:
            if let until = headers.rateLimitedUntil(now: now) { return .rateLimited(until: until) }
            return .authFailed(.forbidden)
        case 404:
            switch kind {
            case .repository, .create: return .authFailed(.repositoryNotFound)
            case .file: return .fileNotFound
            }
        case 409:
            return .conflict
        case 422:
            return kind == .create ? .alreadyExists : .unexpected(status: status)
        case 429:
            return .rateLimited(until: headers.rateLimitedUntil(now: now) ?? now.addingTimeInterval(VaultResponseHeaders.defaultRateLimitPause))
        case 500..<600:
            return .serverError(status: status)
        default:
            return .unexpected(status: status)
        }
    }

    /// Classifies an error thrown before any HTTP answer arrived.
    public static func classify(error: Error) -> VaultOutcome {
        if ConnectivityFailure.matches(error) { return .offline }
        if let urlError = error as? URLError { return .transportError(code: urlError.code.rawValue) }
        return .transportError(code: 0)
    }
}

/// Response headers, looked up case-insensitively, plus the two things
/// VaultKit reads from them: rate-limit signals and the token's expiry.
public struct VaultResponseHeaders: Equatable, Sendable {
    /// When a 429 carries no usable header: wait a minute.
    public static let defaultRateLimitPause: TimeInterval = 60
    /// Never trust a rate-limit pause longer than this (the primary limit
    /// resets hourly); a bogus header can't park the connection for a day.
    public static let maximumRateLimitPause: TimeInterval = 60 * 60
    /// design D10: "documented, not observed" until probe task 1.3.
    public static let tokenExpirationHeader = "github-authentication-token-expiration"

    private let values: [String: String]

    public init(_ headers: [String: String] = [:]) {
        var lowered: [String: String] = [:]
        for (name, value) in headers {
            lowered[name.lowercased()] = value
        }
        self.values = lowered
    }

    public init(_ response: HTTPURLResponse) {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            if let name = name as? String {
                headers[name] = "\(value)"
            }
        }
        self.init(headers)
    }

    public subscript(name: String) -> String? {
        values[name.lowercased()]
    }

    /// `true` when a 403 is really a rate limit: `x-ratelimit-remaining: 0`
    /// or a `retry-after` header (GitHub's secondary limits).
    public var hasRateLimitSignal: Bool {
        if self["retry-after"] != nil { return true }
        if let remaining = self["x-ratelimit-remaining"]?.trimmingCharacters(in: .whitespaces), remaining == "0" { return true }
        return false
    }

    /// When requests may resume, or `nil` when these headers carry no
    /// rate-limit signal. `retry-after` (seconds) wins over
    /// `x-ratelimit-reset` (epoch seconds); the result is clamped to
    /// `[now + 1 s, now + maximumRateLimitPause]`.
    public func rateLimitedUntil(now: Date) -> Date? {
        guard hasRateLimitSignal else { return nil }
        var until: Date?
        if let retryAfter = self["retry-after"].flatMap({ TimeInterval($0.trimmingCharacters(in: .whitespaces)) }), retryAfter >= 0 {
            until = now.addingTimeInterval(retryAfter)
        } else if let reset = self["x-ratelimit-reset"].flatMap({ TimeInterval($0.trimmingCharacters(in: .whitespaces)) }) {
            until = Date(timeIntervalSince1970: reset)
        }
        let resolved = until ?? now.addingTimeInterval(Self.defaultRateLimitPause)
        let earliest = now.addingTimeInterval(1)
        let latest = now.addingTimeInterval(Self.maximumRateLimitPause)
        return min(max(resolved, earliest), latest)
    }

    /// The token's expiry, when GitHub reports it (design D10).
    public var tokenExpiresAt: Date? {
        self[Self.tokenExpirationHeader].flatMap(TokenExpiryParser.parse)
    }
}

/// Tolerant parsing of the token-expiry header. GitHub's docs show
/// `2023-11-14 18:30:00 UTC`; the probe (task 1.3) records the real format.
/// Unparseable means "Expiry unknown", never an error.
public enum TokenExpiryParser {
    public static func parse(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        for format in ["yyyy-MM-dd HH:mm:ss 'UTC'", "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss ZZZZZ", "yyyy-MM-dd HH:mm 'UTC'", "yyyy-MM-dd HH:mm Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withFullDate]
        return iso.date(from: value)
    }
}
