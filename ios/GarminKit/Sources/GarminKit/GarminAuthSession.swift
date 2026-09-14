// GarminAuthSession.swift
//
// The browser-based bootstrap (design.md D2): the user taps "Connect
// Garmin", `ASWebAuthenticationSession` opens Garmin's real sign-in page
// (Safari's own networking stack and TLS fingerprint -- not a `WKWebView`,
// which doesn't share Safari's cookie jar and is more fingerprintable as
// automation), and on success the app captures a service ticket from the
// redirect and exchanges it for the long-lived OAuth1 token.
//
// =====================================================================
// READ THIS BEFORE TOUCHING ANYTHING BELOW: GENUINELY UNVERIFIED TERRITORY
// =====================================================================
//
// Confirmed, live, elsewhere in this project:
//   - Garmin's SSO sign-in endpoints sit behind Cloudflare bot protection
//     as of March 2026 (design.md Context) -- a scripted credential POST
//     to `oauth-service/oauth/preauthorized` gets 401.
//   - The OAuth1 -> OAuth2 EXCHANGE (once an OAuth1 token already exists)
//     works (TokenProvider.swift, `POST /oauth-service/oauth/exchange/user/2.0`).
//
// NOT confirmed, anywhere, by this project's own testing:
//   - The exact URL of Garmin's mobile SSO sign-in page.
//   - Whether Garmin's redirect will honor a custom URL scheme callback at
//     all (`ASWebAuthenticationSession` requires either that or a universal
//     link) -- this is design.md's single biggest named risk for this file:
//     "The redirect URL or ticket parameter changes -> bootstrap breaks
//     while existing tokens keep working, so the failure appears months
//     later at re-auth time, which is the worst possible moment."
//   - The exact query parameter name carrying the resulting service ticket.
//   - Whether a service ticket obtained this way is even exchangeable for
//     an OAuth1 token at all, versus only for a different (DI OAuth2,
//     ~30-day-refresh) token entirely -- this is design.md's Open Question 1,
//     explicitly still open.
//   - The exact shape of the ticket -> OAuth1 exchange request/response
//     below (`exchangeTicket`). It is modeled on the publicly-documented
//     behavior of community tooling (garth's `preauthorized` step: a GET
//     to `oauth-service/oauth/preauthorized` carrying the ticket, OAuth1-signed
//     with the consumer key/secret and an empty token, returning
//     `oauth_token`/`oauth_token_secret` as a query string) -- NOT observed
//     working against this project's own account. This is a best-effort
//     port of prior art, not a verified route.
//
// Every constant below that encodes a guess is marked UNCONFIRMED in its
// own doc comment. When task 8.1-8.3 actually runs this against a real
// device and a real sign-in, update docs/garmin-routes.json's `auth`
// section with whatever the real redirect/parameter/response turns out to
// be, with a `lastVerified` date, matching this repo's existing convention
// for every other route in that file. Do not quietly leave this comment
// stale once that happens.

import Foundation
import AuthenticationServices

/// Best-effort, UNCONFIRMED constants for the browser bootstrap. See this
/// file's header comment.
public enum GarminSSOEndpoints {
    /// Garmin's mobile SSO sign-in page, parameterized the way Garmin
    /// Connect's own web sign-in flow and known community tooling (garth,
    /// python-garminconnect) construct it for a native-app embedded
    /// browser. UNCONFIRMED by this project's own testing -- see header.
    public static let signInURL: URL = {
        var components = URLComponents(string: "https://sso.garmin.com/sso/signin")!
        components.queryItems = [
            URLQueryItem(name: "service", value: "https://connect.garmin.com/modern"),
            URLQueryItem(name: "webhost", value: "https://connect.garmin.com"),
            URLQueryItem(name: "source", value: "https://connect.garmin.com/signin"),
            URLQueryItem(name: "redirectAfterAccountLoginUrl", value: "https://connect.garmin.com/modern"),
            URLQueryItem(name: "redirectAfterAccountCreationUrl", value: "https://connect.garmin.com/modern"),
            URLQueryItem(name: "gauthHost", value: "https://sso.garmin.com/sso"),
            URLQueryItem(name: "locale", value: "en_US"),
            URLQueryItem(name: "id", value: "gauth-widget"),
            URLQueryItem(name: "clientId", value: "GarminConnect"),
            URLQueryItem(name: "consumeServiceTicket", value: "false"),
            URLQueryItem(name: "generateExtraServiceTicket", value: "true"),
            URLQueryItem(name: "generateNoServiceTicket", value: "false"),
            URLQueryItem(name: "mobile", value: "false"),
        ]
        return components.url!
    }()

    /// The custom URL scheme the app would need to register
    /// (`CFBundleURLTypes` in the app target's Info.plist -- a LATER
    /// phase's job, not this package's) for `ASWebAuthenticationSession`
    /// to detect completion. UNCONFIRMED whether Garmin's redirect actually
    /// supports a custom scheme versus requiring a universal link.
    public static let callbackURLScheme = "garminfood"

    /// Best-effort guess at the query parameter carrying the resulting
    /// service ticket, following the CAS-protocol convention ("ticket=...")
    /// Garmin's SSO is known to be built on. UNCONFIRMED.
    public static let ticketQueryParameterName = "ticket"

    /// The GET route community tooling (garth) uses to exchange a ticket
    /// for an OAuth1 token pair. UNCONFIRMED against this project's own
    /// account -- see header comment.
    public static let preauthorizedPath = "/oauth-service/oauth/preauthorized"
}

public enum GarminBootstrapError: Error {
    case cancelled
    case missingCallbackURL
    case missingTicket
    case sessionFailed(Error)
    case exchangeFailed(statusCode: Int?, body: String?)
    case malformedExchangeResponse
}

/// Runs the browser-based bootstrap (or the manual-ticket-paste fallback)
/// and, on success, stores the resulting OAuth1 token via `TokenProvider`.
///
/// `@MainActor` because `ASWebAuthenticationSession` must be created and
/// started on the main thread (it presents UI).
@MainActor
public final class GarminAuthSession: NSObject {
    private let tokenProvider: TokenProvider
    private let urlSession: URLSession
    private let baseURL: String

    /// Held for the lifetime of an in-flight sign-in so
    /// `ASWebAuthenticationSession` isn't deallocated mid-flow.
    private var activeSession: ASWebAuthenticationSession?

    public init(
        tokenProvider: TokenProvider = .shared,
        urlSession: URLSession = .shared,
        baseURL: String = GarminAPI.connectAPI
    ) {
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.baseURL = baseURL
    }

    /// Presents Garmin's sign-in page inside `ASWebAuthenticationSession`.
    ///
    /// `presentationContextProvider` is supplied by the CALLER (the app
    /// target, which owns a real window to anchor the sheet to) rather than
    /// implemented in this package -- GarminKit has no UIKit/SwiftUI
    /// dependency by design (see Package.swift), and providing a
    /// presentation anchor is the app's job, not a shared logic package's.
    @discardableResult
    public func signIn(
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
        prefersEphemeralWebBrowserSession: Bool = false
    ) async throws -> GarminOAuth1Token {
        let callbackURL = try await runWebAuthenticationSession(
            presentationContextProvider: presentationContextProvider,
            prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession
        )

        guard let ticket = Self.extractTicket(from: callbackURL) else {
            throw GarminBootstrapError.missingTicket
        }
        return try await exchangeTicket(ticket)
    }

    /// The documented fallback (design.md D2, task 8.4): sign in through a
    /// real desktop/mobile browser by hand, copy the service ticket out of
    /// the resulting redirect URL, and paste it here. Exactly the workflow
    /// the wider Garmin-tooling community (garth and friends) already uses.
    /// Kept even once `signIn(presentationContextProvider:)` works -- per D2,
    /// "it is the recovery path when the redirect contract changes," which
    /// it eventually will, because none of the URLs above are confirmed
    /// stable.
    @discardableResult
    public func completeBootstrap(withPastedTicket ticket: String) async throws -> GarminOAuth1Token {
        try await exchangeTicket(ticket)
    }

    // MARK: - ASWebAuthenticationSession plumbing

    private func runWebAuthenticationSession(
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
        prefersEphemeralWebBrowserSession: Bool
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let resumeOnce: (Result<URL, Error>) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let session = ASWebAuthenticationSession(
                url: GarminSSOEndpoints.signInURL,
                callbackURLScheme: GarminSSOEndpoints.callbackURLScheme
            ) { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    resumeOnce(.failure(GarminBootstrapError.cancelled))
                    return
                }
                if let error {
                    resumeOnce(.failure(GarminBootstrapError.sessionFailed(error)))
                    return
                }
                guard let url else {
                    resumeOnce(.failure(GarminBootstrapError.missingCallbackURL))
                    return
                }
                resumeOnce(.success(url))
            }
            session.presentationContextProvider = presentationContextProvider
            // false (the default) lets Garmin's page see any existing Safari
            // session/cookies, matching D2's framing of "the user signs in
            // inside the app" as closely as possible to a real browser --
            // Garmin may still force fresh credential entry; that's Garmin's
            // call, not ours.
            session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
            self.activeSession = session

            if !session.start() {
                resumeOnce(.failure(GarminBootstrapError.sessionFailed(
                    NSError(
                        domain: "GarminAuthSession",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "ASWebAuthenticationSession.start() returned false"]
                    )
                )))
            }
        }
    }

    private static func extractTicket(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == GarminSSOEndpoints.ticketQueryParameterName })?
            .value
    }

    // MARK: - Ticket -> OAuth1 exchange (UNCONFIRMED -- see file header)

    /// Exchanges a service ticket for the long-lived OAuth1 token and
    /// stores it via `TokenProvider`. See this file's header comment: the
    /// request shape here is a best-effort port of publicly-documented
    /// community tooling behavior, not a route this project has confirmed
    /// against its own account.
    private func exchangeTicket(_ ticket: String) async throws -> GarminOAuth1Token {
        let consumer = try await OAuth1Signer.fetchConsumer(session: urlSession)

        var components = URLComponents(string: baseURL + GarminSSOEndpoints.preauthorizedPath)!
        components.queryItems = [
            URLQueryItem(name: "ticket", value: ticket),
            URLQueryItem(name: "login-url", value: "https://sso.garmin.com/sso/embed"),
            URLQueryItem(name: "accepts-mfa-tokens", value: "true"),
        ]
        guard let url = components.url else {
            throw GarminBootstrapError.malformedExchangeResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(GarminUserAgent.value, forHTTPHeaderField: "User-Agent")
        // Signed with an EMPTY token/secret: this step is establishing the
        // OAuth1 token in the first place, so there is no user token yet --
        // only the (public) consumer key/secret identifies the client.
        // Whether Garmin's server actually expects `oauth_token` to be
        // present-but-empty in the signature (as done here) versus omitted
        // entirely is itself UNCONFIRMED; this is the most speculative
        // single line in this file.
        request.setValue(
            OAuth1Signer.authorizationHeader(
                method: "GET",
                url: url.absoluteString,
                consumer: consumer,
                token: "",
                tokenSecret: ""
            ),
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GarminBootstrapError.exchangeFailed(statusCode: nil, body: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GarminBootstrapError.exchangeFailed(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }

        // Modeled as a query-string-shaped body (`oauth_token=...&oauth_token_secret=...`),
        // matching how OAuth1's request-token responses are conventionally
        // encoded (RFC 5849 section 2.1) and how community tooling parses
        // this same preauthorized-step response. UNCONFIRMED against a real
        // Garmin response.
        guard let body = String(data: data, encoding: .utf8) else {
            throw GarminBootstrapError.malformedExchangeResponse
        }
        var queryComponents = URLComponents()
        queryComponents.query = body
        let pairs = queryComponents.queryItems ?? []
        guard
            let oauthToken = pairs.first(where: { $0.name == "oauth_token" })?.value,
            let oauthTokenSecret = pairs.first(where: { $0.name == "oauth_token_secret" })?.value
        else {
            throw GarminBootstrapError.malformedExchangeResponse
        }

        let token = GarminOAuth1Token(oauthToken: oauthToken, oauthTokenSecret: oauthTokenSecret)
        try await tokenProvider.storeOAuth1Token(token)
        return token
    }
}
