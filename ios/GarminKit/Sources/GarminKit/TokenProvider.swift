// TokenProvider.swift
//
// Holds OAuth1 (long-lived, ~1 year) and OAuth2 (short-lived, ~24h) Garmin
// tokens in this process's own Keychain, and exchanges OAuth1 -> OAuth2 via
// the confirmed-working route (`POST /oauth-service/oauth/exchange/user/2.0`,
// design.md context section, verified 2026-09-14: a token valid 88227s).
//
// Storage uses this app's own DEFAULT Keychain access group -- deliberately
// no `kSecAttrAccessGroup` entry in the query dictionaries below. Task 6.4
// confirmed a custom `keychain-access-groups` entitlement is not actually
// granted by AltStore's free-tier signing (`errSecMissingEntitlement` /
// -34018, on both read and write, symmetric across app and widget). Per
// design.md D3/D4, there is therefore nothing to share and nothing to lock:
// every process that needs Garmin auth (the app, a widget extension, a
// future Control) runs its own independent bootstrap (GarminAuthSession)
// and keeps its own tokens in its own default Keychain access group, which
// Apple grants to every app/extension automatically without any
// entitlement at all.
//
// `kSecAttrAccessibleAfterFirstUnlock` (not `.whenUnlocked`) is used so a
// background drain (design.md D6/D8) can read the token and refresh it
// before the user has unlocked the phone that session.

import Foundation
import Security

// MARK: - Token models

/// The long-lived credential obtained once via the browser bootstrap
/// (GarminAuthSession, design.md D2). Field names mirror the Node
/// reference's `oauth1.oauth_token` / `oauth1.oauth_token_secret` shape.
public struct GarminOAuth1Token: Codable, Sendable, Equatable {
    public let oauthToken: String
    public let oauthTokenSecret: String

    public init(oauthToken: String, oauthTokenSecret: String) {
        self.oauthToken = oauthToken
        self.oauthTokenSecret = oauthTokenSecret
    }

    enum CodingKeys: String, CodingKey {
        case oauthToken = "oauth_token"
        case oauthTokenSecret = "oauth_token_secret"
    }
}

/// The short-lived access token minted from the OAuth1 token, with the
/// client-computed expiry timestamp attached at receipt time (Garmin's
/// response carries only `expires_in`, a duration, not an absolute time).
public struct GarminOAuth2Token: Codable, Sendable, Equatable {
    public let accessToken: String
    /// Unix seconds.
    public let expiresAt: TimeInterval
    public let tokenType: String?

    public init(accessToken: String, expiresAt: TimeInterval, tokenType: String?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
    }

    /// True when fewer than five minutes of validity remain. Matches the
    /// Node reference's `Date.now() / 1000 < expires_at - 300` cadence
    /// exactly, and the garmin-auth spec's "within five minutes of expiry"
    /// scenario.
    public func isNearExpiry(now: Date = Date()) -> Bool {
        now.timeIntervalSince1970 >= expiresAt - 300
    }
}

/// Raw decode shape of Garmin's exchange response. `expires_in` was
/// observed as 88227 (~24.5h) on 2026-09-14. Other fields Garmin may include
/// (`scope`, `refresh_token`, `jti`) are intentionally not modeled: this
/// design re-mints the OAuth2 token from the OAuth1 token each time it's
/// near expiry rather than using a refresh-token flow, matching the proven
/// Node reference rather than inventing an unconfirmed refresh path.
private struct GarminOAuth2ExchangeResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Keychain storage

enum GarminKeychainError: Error {
    case writeFailed(status: OSStatus)
    case readFailed(status: OSStatus)
}

/// Thin wrapper around `SecItem*`. Deliberately does not set
/// `kSecAttrAccessGroup` -- see the file header comment.
struct KeychainStore: Sendable {
    private let service: String

    enum Account: String {
        case oauth1 = "garmin.oauth1"
        case oauth2 = "garmin.oauth2"
    }

    init(service: String = "com.mlcousek.garminfood.garminkit") {
        self.service = service
    }

    func save(_ data: Data, account: Account) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        // Clear any stale value first so this is an upsert, not an
        // add-that-fails-on-conflict. Ignore the delete's own result --
        // "nothing to delete" is not an error here.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GarminKeychainError.writeFailed(status: status)
        }
    }

    func load(account: Account) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GarminKeychainError.readFailed(status: status)
        }
        return data
    }

    func delete(account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - TokenProvider

/// Per-process token holder and refresher. An actor: all mutable state
/// (the in-memory OAuth2 cache) is isolated to this process's own instance,
/// which is exactly right per design.md D4 -- there is no cross-process
/// state to coordinate, only in-process concurrent callers (e.g. two
/// screens both needing a token at once) to serialize safely.
public actor TokenProvider {
    public static let shared = TokenProvider()

    private let keychain: KeychainStore
    private let urlSession: URLSession
    private let baseURL: String

    private var cachedOAuth2: GarminOAuth2Token?

    public init(
        keychain: KeychainStore = KeychainStore(),
        urlSession: URLSession = .shared,
        baseURL: String = GarminAPI.connectAPI
    ) {
        self.keychain = keychain
        self.urlSession = urlSession
        self.baseURL = baseURL
    }

    // MARK: OAuth1 (long-lived)

    /// Called once, at the end of the browser bootstrap (GarminAuthSession).
    public func storeOAuth1Token(_ token: GarminOAuth1Token) throws {
        let data = try JSONEncoder().encode(token)
        try keychain.save(data, account: .oauth1)
        // A brand-new OAuth1 token (e.g. after re-bootstrapping post-expiry)
        // invalidates any cached OAuth2 token minted from the *previous*
        // OAuth1 token.
        cachedOAuth2 = nil
        keychain.delete(account: .oauth2)
    }

    public func loadOAuth1Token() throws -> GarminOAuth1Token? {
        guard let data = try keychain.load(account: .oauth1) else { return nil }
        return try JSONDecoder().decode(GarminOAuth1Token.self, from: data)
    }

    public var isSignedIn: Bool {
        get throws {
            try loadOAuth1Token() != nil
        }
    }

    /// Clears both tokens. Does not touch the outbox -- entries keep
    /// accumulating locally while signed out and drain once the session is
    /// restored (garmin-sync spec, garmin-auth spec's degraded-state rules).
    public func signOut() {
        cachedOAuth2 = nil
        keychain.delete(account: .oauth1)
        keychain.delete(account: .oauth2)
    }

    // MARK: OAuth2 (short-lived, ~24h)

    /// Returns a valid OAuth2 access token, exchanging a fresh one only if
    /// the cached token is missing or within five minutes of expiry.
    ///
    /// Throws `GarminAuthError.notSignedIn` if no OAuth1 token exists yet in
    /// this process, and `GarminAuthError.longLivedTokenExpired` if the
    /// exchange itself returns 401 -- the one condition design.md D7
    /// requires to surface loudly, never as "no data available".
    public func accessToken(now: Date = Date()) async throws -> String {
        if let cached = try currentOAuth2Token(), !cached.isNearExpiry(now: now) {
            return cached.accessToken
        }
        return try await refreshAccessToken().accessToken
    }

    private func currentOAuth2Token() throws -> GarminOAuth2Token? {
        if let cachedOAuth2 { return cachedOAuth2 }
        guard let data = try keychain.load(account: .oauth2) else { return nil }
        let token = try JSONDecoder().decode(GarminOAuth2Token.self, from: data)
        cachedOAuth2 = token
        return token
    }

    /// Forces a fresh OAuth1 -> OAuth2 exchange, regardless of the cached
    /// token's remaining validity.
    ///
    /// No cross-process lock (design.md D4, revised after task 6.4's
    /// negative result): there is no shared Keychain group on this account,
    /// so there is no shared credential for a second process to race
    /// against in the first place. Two processes refreshing "at the same
    /// moment" are refreshing two *different* OAuth1 tokens from two
    /// *different* independent bootstraps -- harmless by construction, not
    /// because it's been carefully synchronized.
    @discardableResult
    public func refreshAccessToken() async throws -> GarminOAuth2Token {
        guard let oauth1 = try loadOAuth1Token() else {
            throw GarminAuthError.notSignedIn
        }

        let consumer = try await OAuth1Signer.fetchConsumer(session: urlSession)
        let urlString = "\(baseURL)/oauth-service/oauth/exchange/user/2.0"
        guard let url = URL(string: urlString) else {
            throw GarminAuthError.exchangeFailed(statusCode: nil, message: "Invalid exchange URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(GarminUserAgent.value, forHTTPHeaderField: "User-Agent")
        request.setValue(
            OAuth1Signer.authorizationHeader(
                method: "POST",
                url: urlString,
                consumer: consumer,
                token: oauth1.oauthToken,
                tokenSecret: oauth1.oauthTokenSecret
            ),
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GarminAuthError.exchangeFailed(statusCode: nil, message: "No HTTP response")
        }

        // The one loud case -- see design.md D7 and the file header comment.
        if http.statusCode == 401 {
            throw GarminAuthError.longLivedTokenExpired
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? ""
            throw GarminAuthError.exchangeFailed(statusCode: http.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(GarminOAuth2ExchangeResponse.self, from: data)
        let token = GarminOAuth2Token(
            accessToken: decoded.accessToken,
            expiresAt: Date().timeIntervalSince1970 + Double(decoded.expiresIn),
            tokenType: decoded.tokenType
        )

        cachedOAuth2 = token
        try keychain.save(try JSONEncoder().encode(token), account: .oauth2)
        return token
    }
}
