// GarminAuthSession.swift
//
// The browser-based bootstrap (design.md D2): the user taps "Connect
// Garmin", a real WebKit-rendered browser opens Garmin's sign-in page, and
// on success the app captures a service ticket and exchanges it for the
// long-lived OAuth1 token.
//
// REAL-DEVICE FINDING (2026-09-16): the capture step originally used
// `ASWebAuthenticationSession`, which only completes when the browser
// navigates to a URL whose SCHEME matches a registered callback scheme.
// Real testing showed sign-in genuinely succeeds -- the user ends up on a
// real, authenticated `https://connect.garmin.com/modern` -- but that's an
// `https://` URL Garmin's CAS was told to redirect to
// (`GarminSSOEndpoints.signInURL`'s `service`/`redirectAfterAccountLoginUrl`
// params), never our app's custom scheme, so
// `ASWebAuthenticationSession`'s completion handler never fires. The ticket
// capture now happens in the app target instead
// (`ios/GarminFood/App/GarminSSOWebView.swift`), using a plain `WKWebView`
// with a navigation delegate that inspects every navigated-to URL for a
// `ticket` query parameter -- it doesn't depend on Garmin honoring any
// particular redirect scheme, only on the (now-confirmed) fact that
// `sso.garmin.com` -> `connect.garmin.com` is a real, observable, full-page
// navigation. GarminKit itself has no UIKit dependency (see Package.swift),
// so only the ticket -> OAuth1 EXCHANGE below remains this package's job;
// the capture step is intentionally not implemented here.
//
// =====================================================================
// READ THIS BEFORE TOUCHING ANYTHING BELOW: GENUINELY UNVERIFIED TERRITORY
// =====================================================================
//
// Confirmed, live, elsewhere in this project:
//   - Garmin's SSO sign-in endpoints sit behind Cloudflare bot protection
//     as of March 2026 (design.md Context) -- a scripted credential POST
//     to `oauth-service/oauth/preauthorized` gets 401. A real, interactive,
//     WebKit-rendered sign-in (as opposed to a scripted POST) is NOT
//     blocked by this -- confirmed by the same 2026-09-16 real-device test.
//   - The OAuth1 -> OAuth2 EXCHANGE (once an OAuth1 token already exists)
//     works (TokenProvider.swift, `POST /oauth-service/oauth/exchange/user/2.0`).
//   - `GarminSSOEndpoints.signInURL` is a real, working Garmin sign-in page
//     (2026-09-16): loading it and signing in by hand does produce a real,
//     authenticated Garmin session.
//   - The ticket CAPTURE works (2026-09-16, second real-device test): the
//     user signed in and the app reported a failed ticket EXCHANGE, which it
//     can only reach via `GarminSSOWebView`'s `onTicket` -- so the redirect
//     really does carry a `ticket` query parameter and the navigation
//     delegate really does observe it. `ticketQueryParameterName` is settled.
//
// NOT confirmed, anywhere, by this project's own testing:
//   - Whether a service ticket obtained this way is even exchangeable for
//     an OAuth1 token at all, versus only for a different (DI OAuth2,
//     ~30-day-refresh) token entirely -- this is design.md's Open Question 1,
//     explicitly still open. The 2026-09-16 exchange failure is NOT yet
//     evidence either way: it was made against a request carrying three
//     independent defects (see `exchangeTicket`), all since fixed, so the
//     route deserves one clean attempt before that Open Question is judged.
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
// own doc comment. When a real sign-in actually reaches `exchangeTicket`,
// update docs/garmin-routes.json's `auth` section with whatever the real
// parameter/response turns out to be, with a `lastVerified` date, matching
// this repo's existing convention for every other route in that file. Do
// not quietly leave this comment stale once that happens.

import Foundation

/// Best-effort, UNCONFIRMED constants for the browser bootstrap. See this
/// file's header comment.
public enum GarminSSOEndpoints {
    /// The single CAS "service" this whole bootstrap is pinned to.
    ///
    /// It has to appear twice -- as `service` where the ticket is MINTED
    /// (`signInURL`) and as `login-url` where it is REDEEMED
    /// (`GarminAuthSession.exchangeTicket`) -- and CAS issues a ticket that is
    /// only valid for the exact service it was minted for. Before 2026-09-16
    /// these were two separate literals that did not agree
    /// (`https://connect.garmin.com/modern` at mint,
    /// `https://sso.garmin.com/sso/embed` at redeem), which alone is enough
    /// for Garmin to reject every ticket the app ever captured. They are one
    /// constant now specifically so they cannot drift apart again.
    public static let serviceURL = "https://sso.garmin.com/sso/embed"

    /// Garmin's SSO sign-in page, parameterized the way community tooling
    /// (garth) constructs it for an embedded widget: every redirect target is
    /// `serviceURL`, so a completed sign-in lands back on that URL with a
    /// `ticket=ST-...` query parameter. That hop is a server-issued 302, so
    /// `GarminSSOWebView`'s navigation delegate still observes it even though
    /// it no longer crosses an origin boundary (the previous
    /// `sso.garmin.com` -> `connect.garmin.com` hop did).
    public static let signInURL: URL = {
        var components = URLComponents(string: "https://sso.garmin.com/sso/signin")!
        let service = GarminSSOEndpoints.serviceURL
        components.queryItems = [
            URLQueryItem(name: "id", value: "gauth-widget"),
            URLQueryItem(name: "embedWidget", value: "true"),
            URLQueryItem(name: "gauthHost", value: service),
            URLQueryItem(name: "service", value: service),
            URLQueryItem(name: "source", value: service),
            URLQueryItem(name: "redirectAfterAccountLoginUrl", value: service),
            URLQueryItem(name: "redirectAfterAccountCreationUrl", value: service),
            URLQueryItem(name: "locale", value: "en_US"),
        ]
        return components.url!
    }()

    /// The query parameter carrying the resulting service ticket. CONFIRMED
    /// 2026-09-16: a real sign-in reached the ticket EXCHANGE, which is only
    /// reachable once this parameter has been found in a navigated-to URL.
    public static let ticketQueryParameterName = "ticket"

    /// The GET route community tooling (garth) uses to exchange a ticket
    /// for an OAuth1 token pair. UNCONFIRMED against this project's own
    /// account -- see header comment.
    public static let preauthorizedPath = "/oauth-service/oauth/preauthorized"
}

public enum GarminBootstrapError: Error {
    case exchangeFailed(statusCode: Int?, body: String?)
    case malformedExchangeResponse
    /// The exchange request URL failed to construct (R3) -- mirrors
    /// `GarminClientError.invalidURL`'s role in `GarminClient.authorizedRequest`.
    case invalidExchangeURL
}

/// Runs the ticket -> OAuth1 exchange for the browser-based bootstrap (the
/// browser/ticket-capture step itself lives in the app target -- see this
/// file's header comment) and, on success, stores the resulting OAuth1
/// token via `TokenProvider`.
@MainActor
public final class GarminAuthSession {
    private let tokenProvider: TokenProvider
    private let urlSession: URLSession
    private let baseURL: String
    /// Optional (R5): when supplied, a successful bootstrap automatically
    /// calls `markAuthenticated()` on it, so callers don't have to remember
    /// to wire that up themselves. `nil` by default for flexibility/
    /// testability -- unit tests exercising just the ticket-exchange logic
    /// don't need a real `GarminAuthState` in play.
    private let authState: GarminAuthState?

    public init(
        tokenProvider: TokenProvider = .shared,
        urlSession: URLSession = .shared,
        baseURL: String = GarminAPI.connectAPI,
        authState: GarminAuthState? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.baseURL = baseURL
        self.authState = authState
    }

    /// Completes sign-in with a service ticket obtained however the caller
    /// captured it -- either `GarminSSOWebView`'s automatic `WKWebView`
    /// capture, or the manual paste-it-yourself fallback (design.md D2,
    /// task 8.4). Both paths converge here because the exchange itself
    /// doesn't care where the ticket came from.
    @discardableResult
    public func completeBootstrap(withPastedTicket ticket: String) async throws -> GarminOAuth1Token {
        try await exchangeTicket(ticket)
    }

    // MARK: - Ticket -> OAuth1 exchange (UNCONFIRMED -- see file header)

    /// Exchanges a service ticket for the long-lived OAuth1 token and
    /// stores it via `TokenProvider`. See this file's header comment: the
    /// request shape here is a best-effort port of publicly-documented
    /// community tooling behavior, not a route this project has confirmed
    /// against its own account.
    private func exchangeTicket(_ ticket: String) async throws -> GarminOAuth1Token {
        let consumer = try await OAuth1Signer.fetchConsumer(session: urlSession)

        // R3: matches the safe pattern already used in
        // `GarminClient.authorizedRequest` -- a malformed `baseURL` must
        // throw, not crash the process.
        guard var components = URLComponents(string: baseURL + GarminSSOEndpoints.preauthorizedPath) else {
            throw GarminBootstrapError.invalidExchangeURL
        }
        components.queryItems = [
            URLQueryItem(name: "ticket", value: ticket),
            // Must name the same service the ticket was minted for -- see
            // `GarminSSOEndpoints.serviceURL`.
            URLQueryItem(name: "login-url", value: GarminSSOEndpoints.serviceURL),
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
        // `OAuth1Signer` therefore omits `oauth_token` from the signature
        // entirely rather than signing it as present-but-empty (RFC 5849
        // 3.4.1.3.1, and what the reference tooling does), and folds this
        // URL's query parameters into the signed parameter set -- this is the
        // only signed request in the project that has any.
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
        // R5: nothing else wires a successful bootstrap back to
        // `GarminAuthState` -- without this, a real successful reconnect
        // still leaves the UI stuck showing "sign in again". Both types are
        // `@MainActor`, so this is a same-actor synchronous call, not a
        // cross-actor `await`.
        authState?.markAuthenticated()
        return token
    }
}
