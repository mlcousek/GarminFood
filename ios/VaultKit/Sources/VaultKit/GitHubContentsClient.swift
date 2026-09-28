// GitHubContentsClient.swift
//
// The only type in this app that builds a request to GitHub
// (add-vault-connection design D2, D4, D6). Three calls, all against
// `https://api.github.com`:
//
//   getRepository  GET  /repos/{owner}/{repo}
//   getFile        GET  /repos/{owner}/{repo}/contents/{hubRoot}/{path}?ref={branch}
//                       Accept: application/vnd.github.raw+json, If-None-Match
//   createFile     PUT  /repos/{owner}/{repo}/contents/{hubRoot}/{path}
//                       {"message", "content" (base64), "branch"} and NO `sha`,
//                       which makes it create-only (422 if the path exists)
//
// Rules it enforces, so no caller can get around them:
//   - `VaultPathPolicy` is checked BEFORE anything else; a refused path
//     sends nothing, returns `.refusedByPolicy` and logs an error. No
//     public API accepts a full repository path -- only a `HubPath`, to
//     which this type prefixes `VaultHub.root`.
//   - Host fixed to api.github.com. A redirect to any other host is refused
//     in the session delegate, so the `Authorization` header can never
//     follow it; a same-host redirect (a renamed repository) is followed
//     with the original headers.
//   - Ephemeral session, `urlCache = nil`, no cookies: the only copy of a
//     response is the one ConditionalFileSync keeps. 20 s timeout.
//   - `X-GitHub-Api-Version: 2022-11-28`; `Authorization: Bearer <token>`,
//     built per request from the credentials provider and never stored.
//   - Logs (category `vault`) carry the method, hub-relative path, status
//     and byte count -- never the token, owner, repository name, URL or a
//     raw error description (see VaultLog.swift's header).
//
// Credentials and the policy are PROVIDERS, read per request: the token can
// be replaced in Settings and the device id appears on the first successful
// test, and neither should require rebuilding the client.
//
// Depended on by: GitHubVaultTransport. Tests: GitHubContentsClientTests
// (every status through a URLProtocol stub), RedactionTests.

import Foundation
import GarminKit

/// What a request needs to be built. Read per request, never cached.
public struct VaultCredentials: Sendable {
    public let repository: VaultRepository
    public let token: VaultToken

    public init(repository: VaultRepository, token: VaultToken) {
        self.repository = repository
        self.token = token
    }
}

public struct VaultRepositoryResult: Equatable, Sendable {
    public let outcome: VaultOutcome
    public let tokenExpiresAt: Date?

    public init(_ outcome: VaultOutcome, tokenExpiresAt: Date? = nil) {
        self.outcome = outcome
        self.tokenExpiresAt = tokenExpiresAt
    }
}

/// The contents-API calls VaultKit makes (design D1).
public protocol GitHubContentsAPI: Sendable {
    func getRepository() async -> VaultRepositoryResult
    func getFile(_ path: HubPath, ifNoneMatch: String?) async -> VaultFetchResult
    func createFile(_ path: HubPath, bytes: Data, message: String) async -> VaultWriteResult
}

public final class GitHubContentsClient: GitHubContentsAPI, @unchecked Sendable {
    public static let host = "api.github.com"
    public static let apiVersion = "2022-11-28"
    public static let defaultTimeout: TimeInterval = 20
    static let rawMediaType = "application/vnd.github.raw+json"
    static let jsonMediaType = "application/vnd.github+json"
    static let userAgent = "GarminFood-VaultKit"

    private let session: URLSession
    private let credentials: @Sendable () async -> VaultCredentials?
    private let policy: @Sendable () async -> VaultPathPolicy
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - configuration: `nil` for the production configuration
    ///     (`makeSessionConfiguration`); tests pass one whose
    ///     `protocolClasses` holds a stub.
    ///   - credentials: the repository and token, read per request; `nil`
    ///     means "not configured" and nothing is sent.
    ///   - policy: the path allow-lists, read per request.
    public init(
        configuration: URLSessionConfiguration? = nil,
        timeout: TimeInterval = GitHubContentsClient.defaultTimeout,
        credentials: @escaping @Sendable () async -> VaultCredentials?,
        policy: @escaping @Sendable () async -> VaultPathPolicy,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let configuration = configuration ?? Self.makeSessionConfiguration()
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = timeout
        self.session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
        self.credentials = credentials
        self.policy = policy
        self.now = now
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// Ephemeral: no disk cache, no cookie jar, no credential storage.
    public static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCredentialStorage = nil
        return configuration
    }

    // MARK: - Calls

    public func getRepository() async -> VaultRepositoryResult {
        guard let credentials = await credentials() else {
            return VaultRepositoryResult(.notConfigured)
        }
        let request = makeRequest(method: "GET", path: Self.repositoryPath(credentials.repository), query: nil, accept: Self.jsonMediaType, credentials: credentials)
        let response = await send(request, kind: .repository, logPath: "(repository)")
        return VaultRepositoryResult(response.outcome, tokenExpiresAt: response.tokenExpiresAt)
    }

    public func getFile(_ path: HubPath, ifNoneMatch: String?) async -> VaultFetchResult {
        guard await policy().allowsRead(path) else {
            VaultLog.log(.error, "GET \(path.rawValue) refused by the path policy; nothing sent")
            return VaultFetchResult(.failed(.refusedByPolicy))
        }
        guard let credentials = await credentials() else {
            return VaultFetchResult(.failed(.notConfigured))
        }
        var request = makeRequest(
            method: "GET",
            path: Self.contentsPath(credentials.repository, path),
            query: [URLQueryItem(name: "ref", value: credentials.repository.branch)],
            accept: Self.rawMediaType,
            credentials: credentials
        )
        if let ifNoneMatch, !ifNoneMatch.isEmpty {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }
        let response = await send(request, kind: .file, logPath: path.rawValue)
        switch response.outcome {
        case .success where response.status == 304:
            return VaultFetchResult(.notModified, tokenExpiresAt: response.tokenExpiresAt)
        case .success:
            return VaultFetchResult(.fetched(bytes: response.body, etag: response.etag), tokenExpiresAt: response.tokenExpiresAt)
        default:
            return VaultFetchResult(.failed(response.outcome), tokenExpiresAt: response.tokenExpiresAt)
        }
    }

    public func createFile(_ path: HubPath, bytes: Data, message: String) async -> VaultWriteResult {
        guard await policy().allowsWrite(path) else {
            VaultLog.log(.error, "PUT \(path.rawValue) refused by the path policy; nothing sent")
            return VaultWriteResult(.failed(.refusedByPolicy))
        }
        guard let credentials = await credentials() else {
            return VaultWriteResult(.failed(.notConfigured))
        }
        var request = makeRequest(
            method: "PUT",
            path: Self.contentsPath(credentials.repository, path),
            query: nil,
            accept: Self.jsonMediaType,
            credentials: credentials
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.createBody(bytes: bytes, message: message, branch: credentials.repository.branch)
        let response = await send(request, kind: .create, logPath: path.rawValue)
        switch response.outcome {
        case .success: return VaultWriteResult(.created, tokenExpiresAt: response.tokenExpiresAt)
        case .alreadyExists: return VaultWriteResult(.alreadyExists, tokenExpiresAt: response.tokenExpiresAt)
        default: return VaultWriteResult(.failed(response.outcome), tokenExpiresAt: response.tokenExpiresAt)
        }
    }

    // MARK: - Request building (pure, tested)

    static func repositoryPath(_ repository: VaultRepository) -> String {
        "/repos/\(repository.owner)/\(repository.name)"
    }

    static func contentsPath(_ repository: VaultRepository, _ path: HubPath) -> String {
        "\(repositoryPath(repository))/contents/\(VaultHub.root)/\(path.rawValue)"
    }

    /// `{"branch", "content", "message"}` -- no `sha`, so GitHub creates or
    /// refuses with 422, never overwrites.
    static func createBody(bytes: Data, message: String, branch: String) -> Data {
        let body: [String: String] = [
            "message": message,
            "content": bytes.base64EncodedString(),
            "branch": branch
        ]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    private func makeRequest(method: String, path: String, query: [URLQueryItem]?, accept: String, credentials: VaultCredentials) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        // Every component was validated to `[A-Za-z0-9._/-]`
        // (VaultRepository, HubPath, VaultHub.root), so it needs no encoding.
        components.percentEncodedPath = path
        components.queryItems = query
        // A URL can't fail to build from these parts; the fallback keeps the
        // host fixed even if it somehow did.
        let url = components.url ?? URL(string: "https://\(Self.host)/")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: session.configuration.timeoutIntervalForRequest)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(credentials.token.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Sending

    private struct Response {
        var outcome: VaultOutcome
        var status: Int
        var body: Data
        var etag: String?
        var tokenExpiresAt: Date?
    }

    private func send(_ request: URLRequest, kind: VaultOutcome.RequestKind, logPath: String) async -> Response {
        let method = request.httpMethod ?? "GET"
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            let outcome = VaultOutcome.classify(error: error)
            VaultLog.log(outcome == .offline ? .info : .warning, "\(method) \(logPath): \(outcome.logLabel)")
            return Response(outcome: outcome, status: 0, body: Data(), etag: nil, tokenExpiresAt: nil)
        }
        let (data, urlResponse) = result
        guard let http = urlResponse as? HTTPURLResponse else {
            VaultLog.log(.error, "\(method) \(logPath): not an HTTP response")
            return Response(outcome: .transportError(code: 0), status: 0, body: Data(), etag: nil, tokenExpiresAt: nil)
        }
        let headers = VaultResponseHeaders(http)
        // Belt and braces: whatever URLSession did, a response that did not
        // come from api.github.com is never trusted.
        if http.url?.host?.lowercased() != Self.host {
            VaultLog.log(.error, "\(method) \(logPath): answer came from another host; ignored")
            return Response(outcome: .redirectRefused, status: http.statusCode, body: Data(), etag: nil, tokenExpiresAt: nil)
        }
        let outcome = VaultOutcome.classify(status: http.statusCode, headers: headers, kind: kind, now: now())
        let level: DiagnosticsLevel
        if outcome.isLoud || outcome == .redirectRefused {
            level = .error
        } else if outcome.isSuccess || outcome == .fileNotFound || outcome == .alreadyExists {
            level = .info
        } else {
            level = .warning
        }
        VaultLog.log(level, "\(method) \(logPath): \(http.statusCode) \(outcome.logLabel), \(data.count) bytes")
        return Response(
            outcome: outcome,
            status: http.statusCode,
            body: outcome.isSuccess ? data : Data(),
            etag: headers["etag"],
            tokenExpiresAt: headers.tokenExpiresAt
        )
    }
}

/// Refuses redirects that leave api.github.com (design D2).
final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(Self.redirect(from: task.originalRequest, to: request))
    }

    /// The request to follow, or `nil` to refuse. Pure, so it is tested
    /// directly. Same-host https redirects are followed WITH the original
    /// headers (so `Authorization` and `Accept` stay what we set); anything
    /// else is refused and logged.
    static func redirect(from original: URLRequest?, to proposed: URLRequest) -> URLRequest? {
        guard proposed.url?.scheme?.lowercased() == "https",
              proposed.url?.host?.lowercased() == GitHubContentsClient.host
        else {
            VaultLog.log(.error, "redirect to another host refused; the token was not sent there")
            return nil
        }
        var followed = proposed
        for (name, value) in original?.allHTTPHeaderFields ?? [:] {
            followed.setValue(value, forHTTPHeaderField: name)
        }
        return followed
    }
}
