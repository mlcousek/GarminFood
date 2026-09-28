// VaultOutcomeTests.swift
//
// add-vault-connection task 2.4: the design D6 classification table row by
// row, the rate-limit header rules (retry-after vs x-ratelimit-reset,
// clamping), the tolerant token-expiry parser, and the `VaultStatus` /
// `VaultConnectionState` rules behind the banner and the request gate
// (design D10): loud outcomes block until the user acts, rate limits block
// until their reset and persist across launches, offline and server errors
// never block and never show a banner.

import XCTest
@testable import VaultKit

final class VaultOutcomeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let none = VaultResponseHeaders()

    private func classify(_ status: Int, _ headers: [String: String] = [:], kind: VaultOutcome.RequestKind = .file) -> VaultOutcome {
        VaultOutcome.classify(status: status, headers: VaultResponseHeaders(headers), kind: kind, now: now)
    }

    // MARK: - The D6 table

    func testSuccessAndNotModified() {
        for status in [200, 201, 204, 304] {
            XCTAssertEqual(classify(status), .success, "\(status)")
        }
    }

    func testLoudAuthOutcomes() {
        XCTAssertEqual(classify(401), .authFailed(.tokenRejected))
        XCTAssertEqual(classify(403), .authFailed(.forbidden))
        XCTAssertEqual(classify(403, ["X-RateLimit-Remaining": "12"]), .authFailed(.forbidden))
        XCTAssertEqual(classify(404, kind: .repository), .authFailed(.repositoryNotFound))
        XCTAssertEqual(classify(404, kind: .create), .authFailed(.repositoryNotFound))
        for loud in [classify(401), classify(403), classify(404, kind: .repository)] {
            XCTAssertTrue(loud.isLoud, "\(loud)")
        }
    }

    func testFileNotFoundIsQuiet() {
        XCTAssertEqual(classify(404, kind: .file), .fileNotFound)
        XCTAssertFalse(VaultOutcome.fileNotFound.isLoud)
    }

    func testRateLimitsAreQuietAndCarryTheirResumeTime() {
        XCTAssertEqual(classify(429, ["Retry-After": "120"]), .rateLimited(until: now.addingTimeInterval(120)))
        XCTAssertEqual(classify(403, ["retry-after": "30"]), .rateLimited(until: now.addingTimeInterval(30)))
        let reset = now.addingTimeInterval(900)
        XCTAssertEqual(
            classify(403, ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "\(Int(reset.timeIntervalSince1970))"]),
            .rateLimited(until: reset)
        )
        // retry-after wins over the reset time.
        XCTAssertEqual(classify(429, ["retry-after": "5", "x-ratelimit-remaining": "0", "x-ratelimit-reset": "\(Int(reset.timeIntervalSince1970))"]), .rateLimited(until: now.addingTimeInterval(5)))
        // A 429 without usable headers waits a minute.
        XCTAssertEqual(classify(429), .rateLimited(until: now.addingTimeInterval(60)))
        XCTAssertFalse(classify(429).isLoud)
    }

    func testRateLimitPauseIsClamped() {
        // A bogus day-long pause is capped at an hour; a past reset time
        // still waits at least a second.
        XCTAssertEqual(classify(429, ["retry-after": "86400"]), .rateLimited(until: now.addingTimeInterval(3600)))
        XCTAssertEqual(classify(403, ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1000"]), .rateLimited(until: now.addingTimeInterval(1)))
    }

    func testRetryableAndOtherStatuses() {
        XCTAssertEqual(classify(409), .conflict)
        XCTAssertEqual(classify(422, kind: .create), .alreadyExists)
        XCTAssertEqual(classify(422, kind: .file), .unexpected(status: 422))
        XCTAssertEqual(classify(500), .serverError(status: 500))
        XCTAssertEqual(classify(503), .serverError(status: 503))
        XCTAssertEqual(classify(302), .redirectRefused)
        XCTAssertEqual(classify(418), .unexpected(status: 418))
        XCTAssertEqual(classify(400), .unexpected(status: 400))
    }

    func testErrorsBeforeAnyAnswer() {
        XCTAssertEqual(VaultOutcome.classify(error: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(VaultOutcome.classify(error: URLError(.timedOut)), .offline)
        XCTAssertEqual(VaultOutcome.classify(error: URLError(.cancelled)), .transportError(code: URLError.Code.cancelled.rawValue))
        XCTAssertEqual(VaultOutcome.classify(error: URLError(.serverCertificateUntrusted)), .transportError(code: URLError.Code.serverCertificateUntrusted.rawValue))
        struct Other: Error {}
        XCTAssertEqual(VaultOutcome.classify(error: Other()), .transportError(code: 0))
    }

    func testOutcomesRoundTripThroughJSON() throws {
        let all: [VaultOutcome] = [
            .success, .authFailed(.forbidden), .fileNotFound, .rateLimited(until: now), .alreadyExists,
            .conflict, .serverError(status: 502), .offline, .refusedByPolicy, .redirectRefused,
            .notConfigured, .unexpected(status: 418), .transportError(code: -1200)
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode([VaultOutcome].self, from: encoder.encode(all)), all)
    }

    // MARK: - Headers

    func testHeadersAreCaseInsensitive() {
        let headers = VaultResponseHeaders(["ETag": "\"abc\"", "X-RateLimit-Remaining": "0"])
        XCTAssertEqual(headers["etag"], "\"abc\"")
        XCTAssertEqual(headers["ETAG"], "\"abc\"")
        XCTAssertTrue(headers.hasRateLimitSignal)
        XCTAssertFalse(none.hasRateLimitSignal)
    }

    func testTokenExpiryParsingIsTolerant() {
        let expected = Date(timeIntervalSince1970: 1_799_000_000) // 2027-01-03 18:13:20 UTC
        XCTAssertEqual(TokenExpiryParser.parse("2027-01-03 18:13:20 UTC"), expected)
        XCTAssertEqual(TokenExpiryParser.parse("2027-01-03 19:13:20 +0100"), expected)
        XCTAssertEqual(TokenExpiryParser.parse("2027-01-03T18:13:20Z"), expected)
        XCTAssertEqual(TokenExpiryParser.parse(" 2027-01-03 18:13:20 UTC\n"), expected)
        XCTAssertNotNil(TokenExpiryParser.parse("2027-01-03"))
        XCTAssertNil(TokenExpiryParser.parse(""))
        XCTAssertNil(TokenExpiryParser.parse("never"))
        XCTAssertEqual(VaultResponseHeaders(["GitHub-Authentication-Token-Expiration": "2027-01-03 18:13:20 UTC"]).tokenExpiresAt, expected)
        XCTAssertNil(none.tokenExpiresAt)
    }

    // MARK: - VaultStatus.record

    func testSuccessClearsBlocksAndStampsTheSync() {
        var status = VaultStatus(blockedBy: .tokenRejected, rateLimitedUntil: now)
        status.record(.success, at: now, tokenExpiresAt: now.addingTimeInterval(86_400 * 30))
        XCTAssertEqual(status.lastSuccessAt, now)
        XCTAssertNil(status.blockedBy)
        XCTAssertNil(status.rateLimitedUntil)
        XCTAssertEqual(status.tokenExpiresAt, now.addingTimeInterval(86_400 * 30))
        XCTAssertNil(status.lastProblem)
    }

    func testFileNotFoundCountsAsAWorkingConnection() {
        var status = VaultStatus()
        status.record(.fileNotFound, at: now)
        XCTAssertEqual(status.lastSuccessAt, now)
        XCTAssertNil(status.lastProblem, "no plan data yet is information, not a problem")
    }

    func testLoudOutcomeBlocksAndQuietOnesDont() {
        var status = VaultStatus(lastSuccessAt: now.addingTimeInterval(-600))
        status.record(.offline, at: now)
        XCTAssertNil(status.blockedBy)
        XCTAssertEqual(status.lastSuccessAt, now.addingTimeInterval(-600), "offline keeps the last sync time")
        XCTAssertEqual(status.lastProblem, .offline)
        status.record(.serverError(status: 502), at: now)
        XCTAssertNil(status.blockedBy)
        status.record(.authFailed(.tokenRejected), at: now)
        XCTAssertEqual(status.blockedBy, .tokenRejected)
        // A response without an expiry header keeps the known expiry.
        let expiry = now.addingTimeInterval(86_400)
        status.record(.offline, at: now, tokenExpiresAt: expiry)
        status.record(.offline, at: now, tokenExpiresAt: nil)
        XCTAssertEqual(status.tokenExpiresAt, expiry)
    }

    // MARK: - Gate and banner

    private func state(enabled: Bool = true, configured: Bool = true, hasToken: Bool = true, _ status: VaultStatus = VaultStatus()) -> VaultConnectionState {
        VaultConnectionState(enabled: enabled, configured: configured, hasToken: hasToken, status: status)
    }

    func testRequestGate() {
        XCTAssertEqual(state().requestGate(now: now), .allowed)
        XCTAssertEqual(state(enabled: false).requestGate(now: now), .disabled)
        XCTAssertEqual(state(configured: false).requestGate(now: now), .notConfigured)
        XCTAssertEqual(state(hasToken: false).requestGate(now: now), .noToken)
        XCTAssertEqual(state(VaultStatus(blockedBy: .forbidden)).requestGate(now: now), .blockedByAuth(.forbidden))
        let until = now.addingTimeInterval(120)
        XCTAssertEqual(state(VaultStatus(rateLimitedUntil: until)).requestGate(now: now), .rateLimited(until: until))
        // spec: nothing is sent for 120 s, then requests resume.
        XCTAssertEqual(state(VaultStatus(rateLimitedUntil: until)).requestGate(now: now.addingTimeInterval(119)), .rateLimited(until: until))
        XCTAssertEqual(state(VaultStatus(rateLimitedUntil: until)).requestGate(now: now.addingTimeInterval(121)), .allowed)
    }

    func testBannerOnlyWhileEnabledAndOnlyForLoudReasons() {
        XCTAssertNil(state().bannerReason(now: now))
        XCTAssertNil(state(enabled: false, VaultStatus(blockedBy: .tokenRejected)).bannerReason(now: now))
        XCTAssertNil(state(enabled: false, hasToken: false).bannerReason(now: now))
        XCTAssertEqual(state(VaultStatus(blockedBy: .tokenRejected)).bannerReason(now: now), .authProblem(.tokenRejected))
        XCTAssertEqual(state(VaultStatus(blockedBy: .repositoryNotFound)).bannerReason(now: now), .authProblem(.repositoryNotFound))
        // Restored on a new phone: configured, enabled, no token.
        XCTAssertEqual(state(hasToken: false).bannerReason(now: now), .tokenMissing)
        // Never for quiet problems.
        for quiet: VaultOutcome in [.offline, .serverError(status: 500), .rateLimited(until: now.addingTimeInterval(60)), .fileNotFound, .conflict] {
            var status = VaultStatus()
            status.record(quiet, at: now)
            XCTAssertNil(state(status).bannerReason(now: now), "\(quiet)")
            XCTAssertFalse(state(status).needsAttention(now: now))
        }
    }

    func testExpiryCountdownAndBannerInTheLastFourteenDays() {
        let tenDays = VaultStatus(tokenExpiresAt: now.addingTimeInterval(86_400 * 10 + 3600))
        XCTAssertEqual(state(tenDays).daysUntilTokenExpiry(now: now), 10)
        XCTAssertEqual(state(tenDays).bannerReason(now: now), .tokenExpiring(days: 10))

        let fourteen = VaultStatus(tokenExpiresAt: now.addingTimeInterval(86_400 * 14 + 60))
        XCTAssertEqual(state(fourteen).bannerReason(now: now), .tokenExpiring(days: 14))
        let fifteen = VaultStatus(tokenExpiresAt: now.addingTimeInterval(86_400 * 15 + 60))
        XCTAssertNil(state(fifteen).bannerReason(now: now))

        let expired = VaultStatus(tokenExpiresAt: now.addingTimeInterval(-3600))
        XCTAssertEqual(state(expired).bannerReason(now: now), .tokenExpiring(days: 0))

        // Unknown expiry: no countdown, no warning.
        XCTAssertNil(state().daysUntilTokenExpiry(now: now))
        XCTAssertNil(state().bannerReason(now: now))

        // A loud problem outranks the countdown.
        var both = tenDays
        both.blockedBy = .tokenRejected
        XCTAssertEqual(state(both).bannerReason(now: now), .authProblem(.tokenRejected))
    }

    func testStatusStorePersistsRateLimitAcrossLaunches() async throws {
        let directory = try makeTemporaryDirectory()
        let until = now.addingTimeInterval(120)
        let first = VaultStatusStore(directory: directory)
        await first.record(.rateLimited(until: until), at: now, tokenExpiresAt: nil)

        let relaunched = VaultStatusStore(directory: directory)
        let status = await relaunched.current()
        XCTAssertEqual(status.rateLimitedUntil, until)
        XCTAssertEqual(state(status).requestGate(now: now.addingTimeInterval(60)), .rateLimited(until: until))

        try await relaunched.clearAuthBlock()
        try await relaunched.reset()
        let cleared = await VaultStatusStore(directory: directory).current()
        XCTAssertEqual(cleared, VaultStatus())
    }
}
