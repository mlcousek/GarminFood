// GarminSSOWebView.swift
//
// Real-device testing (2026-09-16) confirmed why the since-deleted
// `GarminAuthSession.signIn(presentationContextProvider:)` (an
// `ASWebAuthenticationSession`-based flow that lived in GarminKit until
// 2b96f35) could never complete: signing in genuinely succeeds --
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
// `sso.garmin.com` and `connect.garmin.com` are different origins, so
// landing on the latter after starting on the former MUST be a real,
// full-page navigation (no same-origin `history.pushState` trick can do
// that) -- which is exactly the event `WKNavigationDelegate.decidePolicyFor`
// observes, and it fires with the REQUESTED url (ticket query param
// included) before that page loads and before any of its own JS has a
// chance to strip the ticket from the visible address, e.g. via
// `history.replaceState`. CONFIRMED working on a real device 2026-09-16.
//
// `GarminSSOEndpoints.serviceURL` is what keeps that hop cross-origin, and
// is pinned to `connect.garmin.com/modern` partly for this reason. See its
// own doc comment for why garth's `sso/embed` service would be the wrong
// trade here, despite being the shape garth itself uses.
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

import Foundation
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
        title = String(localized: "Sign in to Garmin")
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
        // The host gate matters because capture is one-shot and destructive:
        // it cancels the navigation and latches `didResolve`. Any URL at all
        // carrying a `ticket` parameter -- an analytics hop, a marketing
        // redirect, some unrelated host -- would otherwise end the sign-in
        // holding a value Garmin never minted, with no way to retry in this
        // sheet.
        if let url = navigationAction.request.url,
           GarminSSOEndpoints.isGarminHost(url),
           let ticket = GarminSSOEndpoints.ticket(in: url) {
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
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    private func handleNavigationFailure(_ error: Error) {
        activityIndicator.stopAnimating()
        guard !Self.isBenignNavigationInterruption(error) else { return }
        resolveFailure(String(localized: "Couldn't load Garmin's sign-in page. Check your connection and try again."))
    }

    /// WebKit reports a navigation that was SUPERSEDED through the same
    /// delegate methods as one that actually broke. Two of those are routine
    /// here and must not end the sign-in: `NSURLErrorCancelled`, when a load
    /// is replaced mid-flight (the SSO page's own JS does this after
    /// credential submission), and `WebKitErrorDomain` 102
    /// (`FrameLoadInterruptedByPolicyChange`), raised when a policy decision
    /// cancels a load -- which is exactly what `decidePolicyFor` does on
    /// every SUCCESSFUL capture.
    ///
    /// Reporting either as a failure would close the sheet mid-sign-in and
    /// latch `didResolve`, so the real ticket navigation that follows is then
    /// silently ignored. (`resolveFailure`'s own `didResolve` guard already
    /// absorbs the post-capture case, but only because capture happens to win
    /// the race; the JS-navigation case has no such protection.)
    private static func isBenignNavigationInterruption(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 {
            return true
        }
        return false
    }
}
