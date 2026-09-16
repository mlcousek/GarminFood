// GarminSSOEndpointsTests.swift
//
// `ticket(in:)` is the single point both capture paths agree on: the
// `WKWebView` navigation delegate and the manual paste fallback. The paste
// path is the project's declared recovery route "when the redirect contract
// changes" (task 8.4), so it is worth exactly as much as its tolerance for
// what a human actually copies -- and its first implementation silently
// handed back `ticket=ST-...` with the prefix still attached, failing the
// exchange and blaming the paste for it.

import XCTest
@testable import GarminKit

final class GarminSSOEndpointsTests: XCTestCase {
    private let ticket = "ST-0123456-aBcDeF-cas"

    func testExtractsTicketFromFullRedirectURL() {
        XCTAssertEqual(
            GarminSSOEndpoints.ticket(in: "https://connect.garmin.com/modern?ticket=\(ticket)"),
            ticket
        )
    }

    /// No `?`, so `URLComponents` reads the whole thing as a PATH and reports
    /// no query items at all. This is the shape a user produces by copying
    /// the query pair out of the address bar.
    func testExtractsTicketFromBareQueryPair() {
        XCTAssertEqual(GarminSSOEndpoints.ticket(in: "ticket=\(ticket)"), ticket)
        XCTAssertEqual(GarminSSOEndpoints.ticket(in: "?ticket=\(ticket)"), ticket)
    }

    func testStopsAtTheNextQueryParameter() {
        XCTAssertEqual(GarminSSOEndpoints.ticket(in: "ticket=\(ticket)&foo=bar"), ticket)
    }

    /// An embedded space makes `URL(string:)` fail outright, which is how a
    /// copy that wrapped across lines arrives.
    func testRecoversWhenURLParsingRejectsTheInput() {
        XCTAssertEqual(
            GarminSSOEndpoints.ticket(in: "https://connect.garmin.com/modern ?ticket=\(ticket)"),
            ticket
        )
    }

    func testAcceptsABareTicketValue() {
        XCTAssertEqual(GarminSSOEndpoints.ticket(in: "  \(ticket)  "), ticket)
    }

    func testReturnsNilForEmptyInput() {
        XCTAssertNil(GarminSSOEndpoints.ticket(in: "   \n "))
    }

    /// The URL overload is strict on purpose: a navigation watcher needs a
    /// truthful "this one carries no ticket", which the lenient String
    /// overload cannot give (it treats unrecognised input as the ticket).
    func testURLOverloadReturnsNilWhenNoTicketPresent() {
        let url = URL(string: "https://connect.garmin.com/modern")!
        XCTAssertNil(GarminSSOEndpoints.ticket(in: url))
    }

    func testURLOverloadReturnsNilForEmptyTicketValue() {
        let url = URL(string: "https://connect.garmin.com/modern?ticket=")!
        XCTAssertNil(GarminSSOEndpoints.ticket(in: url))
    }

    func testHostGateAcceptsGarminAndRejectsOthers() {
        XCTAssertTrue(GarminSSOEndpoints.isGarminHost(URL(string: "https://connect.garmin.com/modern")!))
        XCTAssertTrue(GarminSSOEndpoints.isGarminHost(URL(string: "https://sso.garmin.com/sso/signin")!))
        XCTAssertFalse(GarminSSOEndpoints.isGarminHost(URL(string: "https://example.com/?ticket=x")!))
        // Suffix matching must not be fooled by a lookalike registrable domain.
        XCTAssertFalse(GarminSSOEndpoints.isGarminHost(URL(string: "https://evilgarmin.com/?ticket=x")!))
    }

    /// The mint and redeem halves of the bootstrap must name the same CAS
    /// service, because a ticket is only valid for the service it was minted
    /// for. These were two literals that disagreed until 2026-09-16.
    func testSignInURLMintsForTheSameServiceTheExchangeRedeems() {
        let items = URLComponents(url: GarminSSOEndpoints.signInURL, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(
            items?.first(where: { $0.name == "service" })?.value,
            GarminSSOEndpoints.serviceURL
        )
        XCTAssertEqual(
            items?.first(where: { $0.name == "redirectAfterAccountLoginUrl" })?.value,
            GarminSSOEndpoints.serviceURL
        )
    }
}
