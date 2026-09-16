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
// CONFIRMED END TO END 2026-09-16. This was "genuinely unverified
// territory" until a real device signed in and immediately performed
// authenticated reads. Everything below is now load-bearing and proven --
// change it only with a device to re-verify on.
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
//   - The ticket -> OAuth1 EXCHANGE below (`exchangeTicket`) works, which
//     ANSWERS design.md's Open Question 1: a CAS service ticket IS
//     exchangeable for a long-lived OAuth1 token, not merely for some
//     different (DI OAuth2, ~30-day-refresh) credential. Evidence: the same
//     device went straight from sign-in to authenticated reads, which is
//     impossible without a valid OAuth1 token stored by this route.
//   - `login-url` does NOT have to be garth's `https://sso.garmin.com/sso/embed`.
//     `https://connect.garmin.com/modern` is accepted, which is what lets
//     this project keep the redirect-based capture it had already confirmed
//     instead of adopting garth's embed-widget flow. This was the single
//     biggest open worry and it is now settled -- see `serviceURL`.
//   - The response really is a query-string body carrying
//     `oauth_token`/`oauth_token_secret`, as modelled on garth. A wrong
//     guess here would have thrown `malformedExchangeResponse` rather than
//     authenticating, so success confirms the shape.
//
// Still NOT confirmed:
//   - Nothing in this file. The remaining unverified surface in this project
//     has moved to the WRITE path: every route in docs/garmin-routes.json's
//     `write` section is still "documented, not exercised", and the first
//     real `createFoodLogEntry` attempt (2026-09-16) failed. See
//     docs/garmin-food-log-contract.md.
//
// docs/garmin-routes.json's `auth` section has been updated accordingly
// (`exchangeTicketForOAuth1`, observedStatus 200, lastVerified 2026-09-16),
// per the instruction that used to live here.

import Foundation

/// Constants for the browser bootstrap, CONFIRMED end to end 2026-09-16.
/// See this file's header comment.
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
    ///
    /// It resolves to the MINT side's value, not the redeem side's, because
    /// the mint side is the half this project has actually confirmed. garth
    /// uses `https://sso.garmin.com/sso/embed` here, but garth does not
    /// capture its ticket from a redirect at all -- it regex-scrapes
    /// `embed?ticket=...` out of the sign-in POST's response body. The embed
    /// widget is built to be iframed and hand its result to a parent frame in
    /// JS, so adopting garth's `service` would risk the top frame never
    /// navigating, `decidePolicyFor` never firing, and the sheet hanging with
    /// no callback -- trading a confirmed-working capture for an unverified
    /// one. Changing this constant means re-verifying capture on a device.
    public static let serviceURL = "https://connect.garmin.com/modern"

    /// Garmin's SSO sign-in page. This is the exact parameter set under which
    /// a real device completed sign-in and produced an observable,
    /// ticket-bearing navigation on 2026-09-16; only `service` and the two
    /// `redirectAfter...` values are routed through `serviceURL`, so that the
    /// ticket is minted for the same service `exchangeTicket` redeems it
    /// against. Do not re-parameterize this without a device to re-confirm on.
    public static let signInURL: URL = {
        var components = URLComponents(string: "https://sso.garmin.com/sso/signin")!
        let service = GarminSSOEndpoints.serviceURL
        components.queryItems = [
            URLQueryItem(name: "service", value: service),
            URLQueryItem(name: "webhost", value: "https://connect.garmin.com"),
            URLQueryItem(name: "source", value: "https://connect.garmin.com/signin"),
            URLQueryItem(name: "redirectAfterAccountLoginUrl", value: service),
            URLQueryItem(name: "redirectAfterAccountCreationUrl", value: service),
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

    /// The query parameter carrying the resulting service ticket. CONFIRMED
    /// 2026-09-16: a real sign-in reached the ticket EXCHANGE, which is only
    /// reachable once this parameter has been found in a navigated-to URL.
    public static let ticketQueryParameterName = "ticket"

    /// Extracts a service ticket from whatever the caller has in hand.
    ///
    /// Both capture paths funnel through here so they cannot disagree about
    /// what a ticket looks like, and so neither hardcodes the parameter name
    /// that `ticketQueryParameterName` exists to own. `GarminSSOWebView`
    /// passes a navigated-to URL; the manual fallback passes whatever the
    /// user pasted. That user is told to copy a value "from the redirect
    /// URL", so all three of these shapes turn up in practice:
    ///
    ///   - a full URL   -- `https://connect.garmin.com/modern?ticket=ST-...`
    ///   - a query pair -- `ticket=ST-...`, which has no `?`, so
    ///     `URLComponents` reads it as a PATH and finds no query items at all
    ///   - the bare value -- `ST-...`
    ///
    /// The middle case is why this cannot just be `URLComponents`: a
    /// URL-parsing-only version silently hands `ticket=ST-...` back with the
    /// prefix still attached, and the exchange then fails blaming the user's
    /// paste. A copy that wrapped across lines (embedding a space, which
    /// `URLComponents(string:)` rejects outright) lands here the same way.
    public static func ticket(in raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let value = ticket(in: url) {
            return value
        }

        if let marker = trimmed.range(of: ticketQueryParameterName + "=") {
            var value = ""
            for character in trimmed[marker.upperBound...] {
                if character == "&" || character == "#" { break }
                value.append(character)
            }
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }

        return trimmed
    }

    /// The strict counterpart, for a URL that was actually navigated to:
    /// returns a ticket only if this URL genuinely carries one. Callers
    /// watching navigations need that "no" answer, which is exactly what the
    /// lenient `ticket(in raw:)` above cannot give them -- it falls back to
    /// treating unrecognised input as the ticket itself, which is right for a
    /// human paste and wrong for a redirect.
    public static func ticket(in url: URL) -> String? {
        guard
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let value = items.first(where: { $0.name == ticketQueryParameterName })?.value,
            !value.isEmpty
        else { return nil }
        return value
    }

    /// Whether a navigated-to URL belongs to Garmin, used to gate ticket
    /// capture. Without it, ANY navigation carrying a `ticket` query
    /// parameter -- an analytics hop, a marketing redirect, an unrelated
    /// host -- latches the one-shot capture, cancels that navigation, and
    /// ends the sign-in holding a ticket Garmin never minted, with no way to
    /// retry inside the same sheet.
    ///
    /// Deliberately the whole `garmin.com` tree rather than just
    /// `serviceURL`'s host: the class of mistake worth excluding is a third
    /// party, and narrowing it further risks rejecting an intermediate CAS
    /// hop that the 2026-09-16 device test had no reason to reveal.
    public static func isGarminHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "garmin.com" || host.hasSuffix(".garmin.com")
    }

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
        // R3 again: this fires BEFORE any request is sent, so it is a
        // malformed URL, not a malformed response. Reporting it as the latter
        // tells the user Garmin replied when Garmin was never contacted.
        guard let url = components.url else {
            throw GarminBootstrapError.invalidExchangeURL
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
