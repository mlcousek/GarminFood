// OAuth1SignerTests.swift
//
// Pins OAuth1Signer's percent-encoding and signature construction against
// known-good vectors derived by RUNNING the actual Node reference
// implementation (`tools/lib/garmin-auth.mjs`'s `pctEncode`/`oauth1Header`)
// by hand, with fixed fake nonce/timestamp/consumer/token inputs instead of
// its normal random/live ones, so the output is deterministic and
// reproducible. None of these values are real Garmin credentials -- they
// are fabricated solely to pin the algorithm.
//
// The exact script run (Node v22.12.0, no network access) was:
//
//     import { createHmac } from 'crypto';
//     function pctEncode(s) {
//         return encodeURIComponent(s).replace(/[!'()*]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
//     }
//     function oauth1Header(method, url, consumer, token, tokenSecret, fixedNonce, fixedTimestamp) {
//         const params = {
//             oauth_consumer_key: consumer.consumer_key,
//             oauth_token: token,
//             oauth_nonce: fixedNonce,
//             oauth_timestamp: fixedTimestamp,
//             oauth_signature_method: 'HMAC-SHA1',
//             oauth_version: '1.0',
//         };
//         const paramStr = Object.keys(params).sort()
//             .map(k => `${pctEncode(k)}=${pctEncode(params[k])}`).join('&');
//         const base = [method.toUpperCase(), pctEncode(url), pctEncode(paramStr)].join('&');
//         const key = `${pctEncode(consumer.consumer_secret)}&${pctEncode(tokenSecret)}`;
//         const signature = createHmac('sha1', key).update(base).digest('base64');
//         params.oauth_signature = signature;
//         const header = 'OAuth ' + Object.keys(params).sort()
//             .map(k => `${pctEncode(k)}="${pctEncode(params[k])}"`).join(', ');
//         return { paramStr, base, key, signature, header };
//     }
//
//     const consumer = { consumer_key: 'fake_consumer_key', consumer_secret: 'fake_consumer_secret' };
//     oauth1Header('POST', 'https://connectapi.garmin.com/oauth-service/oauth/exchange/user/2.0',
//         consumer, 'fake_oauth_token', 'fake_oauth_token_secret',
//         '0123456789abcdef0123456789abcdef', '1700000000');
//
// ...which printed (verbatim, this is the actual captured output):
//
//   paramStr: oauth_consumer_key=fake_consumer_key&oauth_nonce=0123456789abcdef0123456789abcdef&oauth_signature_method=HMAC-SHA1&oauth_timestamp=1700000000&oauth_token=fake_oauth_token&oauth_version=1.0
//   base:     POST&https%3A%2F%2Fconnectapi.garmin.com%2Foauth-service%2Foauth%2Fexchange%2Fuser%2F2.0&oauth_consumer_key%3Dfake_consumer_key%26oauth_nonce%3D0123456789abcdef0123456789abcdef%26oauth_signature_method%3DHMAC-SHA1%26oauth_timestamp%3D1700000000%26oauth_token%3Dfake_oauth_token%26oauth_version%3D1.0
//   key:      fake_consumer_secret&fake_oauth_token_secret
//   signature: O62tySMX9b0PxPj1SLLisDc7o8E=
//   header:   OAuth oauth_consumer_key="fake_consumer_key", oauth_nonce="0123456789abcdef0123456789abcdef", oauth_signature="O62tySMX9b0PxPj1SLLisDc7o8E%3D", oauth_signature_method="HMAC-SHA1", oauth_timestamp="1700000000", oauth_token="fake_oauth_token", oauth_version="1.0"
//
// If OAuth1Signer.authorizationHeader ever stops producing this exact
// header string for this exact input, the port has diverged from the
// reference algorithm -- treat that as a real regression, not a flaky test.

import XCTest
@testable import GarminKit

final class OAuth1SignerTests: XCTestCase {
    private let fakeConsumer = OAuth1Signer.Consumer(consumerKey: "fake_consumer_key", consumerSecret: "fake_consumer_secret")

    func testAuthorizationHeaderMatchesNodeReferenceVector() {
        let header = OAuth1Signer.authorizationHeader(
            method: "POST",
            url: "https://connectapi.garmin.com/oauth-service/oauth/exchange/user/2.0",
            consumer: fakeConsumer,
            token: "fake_oauth_token",
            tokenSecret: "fake_oauth_token_secret",
            nonce: "0123456789abcdef0123456789abcdef",
            timestamp: "1700000000"
        )

        let expected = "OAuth oauth_consumer_key=\"fake_consumer_key\", " +
            "oauth_nonce=\"0123456789abcdef0123456789abcdef\", " +
            "oauth_signature=\"O62tySMX9b0PxPj1SLLisDc7o8E%3D\", " +
            "oauth_signature_method=\"HMAC-SHA1\", " +
            "oauth_timestamp=\"1700000000\", " +
            "oauth_token=\"fake_oauth_token\", " +
            "oauth_version=\"1.0\""

        XCTAssertEqual(header, expected)
    }

    func testAuthorizationHeaderIsDeterministicForSameInputs() {
        let header1 = OAuth1Signer.authorizationHeader(
            method: "get", // lowercase on purpose -- must be normalized to GET
            url: "https://connectapi.garmin.com/x",
            consumer: fakeConsumer,
            token: "t",
            tokenSecret: "s",
            nonce: "n",
            timestamp: "123"
        )
        let header2 = OAuth1Signer.authorizationHeader(
            method: "GET",
            url: "https://connectapi.garmin.com/x",
            consumer: fakeConsumer,
            token: "t",
            tokenSecret: "s",
            nonce: "n",
            timestamp: "123"
        )
        XCTAssertEqual(header1, header2)
    }

    // MARK: - Percent-encoding, verified against the same Node `pctEncode`
    // run with the following tricky inputs (also captured verbatim):
    //
    //   "hello world"          -> "hello%20world"
    //   "a!b'c(d)e*f~g-h_i.j"  -> "a%21b%27c%28d%29e%2Af~g-h_i.j"
    //   "café" (NFD: cafe + combining acute U+0301) -> "cafe%CC%81"
    //   "key=value&other=1"    -> "key%3Dvalue%26other%3D1"
    //   "10/20:30"              -> "10%2F20%3A30"

    func testPercentEncodingSpace() {
        XCTAssertEqual(OAuth1PercentEncoding.encode("hello world"), "hello%20world")
    }

    func testPercentEncodingForcesEncodedURIComponentSurvivors() {
        // encodeURIComponent alone would leave ! ' ( ) * unescaped; OAuth1
        // (RFC 5849 3.6) requires them percent-encoded too, uppercase hex.
        XCTAssertEqual(OAuth1PercentEncoding.encode("a!b'c(d)e*f~g-h_i.j"), "a%21b%27c%28d%29e%2Af~g-h_i.j")
    }

    func testPercentEncodingMultiByteUTF8() {
        // "café" in NFD form: 'cafe' + COMBINING ACUTE ACCENT (U+0301),
        // whose UTF-8 encoding is the two bytes 0xCC 0x81.
        let input = "cafe\u{0301}"
        XCTAssertEqual(OAuth1PercentEncoding.encode(input), "cafe%CC%81")
    }

    func testPercentEncodingReservedURLCharacters() {
        XCTAssertEqual(OAuth1PercentEncoding.encode("key=value&other=1"), "key%3Dvalue%26other%3D1")
        XCTAssertEqual(OAuth1PercentEncoding.encode("10/20:30"), "10%2F20%3A30")
    }

    func testPercentEncodingLeavesUnreservedCharactersAlone() {
        let unreserved = "ABCXYZabcxyz0129-._~"
        XCTAssertEqual(OAuth1PercentEncoding.encode(unreserved), unreserved)
    }

    func testNonceIsThirtyTwoLowercaseHexCharacters() {
        let nonce = OAuth1Signer.randomNonce()
        XCTAssertEqual(nonce.count, 32)
        XCTAssertTrue(nonce.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    func testNonceIsNotConstantAcrossCalls() {
        // Not a proof of randomness, just a guard against an accidental
        // fixed-nonce regression, which would break OAuth1's replay
        // protection silently.
        let nonces = Set((0..<20).map { _ in OAuth1Signer.randomNonce() })
        XCTAssertEqual(nonces.count, 20)
    }
}
