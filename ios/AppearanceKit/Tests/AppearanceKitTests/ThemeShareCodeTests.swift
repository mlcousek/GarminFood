// ThemeShareCodeTests — task 5.4 (design D11): the `GFT1.` share code
// round-trips every setting it carries, rejects garbage, tampering, other
// format versions and oversized input without ever applying anything, and
// decodes a newer build's code leniently (unknown theme -> Classic with a
// warning; unknown values -> defaults with a warning). Also the
// `garminfood://theme?c=` link and pasted share messages.

import XCTest
@testable import AppearanceKit

final class ThemeShareCodeTests: XCTestCase {

    private let scheme = "garminfood"

    private func decoded(_ code: String, file: StaticString = #filePath, line: UInt = #line) throws -> ThemeShareCode.Import {
        switch ThemeShareCode.decode(code) {
        case .success(let result):
            return result
        case .failure(let failure):
            XCTFail("expected success, got \(failure) for \(code)", file: file, line: line)
            throw failure
        }
    }

    private func failure(_ code: String) -> ThemeShareCode.Failure? {
        if case .failure(let failure) = ThemeShareCode.decode(code) { return failure }
        return nil
    }

    // MARK: Round trip

    func testRoundTripOfEveryField() throws {
        let settings = AppearanceSettings(
            themeID: "forest",
            appearance: .dark,
            macroSet: .colorBlindSafe,
            customAccent: RGBA(hex: 0x7A52C7),
            style: AppearanceStyle(cardStyle: .glass, cornerShape: .sharp, density: .compact,
                                   numberFont: .monospaced, gradientHeader: true)
        )
        let result = try decoded(ThemeShareCode.encode(settings))
        XCTAssertEqual(result.settings, settings)
        XCTAssertEqual(result.warnings, [])
    }

    func testRoundTripOfTheDefaultsAndEveryBuiltInTheme() throws {
        XCTAssertEqual(try decoded(ThemeShareCode.encode(.default)).settings, .default)
        for theme in BuiltInTheme.allCases {
            let settings = AppearanceSettings(themeID: theme.rawValue)
            let result = try decoded(ThemeShareCode.encode(settings))
            XCTAssertEqual(result.settings.themeID, theme.rawValue)
            XCTAssertEqual(result.warnings, [])
        }
    }

    func testCodeShapeIsPrefixedCompactAndURLSafe() {
        let code = ThemeShareCode.encode(AppearanceSettings(customAccent: RGBA(hex: 0x15808C)))
        XCTAssertTrue(code.hasPrefix("GFT1."), code)
        XCTAssertLessThan(code.count, 256, code)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        XCTAssertTrue(code.unicodeScalars.allSatisfy { allowed.contains($0) }, code)
        XCTAssertEqual(code.split(separator: ".").count, 3)
    }

    func testSurroundingWhitespaceIsIgnored() throws {
        let code = ThemeShareCode.encode(AppearanceSettings(themeID: "ocean"))
        XCTAssertEqual(try decoded("  \n\(code)\n ").settings.themeID, "ocean")
    }

    // MARK: Rejected input

    func testGarbageIsNotAShareCode() {
        XCTAssertEqual(failure(""), .notAShareCode)
        XCTAssertEqual(failure("hello"), .notAShareCode)
        XCTAssertEqual(failure("GFT"), .notAShareCode)
        XCTAssertEqual(failure("GFTx.abc.def"), .notAShareCode)
        XCTAssertEqual(failure("GFT-1.abc.def"), .notAShareCode)
    }

    func testAnotherFormatVersionIsRejectedAsSuch() {
        let code = ThemeShareCode.encode(.default)
        let newer = "GFT2" + code.dropFirst("GFT1".count)
        XCTAssertEqual(failure(newer), .unsupportedVersion(2))
        XCTAssertEqual(failure("GFT0.abc.def"), .unsupportedVersion(0))
    }

    func testTruncatedCodeIsCorrupted() {
        let code = ThemeShareCode.encode(AppearanceSettings(themeID: "sunset"))
        XCTAssertEqual(failure(String(code.dropLast(3))), .corrupted)
        XCTAssertEqual(failure(String(code.prefix(20))), .corrupted)
        XCTAssertEqual(failure("GFT1."), .corrupted)
        XCTAssertEqual(failure("GFT1.abc"), .corrupted)
    }

    func testTamperedPayloadFailsTheChecksum() {
        let code = ThemeShareCode.encode(AppearanceSettings(themeID: "sunset"))
        var parts = code.split(separator: ".").map(String.init)
        var payload = Array(parts[1])
        let index = payload.count / 2
        payload[index] = payload[index] == "A" ? "B" : "A"
        parts[1] = String(payload)
        XCTAssertEqual(failure(parts.joined(separator: ".")), .corrupted)
    }

    func testValidChecksumOverNonJSONIsCorrupted() {
        let notJSON = ThemeShareCode.wrap(json: Data("not json".utf8))
        XCTAssertEqual(failure(notJSON), .corrupted)
        let notAnObject = ThemeShareCode.wrap(json: Data("[1,2]".utf8))
        XCTAssertEqual(failure(notAnObject), .corrupted)
        let noTheme = ThemeShareCode.wrap(json: Data(#"{"p":"dark"}"#.utf8))
        XCTAssertEqual(failure(noTheme), .corrupted)
    }

    func testOversizedInputIsRejectedBeforeParsing() {
        let huge = "GFT1." + String(repeating: "A", count: ThemeShareCode.maximumLength) + ".00000000"
        XCTAssertEqual(failure(huge), .tooLong)
    }

    // MARK: Lenient content (a newer build's code)

    func testUnknownThemeFallsBackToClassicWithAWarning() throws {
        let code = ThemeShareCode.wrap(json: Data(#"{"t":"aurora","p":"dark","m":"legible"}"#.utf8))
        let result = try decoded(code)
        XCTAssertEqual(result.settings.themeID, BuiltInTheme.classic.rawValue)
        XCTAssertEqual(result.settings.appearance, .dark, "the rest still applies")
        XCTAssertEqual(result.settings.macroSet, .legible)
        XCTAssertEqual(result.warnings, [.unknownTheme("aurora")])
    }

    func testUnknownValuesFallBackPerFieldWithAWarning() throws {
        let json = ##"{"t":"ocean","p":"sepia","m":"ultraviolet","a":"#GGGGGG","s":{"c":"neon","r":"round","g":"yes"},"l":[1],"z":true}"##
        let result = try decoded(ThemeShareCode.wrap(json: Data(json.utf8)))
        XCTAssertEqual(result.settings.themeID, "ocean")
        XCTAssertEqual(result.settings.appearance, .system)
        XCTAssertEqual(result.settings.macroSet, .theme)
        XCTAssertNil(result.settings.customAccent)
        XCTAssertEqual(result.settings.style.cardStyle, .filled)
        XCTAssertEqual(result.settings.style.cornerShape, .round)
        XCTAssertFalse(result.settings.style.gradientHeader)
        XCTAssertEqual(result.warnings, [.ignoredUnknownValues])
    }

    func testUnknownKeysAloneAreIgnoredSilently() throws {
        let result = try decoded(ThemeShareCode.wrap(json: Data(#"{"t":"slate","l":{"today":[]},"future":42}"#.utf8)))
        XCTAssertEqual(result.settings.themeID, "slate")
        XCTAssertEqual(result.warnings, [])
    }

    func testCustomAccentTravelsRawAndIsRefittedOnTheReceivingPhone() throws {
        let yellow = RGBA(hex: 0xFFFF00)
        let result = try decoded(ThemeShareCode.encode(AppearanceSettings(themeID: "teal", customAccent: yellow)))
        XCTAssertEqual(result.settings.customAccent, yellow)
        let palette = PaletteResolver.resolve(
            theme: ThemeCatalog.themeOrDefault(id: result.settings.themeID),
            requestedScheme: .light,
            customAccent: result.settings.customAccent
        )
        XCTAssertTrue(palette.adjustedRoles.contains(.accent))
        XCTAssertNotEqual(palette[.accent], .rgb(yellow))
    }

    // MARK: Link and paste

    func testLinkRoundTrip() throws {
        let code = ThemeShareCode.encode(AppearanceSettings(themeID: "berry"))
        let url = try XCTUnwrap(ThemeShareCode.link(for: code, scheme: scheme))
        XCTAssertEqual(url.absoluteString, "garminfood://theme?c=\(code)")
        XCTAssertEqual(ThemeShareCode.code(fromLink: url, scheme: scheme), code)
    }

    func testOtherLinksAreNotThemeLinks() throws {
        XCTAssertNil(ThemeShareCode.code(fromLink: try XCTUnwrap(URL(string: "garminfood://logFood")), scheme: scheme))
        XCTAssertNil(ThemeShareCode.code(fromLink: try XCTUnwrap(URL(string: "https://theme?c=GFT1.a.b")), scheme: scheme))
        XCTAssertNil(ThemeShareCode.code(fromLink: try XCTUnwrap(URL(string: "garminfood://theme")), scheme: scheme))
    }

    func testPastedShareMessageFindsTheCodeOrLink() throws {
        let code = ThemeShareCode.encode(AppearanceSettings(themeID: "gold"))
        let link = try XCTUnwrap(ThemeShareCode.link(for: code, scheme: scheme)).absoluteString

        let messages = [
            code,
            "My GarminFood theme:\n\(code)",
            "Open \(link) on your phone",
            link
        ]
        for message in messages {
            guard case .success(let result) = ThemeShareCode.decode(pasted: message, scheme: scheme) else {
                return XCTFail("no code found in \(message)")
            }
            XCTAssertEqual(result.settings.themeID, "gold")
        }
        guard case .failure(.notAShareCode) = ThemeShareCode.decode(pasted: "just some text", scheme: scheme) else {
            return XCTFail("plain text must not decode")
        }
    }
}
