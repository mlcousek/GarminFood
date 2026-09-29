// ContractPrimitivesTests.swift
//
// The building blocks of tolerant decoding (design D2, tasks 2.2):
// `OpenEnum` (unknown values, aliases), `LossyArray`/`LossyMap` (dropped
// elements recorded, the rest kept), `LocalizedText` (cs -> cz -> en ->
// first; plain strings), and the calendar formats (`LocalDate`, `ISOWeek`
// with W53 and year boundaries, `ClockTime`).

import XCTest
@testable import TrainingCore

final class ContractPrimitivesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String, collector: DecodeIssueCollector? = nil) throws -> T {
        let decoder = JSONDecoder()
        if let collector { decoder.userInfo[DecodeIssueCollector.userInfoKey] = collector }
        return try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: OpenEnum

    func testOpenEnumKnownAndUnknown() throws {
        XCTAssertEqual(try decode(OpenEnum<SessionType>.self, "\"easy\""), .known(.easy))
        let hike = try decode(OpenEnum<SessionType>.self, "\"hike\"")
        XCTAssertEqual(hike, .unknown("hike"))
        XCTAssertNil(hike.known)
        XCTAssertEqual(hike.rawValue, "hike")
        XCTAssertEqual(try decode(OpenEnum<OptionCode>.self, "\"R\""), .known(.r))
        XCTAssertEqual(try decode(OpenEnum<StepSide>.self, "\"L\""), .known(.left))
        XCTAssertEqual(try decode(OpenEnum<MorningLight>.self, "\"amber\"").known?.option, .a)
    }

    func testScheduleKindAcceptsSnakeCaseAliases() throws {
        XCTAssertEqual(try decode(OpenEnum<ScheduleKind>.self, "\"weeklyCount\""), .known(.weeklyCount))
        XCTAssertEqual(try decode(OpenEnum<ScheduleKind>.self, "\"weekly_count\""), .known(.weeklyCount))
        XCTAssertEqual(try decode(OpenEnum<ScheduleKind>.self, "\"every_n_weeks\""), .known(.everyNWeeks))
        XCTAssertEqual(try decode(OpenEnum<ScheduleKind>.self, "\"with_sessions\""), .known(.withSessions))
    }

    // MARK: Lossy

    func testLossyArrayDropsAndRecordsBrokenElements() throws {
        let collector = DecodeIssueCollector()
        let json = """
        [{"id": "a"}, {"slot": "am"}, {"id": ""}, {"id": "d", "type": "hike"}]
        """
        let list = try decode(LossyArray<Session>.self, json, collector: collector)
        XCTAssertEqual(list.elements.map(\.id), ["a", "d"])
        XCTAssertEqual(list.elements.last?.type, .unknown("hike"))
        let issues = collector.issues
        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues.issues.map(\.element), ["session", "session"])
        XCTAssertEqual(issues.issues.first?.reason, "missing id")
        XCTAssertEqual(issues.summary, "session skipped x2: missing id")
    }

    func testLossyMapDropsBrokenValues() throws {
        let collector = DecodeIssueCollector()
        let json = """
        {"a": {"date": "2030-10-21", "values": {"x": 1}}, "b": {"date": "21. 10. 2030"}}
        """
        let map = try decode(LossyMap<TestResultEntry>.self, json, collector: collector)
        XCTAssertEqual(Array(map.values.keys), ["a"])
        XCTAssertEqual(collector.issues.issues.first?.reason, "malformed date")
    }

    func testLenientFieldsTreatNullMissingAndWrongTypeAlike() throws {
        let targets = try decode(Targets.self, #"{"km": null, "min": "45", "hrMax": 144.0, "zone": 2}"#)
        XCTAssertNil(targets.km)
        XCTAssertNil(targets.min)
        XCTAssertEqual(targets.hrMax, 144)
        XCTAssertNil(targets.zone)
        let empty = try decode(Targets.self, "{}")
        XCTAssertTrue(empty.isEmpty)
    }

    func testScalarTextReadsStringsAndNumbers() throws {
        XCTAssertEqual(try decode(ScalarText.self, "8").text, "8")
        XCTAssertEqual(try decode(ScalarText.self, "\"8-12\"").text, "8-12")
        XCTAssertEqual(try decode(ScalarText.self, "2.5").text, "2.5")
    }

    // MARK: LocalizedText

    func testLocalizedTextLanguageFallback() throws {
        let text = try decode(LocalizedText.self, #"{"en": "Easy 8 km flat", "cz": "Klidně 8 km po rovině"}"#)
        XCTAssertEqual(text.resolved(.english), "Easy 8 km flat")
        XCTAssertEqual(text.resolved(.czech), "Klidně 8 km po rovině")

        let withCs = try decode(LocalizedText.self, #"{"en": "E", "cz": "Z", "cs": "C"}"#)
        XCTAssertEqual(withCs.resolved(.czech), "C")

        let englishOnly = try decode(LocalizedText.self, #"{"en": "Only English", "cz": ""}"#)
        XCTAssertEqual(englishOnly.resolved(.czech), "Only English")

        let czechOnly = try decode(LocalizedText.self, #"{"en": null, "cz": "Jen česky"}"#)
        XCTAssertEqual(czechOnly.resolved(.english), "Jen česky")

        let other = try decode(LocalizedText.self, #"{"de": "Deutsch", "fr": "Français"}"#)
        XCTAssertEqual(other.resolved(.english), "Deutsch")
    }

    func testPlainStringShowsAsIsInBothLanguages() throws {
        let text = try decode(LocalizedText.self, "\"5 × 45 s, twice a day\"")
        XCTAssertEqual(text.resolved(.english), "5 × 45 s, twice a day")
        XCTAssertEqual(text.resolved(.czech), "5 × 45 s, twice a day")
    }

    func testLanguageFromPreferredLocalizations() {
        XCTAssertEqual(TrainingLanguage.from(preferredLocalizations: ["cs"]), .czech)
        XCTAssertEqual(TrainingLanguage.from(preferredLocalizations: ["cs-CZ", "en"]), .czech)
        XCTAssertEqual(TrainingLanguage.from(preferredLocalizations: ["en"]), .english)
        XCTAssertEqual(TrainingLanguage.from(preferredLocalizations: ["de"]), .english)
        XCTAssertEqual(TrainingLanguage.from(preferredLocalizations: []), .english)
    }

    // MARK: Dates

    func testLocalDateParsingAndArithmetic() {
        XCTAssertNotNil(LocalDate("2030-10-23"))
        XCTAssertNil(LocalDate("2030-10-32"))
        XCTAssertNil(LocalDate("2030-02-29"))
        XCTAssertNotNil(LocalDate("2028-02-29"))
        XCTAssertNil(LocalDate("2030-1-5"))
        XCTAssertNil(LocalDate("23. 10. 2030"))
        let date = D.date("2030-10-23")
        XCTAssertEqual(date.isoWeekday, 3) // Wednesday
        XCTAssertEqual(date.adding(days: 10).description, "2030-11-02")
        XCTAssertEqual(D.date("2030-12-31").adding(days: 1).description, "2031-01-01")
        XCTAssertEqual(D.date("2028-02-28").adding(days: 1).description, "2028-02-29")
        XCTAssertEqual(D.date("1970-01-01").dayNumber, 0)
        XCTAssertEqual(D.date("1970-01-01").isoWeekday, 4) // Thursday
        XCTAssertEqual(date.days(until: D.date("2031-06-21")), 241)
        XCTAssertLessThan(D.date("2030-10-22"), date)
    }

    func testLocalDateFromInstantUsesTheGivenZone() throws {
        let prague = try XCTUnwrap(TimeZone(identifier: "Europe/Prague"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        // 2030-10-20 23:30 UTC is already 21 Oct in Prague (UTC+2).
        let instant = Date(timeIntervalSince1970: TimeInterval(D.date("2030-10-20").dayNumber * 86_400 + 23 * 3600 + 1800))
        XCTAssertEqual(LocalDate(date: instant, timeZone: utc).description, "2030-10-20")
        XCTAssertEqual(LocalDate(date: instant, timeZone: prague).description, "2030-10-21")
    }

    func testISOWeekAcrossYearBoundaries() {
        // 2026 starts on a Thursday, so it has a W53.
        XCTAssertEqual(ISOWeek(containing: D.date("2026-12-28")).description, "2026-W53")
        XCTAssertEqual(ISOWeek(containing: D.date("2027-01-01")).description, "2026-W53")
        XCTAssertEqual(ISOWeek(containing: D.date("2027-01-04")).description, "2027-W01")
        XCTAssertEqual(D.week("2026-W53").monday.description, "2026-12-28")
        XCTAssertNil(ISOWeek("2027-W53"))
        // 29 Dec 2025 belongs to 2026-W01.
        XCTAssertEqual(ISOWeek(containing: D.date("2025-12-29")).description, "2026-W01")
        XCTAssertEqual(D.week("2030-W43").monday.description, "2030-10-21")
        XCTAssertEqual(D.week("2030-W43").sunday.description, "2030-10-27")
        XCTAssertEqual(D.week("2026-W53").adding(weeks: 1).description, "2027-W01")
        XCTAssertEqual(D.week("2027-W01").adding(weeks: -1).description, "2026-W53")
        XCTAssertTrue(D.week("2030-W43").contains(D.asOf))
        XCTAssertNil(ISOWeek("2030-43"))
        XCTAssertNil(ISOWeek("2030-W54"))
    }

    func testClockTime() {
        XCTAssertEqual(ClockTime("05:10")?.description, "05:10")
        XCTAssertNil(ClockTime("5:10"))
        XCTAssertNil(ClockTime("24:00"))
        XCTAssertLessThan(ClockTime("05:10")!, ClockTime("17:30")!)
    }
}
