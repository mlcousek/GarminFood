// GarminSSOWebView.swift
//
// Real-device testing (2026-09-16) confirmed why `GarminAuthSession.signIn
// (presentationContextProvider:)` (the `ASWebAuthenticationSession`-based
// flow in GarminKit) can never complete: signing in genuinely succeeds --
// the user ends up looking at a real, authenticated
// https://connect.garmin.com/modern inside the sheet -- but
// `ASWebAuthenticationSession` only ever completes when the browser
// navigates to a URL whose SCHEME matches `callbackURLScheme`
// ("garminfood"). Our sign-in URL tells Garmin's CAS to send the browser
// back to `https://connect.garmin.com/modern` (GarminSSOEndpoints.signInURL's
// `service`/`redirectAfterAccountLoginUrl` params), not to our scheme, so
// that condition is never met. The user is left staring at Garmin's own
// website with no way back into the app except manually dismissing, which
// (correctly, but unhelpfully) reports as a cancelled sign-in.
//
// The post-sign-in hop is a server-issued CAS 302 carrying the ticket in its
// Location header, which `WKNavigationDelegate.decidePolicyFor` sees with the
// REQUESTED url (ticket query parameter included) before that page loads and
// before any of its own JS can strip the ticket from the visible address,
// e.g. via `history.replaceState`. This capture was CONFIRMED working on a
// real device 2026-09-16.
//
// It does NOT depend on that hop crossing an origin boundary -- it did when
// this file was written (`sso.garmin.com` -> `connect.garmin.com`), but
// `GarminSSOEndpoints.serviceURL` now keeps the whole flow on
// `sso.garmin.com/sso/embed`, so that the minted ticket names the same CAS
// service the exchange later redeems it against. A 302 is observable either
// way; only a same-origin `history.pushState` would not be, and CAS does not
// use one.
//
// This uses a real `WKWebView`, not `ASWebAuthenticationSession`, purely to
// solve that observability gap. It is NOT a response to design.md's
// Cloudflare bot-protection concern -- that concern was specifically about
// *scripted, non-interactive* credential POSTs (no browser, no JS, no real
// device fingerprint) hitting `oauth-service/oauth/preauthorized` directly.
// A real WebKit-rendered form, filled in by an actual person, is not what
// that protection targets, and this same real-device test already proved a
// real browser session (Safari's, via ASWebAuthenticationSession) gets past
// it -- there's no confirmed evidence WKWebView's own WebKit engine would be
// treated differently for an interactive, human-driven sign-in.
//
// Once a ticket is captured here, it's handed to
// `GarminAuthSession.completeBootstrap(withPastedTicket:)` -- the exact
// same ticket -> OAuth1 exchange the manual paste fallback already uses.
// Only the CAPTURE mechanism changes; the exchange itself is unaffected and
// remains just as unconfirmed/best-effort as GarminAuthSession's own header
// comment describes.

import SwiftUI
import WebKit
import GarminKit

struct GarminSSOWebView: UIViewControllerRepresentable {
    let onTicket: (String) -> Void
    let onCancel: () -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = GarminSSOWebViewController()
        controller.onTicket = onTicket
        controller.onCancel = onCancel
        controller.onFailure = onFailure
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

private final class GarminSSOWebViewController: UIViewController, WKNavigationDelegate {
    var onTicket: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private var webView: WKWebView!
    private var didResolve = false
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override func loadView() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sign in to Garmin"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        activityIndicator.hidesWhenStopped = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: activityIndicator)
        activityIndicator.startAnimating()
        webView.load(URLRequest(url: GarminSSOEndpoints.signInURL))
    }

    @objc private func cancelTapped() {
        guard !didResolve else { return }
        didResolve = true
        onCancel?()
    }

    private func resolveTicket(_ ticket: String) {
        guard !didResolve else { return }
        didResolve = true
        onTicket?(ticket)
    }

    private func resolveFailure(_ message: String) {
        guard !didResolve else { return }
        didResolve = true
        onFailure?(message)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           let ticket = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == GarminSSOEndpoints.ticketQueryParameterName })?.value {
            decisionHandler(.cancel)
            resolveTicket(ticket)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        resolveFailure("Couldn't load Garmin's sign-in page. Check your connection and try again.")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        resolveFailure("Couldn't load Garmin's sign-in page. Check your connection and try again.")
    }
}
