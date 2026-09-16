// OAuth1Signer.swift
//
// HMAC-SHA1 OAuth1 request signing, ported field-for-field from the
// confirmed-working Node reference implementation at
// `tools/lib/garmin-auth.mjs` (functions `pctEncode`, `oauth1Header`,
// `getConsumer`). Do not "improve" the algorithm — Garmin's server accepts
// exactly this construction as of 2026-09-14, and any deviation (different
// percent-encoding rules, different parameter ordering, a different key
// construction) will produce a signature Garmin silently rejects with a 401.
//
// That rule still holds, and this file still reproduces the reference
// byte-for-byte for the shape the reference was actually exercised against:
// a query-less URL signed with a real token. `OAuth1SignerTests` pins exactly
// that vector. Two additions (2026-09-16) apply only to shapes the reference
// never saw, because until the browser bootstrap landed nothing in this
// project signed them: a URL carrying a QUERY STRING, and a request made
// before any user token exists. For those, RFC 5849 3.4.1.2/3.4.1.3.1 govern
// -- the query leaves the base string URI and joins the signed parameters,
// and an absent token is omitted rather than signed as empty. Both are
// no-ops for the confirmed route. `tools/lib/garmin-auth.mjs` has the same
// two gaps; it has never signed a query-bearing URL either, so it is
// latently, not actively, wrong -- fix it there before giving it one.
//
// Reference (`tools/lib/garmin-auth.mjs`) for comparison:
//
//     function pctEncode(s) {
//         return encodeURIComponent(s).replace(/[!'()*]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
//     }
//
//     function oauth1Header(method, url, consumer, token, tokenSecret) {
//         const params = {
//             oauth_consumer_key: consumer.consumer_key,
//             oauth_token: token,
//             oauth_nonce: randomBytes(16).toString('hex'),
//             oauth_timestamp: String(Math.floor(Date.now() / 1000)),
//             oauth_signature_method: 'HMAC-SHA1',
//             oauth_version: '1.0',
//         };
//         const paramStr = Object.keys(params).sort()
//             .map(k => `${pctEncode(k)}=${pctEncode(params[k])}`).join('&');
//         const base = [method.toUpperCase(), pctEncode(url), pctEncode(paramStr)].join('&');
//         const key = `${pctEncode(consumer.consumer_secret)}&${pctEncode(tokenSecret)}`;
//         params.oauth_signature = createHmac('sha1', key).update(base).digest('base64');
//         return 'OAuth ' + Object.keys(params).sort()
//             .map(k => `${pctEncode(k)}="${pctEncode(params[k])}"`).join(', ');
//     }

import Foundation
import CryptoKit
import Security

/// RFC 3986 percent-encoding, exactly as OAuth1 (RFC 5849 §3.6) requires it.
///
/// JavaScript's `encodeURIComponent` leaves five characters unescaped that
/// RFC 3986 does *not* consider "unreserved" — `! ' ( ) *` — which is why the
/// Node reference follows it with a second pass that force-encodes exactly
/// those five. Rather than port that two-pass shape literally, this
/// implementation encodes directly against the RFC 3986 unreserved set
/// (`A-Z a-z 0-9 - _ . ~`) in one pass. For every input the two approaches
/// are byte-for-byte identical — encoding is done per UTF-8 byte, uppercase
/// hex, so multi-byte characters (e.g. "café") encode each byte separately,
/// matching the Node reference exactly.
enum OAuth1PercentEncoding {
    /// ALPHA / DIGIT / "-" / "." / "_" / "~" — RFC 5849 §3.6's unreserved set.
    private static let unreservedASCII: Set<UInt8> = {
        var set = Set<UInt8>()
        set.formUnion(UInt8(ascii: "A")...UInt8(ascii: "Z"))
        set.formUnion(UInt8(ascii: "a")...UInt8(ascii: "z"))
        set.formUnion(UInt8(ascii: "0")...UInt8(ascii: "9"))
        set.insert(UInt8(ascii: "-"))
        set.insert(UInt8(ascii: "."))
        set.insert(UInt8(ascii: "_"))
        set.insert(UInt8(ascii: "~"))
        return set
    }()

    private static let hexDigits: [Character] = Array("0123456789ABCDEF")

    static func encode(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.utf8.count)
        for byte in string.utf8 {
            if unreservedASCII.contains(byte) {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result.append("%")
                result.append(hexDigits[Int(byte >> 4)])
                result.append(hexDigits[Int(byte & 0x0F)])
            }
        }
        return result
    }
}

/// Public because it's part of the thrown-error surface of `TokenProvider`'s
/// and `GarminClient`'s public API -- a consumer outside this package must
/// be able to `catch GarminAuthError.longLivedTokenExpired` by name (which
/// is exactly what `GarminAuthState.report(_:)` does from within this same
/// package, and what app-layer code is free to do too).
public enum GarminAuthError: Error, Equatable, Sendable {
    /// The consumer-key bootstrap fetch (`thegarth.s3.amazonaws.com/oauth_consumer.json`)
    /// failed or returned an unparseable body.
    case consumerKeyFetchFailed(statusCode: Int?)
    /// The OAuth1→OAuth2 exchange returned 401 — the long-lived OAuth1 token
    /// itself has expired (they last roughly a year) and the user must
    /// re-run the browser bootstrap (D2). Per D7, this is the ONE condition
    /// that must surface loudly as "sign in again" — never swallowed, never
    /// reported as "no data".
    case longLivedTokenExpired
    /// The exchange failed for a reason other than 401 — network error,
    /// 5xx, malformed response. Distinct from `longLivedTokenExpired` on
    /// purpose: per D7 / spec's "a route is merely unavailable, not an auth
    /// failure" scenario, this must NOT be presented as "sign in again".
    case exchangeFailed(statusCode: Int?, message: String)
    /// No OAuth1 token is stored at all — the user has never connected
    /// Garmin from this process (D3: each process bootstraps independently).
    case notSignedIn
}

/// Garmin's public OAuth1 consumer key/secret pair, and the HMAC-SHA1
/// request signer built on top of it.
enum OAuth1Signer {
    struct Consumer: Codable, Sendable, Equatable {
        let consumerKey: String
        let consumerSecret: String

        enum CodingKeys: String, CodingKey {
            case consumerKey = "consumer_key"
            case consumerSecret = "consumer_secret"
        }
    }

    /// Fetches (and memoizes for the lifetime of the process) Garmin's
    /// public OAuth1 consumer key/secret pair from the same URL the Node
    /// reference uses. This is not a secret specific to any one user —
    /// every open-source Garmin Connect client (garth, python-garminconnect)
    /// fetches the same publicly-hosted file — but it is fetched at runtime
    /// rather than hardcoded, so a Garmin-side rotation doesn't require an
    /// app update, matching the reference implementation's behavior.
    static func fetchConsumer(session: URLSession = .shared) async throws -> Consumer {
        try await ConsumerCredentialCache.shared.consumer(session: session)
    }

    /// Builds the `Authorization: OAuth ...` header value for one request.
    ///
    /// `nonce` and `timestamp` default to fresh random/current values on
    /// every call, matching the Node reference's per-request freshness —
    /// they are exposed as parameters purely so unit tests can pin them to
    /// known-good vectors without needing to intercept `Date()` or
    /// `SecRandomCopyBytes`.
    static func authorizationHeader(
        method: String,
        url: String,
        consumer: Consumer,
        token: String,
        tokenSecret: String,
        nonce: String = OAuth1Signer.randomNonce(),
        timestamp: String = String(Int(Date().timeIntervalSince1970))
    ) -> String {
        var params: [String: String] = [
            "oauth_consumer_key": consumer.consumerKey,
            "oauth_nonce": nonce,
            "oauth_timestamp": timestamp,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_version": "1.0",
        ]
        // RFC 5849 3.4.1.3.1: a token that doesn't exist yet is omitted from
        // the signature, not signed as an empty `oauth_token=`. Only the
        // bootstrap (GarminAuthSession's `preauthorized` call, which exists to
        // establish that token in the first place) passes an empty token; the
        // OAuth1->OAuth2 exchange always has a real one, so its signature is
        // byte-for-byte unchanged by this branch.
        if !token.isEmpty {
            params["oauth_token"] = token
        }

        // RFC 5849 3.4.1.2 + 3.4.1.3.1: the base string URI excludes the
        // query, and the query's parameters are signed alongside the oauth_*
        // ones. The Node reference this was ported from signs the full URL and
        // no query parameters at all -- indistinguishable from correct for a
        // query-less URL, which is all it was ever exercised against. The
        // bootstrap's `preauthorized` call is the first signed request here to
        // carry a query string (`ticket`, `login-url`, ...), and Garmin
        // recomputes the signature server-side over those parameters, so
        // omitting them could only ever produce a mismatch.
        //
        // This is deliberately ALL-OR-NOTHING. A parameter may only move into
        // the signed set if the base string URI actually lost it; folding the
        // query in while leaving it on the URI counts every parameter twice,
        // which is its own guaranteed mismatch. So if the URI cannot be
        // stripped, nothing is folded and the old (reference-identical)
        // behavior stands.
        var signedPairs: [(String, String)] = []
        signedPairs.reserveCapacity(params.count)
        for (name, value) in params {
            signedPairs.append((name, value))
        }
        var signatureURL = url
        if let components = URLComponents(string: url) {
            var withoutQuery = components
            withoutQuery.queryItems = nil
            withoutQuery.fragment = nil
            if let stripped = withoutQuery.url?.absoluteString {
                signatureURL = stripped
                for item in components.queryItems ?? [] {
                    // A query parameter named `oauth_*` would otherwise
                    // replace the value the Authorization header still
                    // advertises below -- signing one nonce and sending
                    // another, which is a 401 with no diagnosable symptom.
                    guard params[item.name] == nil else { continue }
                    signedPairs.append((item.name, item.value ?? ""))
                }
            }
        }

        // Signature base string: METHOD & pctEncode(url) & pctEncode(sorted param string).
        // RFC 5849 3.4.1.3.2 sorts by encoded name and then by encoded value,
        // which preserves repeated names instead of collapsing them the way a
        // dictionary would. For the oauth_* keys, encoding is the identity and
        // names are unique, so this orders them exactly as before.
        // Written out rather than chained: the fluent
        // map/sorted/map/joined version over tuples defeats Swift's type
        // checker outright ("unable to type-check this expression in
        // reasonable time"), which is a build failure, not a slow build.
        var encodedPairs: [(name: String, value: String)] = []
        encodedPairs.reserveCapacity(signedPairs.count)
        for pair in signedPairs {
            let name = OAuth1PercentEncoding.encode(pair.0)
            let value = OAuth1PercentEncoding.encode(pair.1)
            encodedPairs.append((name: name, value: value))
        }
        encodedPairs.sort { lhs, rhs in
            lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name
        }

        var paramString = ""
        for (index, pair) in encodedPairs.enumerated() {
            if index > 0 { paramString += "&" }
            paramString += pair.name + "=" + pair.value
        }

        let baseString = [
            method.uppercased(),
            OAuth1PercentEncoding.encode(signatureURL),
            OAuth1PercentEncoding.encode(paramString),
        ].joined(separator: "&")

        // Signing key: pctEncode(consumerSecret) & pctEncode(tokenSecret).
        // Note the '&' is literal, not itself percent-encoded — matches the
        // Node reference's template-string construction exactly.
        let signingKey = "\(OAuth1PercentEncoding.encode(consumer.consumerSecret))&\(OAuth1PercentEncoding.encode(tokenSecret))"

        params["oauth_signature"] = hmacSHA1Base64(message: baseString, key: signingKey)

        let headerParams = params.keys.sorted()
            .map { "\(OAuth1PercentEncoding.encode($0))=\"\(OAuth1PercentEncoding.encode(params[$0]!))\"" }
            .joined(separator: ", ")

        return "OAuth \(headerParams)"
    }

    /// 16 random bytes, hex-encoded lowercase — matches
    /// `randomBytes(16).toString('hex')` in the Node reference exactly
    /// (32 lowercase hex characters).
    static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // SecRandomCopyBytes failing is effectively unheard-of on iOS, but
        // fall back to a still-random (if lower-quality) source rather than
        // producing a fixed nonce, which would be a genuine security bug
        // (nonce reuse breaks OAuth1's replay protection).
        if status != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacSHA1Base64(message: String, key: String) -> String {
        let symmetricKey = SymmetricKey(data: Data(key.utf8))
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(message.utf8), using: symmetricKey)
        return Data(mac).base64EncodedString()
    }
}

/// In-memory-only cache for the fetched consumer credential. An actor so
/// concurrent callers from different tasks don't trigger duplicate fetches
/// and don't race on the cached value — this is per-process state (D3/D4:
/// nothing here is shared across processes, so no Keychain or cross-process
/// coordination is needed for it, only in-process thread-safety).
actor ConsumerCredentialCache {
    static let shared = ConsumerCredentialCache()

    private var cached: OAuth1Signer.Consumer?
    private static let url = URL(string: "https://thegarth.s3.amazonaws.com/oauth_consumer.json")!

    func consumer(session: URLSession) async throws -> OAuth1Signer.Consumer {
        if let cached { return cached }

        let (data, response) = try await session.data(from: Self.url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode
            throw GarminAuthError.consumerKeyFetchFailed(statusCode: status)
        }
        let consumer = try JSONDecoder().decode(OAuth1Signer.Consumer.self, from: data)
        cached = consumer
        return consumer
    }
}
