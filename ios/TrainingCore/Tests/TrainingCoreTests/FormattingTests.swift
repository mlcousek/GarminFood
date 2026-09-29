// FormattingTests.swift
//
// Every string table entry resolves in English and Czech, and the
// formatters produce the design's text in both languages (tasks 3.2):
// targets, every step kind, fuel, countdowns (Czech plural forms),
// schedules (all five kinds), dates.

import XCTest
@testable import TrainingCore

final class TrainingTextTests: XCTestCase {
    func testEveryKeyResolvesInBothLanguages() {
        for language in TrainingLanguage.allCases {
            let text = TrainingText(language)
            for key in TrainingKey.allCases {
                XCTAssertTrue(text.hasEntry(key), "\(key) missing in \(language)")
                XCTAssertFalse(text(key).isEmpty, "\(key) empty in \(language)")
            }
        }
    }

    func testCzechIsActuallyCzech() {
        let czech = TrainingText(.czech)
        XCTAssertEqual(czech(.stateRestDayTitle), "Den volna")
        XCTAssertEqual(czech(.optionNotIdentified), "Možnost nerozpoznána")
        XCTAssertEqual(czech.format(.weekRunOfTarget, "34", "60"), "Běh 34 z 60 km")
    }

    func testCzechPluralForms() {
        let czech = TrainingText(.czech)
        XCTAssertEqual(czech.format(.countdownInDays, 1), "za 1 den")
        XCTAssertEqual(czech.format(.countdownInDays, 3), "za 3 dny")
        XCTAssertEqual(czech.format(.countdownInDays, 23), "za 23 dní")
        XCTAssertEqual(czech.format(.scheduleEveryNWeeks, 2), "každé 2 týdny")
        XCTAssertEqual(czech.format(.scheduleEveryNWeeks, 5), "každých 5 týdnů")
        XCTAssertEqual(czech.format(.habitRecordedDays, 9), "za 9 zaznamenaných dní")
        let english = TrainingText(.english)
        XCTAssertEqual(english.format(.countdownInDays, 1), "in 1 day")
        XCTAssertEqual(english.format(.countdownInDays, 23), "in 23 days")
    }

    func testPercentSignSurvivesFormatting() {
        XCTAssertEqual(TrainingText(.english).format(.habitWindow, 25, 28, 89), "25 of 28 · 89 %")
        XCTAssertEqual(TrainingText(.czech).format(.habitWindow, 25, 28, 89), "25 z 28 · 89 %")
    }
}

final class FormattingTests: XCTestCase {
    private let english = TrainingText(.english)
    private let czech = TrainingText(.czech)

    private func step(_ kind: StepKind, _ configure: (inout Step) -> Void = { _ in }) -> Step {
        var step = Step(kind: kind)
        configure(&step)
        return step
    }

    // MARK: Numbers and dates

    func testNumbersFollowTheLanguage() {
        XCTAssertEqual(NumberText.distance(10.1, .english), "10.1 km")
        XCTAssertEqual(NumberText.distance(10.1, .czech), "10,1 km")
        XCTAssertEqual(NumberText.distance(12, .czech), "12 km")
        XCTAssertEqual(NumberText.duration(minutes: 45), "45 min")
        XCTAssertEqual(NumberText.duration(minutes: 60), "1 h")
        XCTAssertEqual(NumberText.duration(minutes: 90), "1 h 30 min")
        XCTAssertEqual(NumberText.seconds(45), "45 s")
        XCTAssertEqual(NumberText.seconds(120), "2 min")
    }

    func testDates() {
        let en = DateText(.english)
        let cs = DateText(.czech)
        XCTAssertEqual(en.short(D.date("2030-10-20")), "Sun 20 Oct")
        XCTAssertEqual(cs.short(D.date("2030-10-20")), "ne 20. 10.")
        XCTAssertEqual(en.weekdayAndDay(D.asOf), "Wed 23")
        XCTAssertEqual(cs.weekdayAndDay(D.asOf), "st 23.")
        XCTAssertEqual(en.range(D.date("2030-10-21"), D.date("2030-10-27")), "21–27 Oct")
        XCTAssertEqual(en.range(D.date("2030-10-28"), D.date("2030-11-03")), "28 Oct – 3 Nov")
        XCTAssertEqual(cs.range(D.date("2030-10-21"), D.date("2030-10-27")), "21.–27. 10.")
        XCTAssertEqual(en.monthTitle(year: 2030, month: 10), "October 2030")
        XCTAssertEqual(cs.monthTitle(year: 2030, month: 10), "Říjen 2030")
        XCTAssertEqual(en.weekdayHeaders.first, "Mon")
        XCTAssertEqual(cs.weekdayHeaders.first, "po")
        XCTAssertEqual(en.weekdayHeaders.count, 7)
    }

    // MARK: Steps (spec "Workout steps")

    func testWarmUpAndIntervalSteps() {
        let steps = StepFormatter(text: english)
        XCTAssertEqual(steps.line(step(.warmup) { $0.min = 10; $0.zone = "Z1" }), "Warm-up 10 min · Z1")
        XCTAssertEqual(steps.line(step(.interval) { $0.times = 4; $0.min = 5; $0.zone = "Z3"; $0.recoverMin = 2 }), "4 × 5 min · Z3, 2 min recovery")
        XCTAssertEqual(steps.line(step(.interval) { $0.times = 3; $0.min = 8; $0.hrLo = 150; $0.hrHi = 158; $0.recoverSec = 90 }), "3 × 8 min · 150–158 bpm, 90 s recovery")
        XCTAssertEqual(StepFormatter(text: czech).line(step(.warmup) { $0.min = 10; $0.zone = "z1" }), "Rozklusání 10 min · Z1")
        XCTAssertEqual(StepFormatter(text: czech).line(step(.interval) { $0.times = 4; $0.min = 5; $0.zone = "Z3"; $0.recoverMin = 2 }), "4 × 5 min · Z3, 2 min volně")
    }

    func testEveryOtherStepKind() {
        let steps = StepFormatter(text: english)
        XCTAssertEqual(steps.line(step(.active) { $0.km = 10; $0.zone = "Z1"; $0.hrMax = 140 }), "10 km · Z1 · ≤140 bpm")
        XCTAssertEqual(steps.line(step(.active) { $0.km = 6; $0.zone = "Z1"; $0.pace = "6:15"; $0.note = "flat route only" }), "6 km · Z1 · 6:15 /km · flat route only")
        XCTAssertEqual(steps.line(step(.recovery) { $0.min = 2 }), "Recovery 2 min")
        XCTAssertEqual(steps.line(step(.cooldown) { $0.km = 2 }), "Cool-down 2 km")
        XCTAssertEqual(steps.line(step(.rest) { $0.min = 2 }), "Rest 2 min")
        XCTAssertEqual(steps.line(step(.exercise) { $0.name = "Calf raises"; $0.sets = 3; $0.reps = ScalarText("15"); $0.tempo = "slow" }), "Calf raises · 3 × 15 · slow")
        XCTAssertEqual(steps.line(step(.exercise) { $0.name = "Seated calf raise"; $0.sets = 3; $0.reps = ScalarText("8-12"); $0.tempo = "3-0-3"; $0.load = ScalarText("40 kg") }), "Seated calf raise · 3 × 8-12 · 3-0-3 · 40 kg")
        XCTAssertEqual(steps.line(step(.hold) { $0.sec = 45; $0.side = .known(.left) }), "Hold 45 s · left")
        XCTAssertEqual(steps.line(step(.hold) { $0.sec = 45; $0.sets = 3; $0.side = .known(.each) }), "Hold 3 × 45 s · each side")
        XCTAssertEqual(StepFormatter(text: czech).line(step(.hold) { $0.sec = 45; $0.side = .known(.left) }), "Výdrž 45 s · levá")
    }

    // MARK: Fuel and countdowns

    func testFuelLines() throws {
        let fuelJSON = #"{"kind": "carb-load", "raceId": "r", "carbsGPerKg": 8, "carbsG": 680}"#
        let fuel = try JSONDecoder().decode(DayFuel.self, from: Data(fuelJSON.utf8))
        XCTAssertEqual(FuelFormatter(text: english).dayLine(fuel), "Carb load: 680 g carbs (8 g/kg)")
        XCTAssertEqual(FuelFormatter(text: czech).dayLine(fuel), "Nasycení sacharidy: 680 g sacharidů (8 g/kg)")
        let session = try JSONDecoder().decode(SessionFuel.self, from: Data(#"{"carbsPerHour": 60}"#.utf8))
        XCTAssertEqual(FuelFormatter(text: english).sessionLine(session), "Fuel: 60 g carbs/h")
        XCTAssertNil(FuelFormatter(text: english).dayLine(nil))
    }

    func testCountdowns() {
        let en = CountdownFormatter(text: english)
        XCTAssertEqual(en.phrase(days: 0, approximate: false), "today")
        XCTAssertEqual(en.phrase(days: 1, approximate: false), "tomorrow")
        XCTAssertEqual(en.phrase(days: 23, approximate: false), "in 23 days")
        XCTAssertEqual(en.phrase(days: 23, approximate: true), "in about 23 days")
        let cs = CountdownFormatter(text: czech)
        XCTAssertEqual(cs.phrase(days: 23, approximate: false), "za 23 dní")
        XCTAssertEqual(cs.phrase(days: 2, approximate: true), "zhruba za 2 dny")
        XCTAssertEqual(cs.phrase(days: 1, approximate: false), "zítra")
    }

    // MARK: Schedules

    private func schedule(_ json: String) throws -> HabitSchedule {
        try JSONDecoder().decode(HabitSchedule.self, from: Data(json.utf8))
    }

    func testEveryScheduleKind() throws {
        let en = ScheduleFormatter(text: english)
        XCTAssertEqual(en.line(try schedule(#"{"kind": "daily", "perDay": 2}"#)), "2× a day")
        XCTAssertEqual(en.line(try schedule(#"{"kind": "daily", "perDay": 1}"#)), "Every day")
        XCTAssertEqual(en.line(try schedule(#"{"kind": "weekly", "days": ["MO", "TH"]}"#)), "Mon and Thu")
        XCTAssertEqual(en.line(try schedule(#"{"kind": "weeklyCount", "times": 1}"#)), "Once a week")
        XCTAssertEqual(en.line(try schedule(#"{"kind": "weekly_count", "times": 2}"#)), "2× a week")
        XCTAssertEqual(en.line(try schedule(#"{"kind": "everyNWeeks", "n": 2, "day": "SA", "anchor": "2030-11-30"}"#)), "every 2 weeks · Sat")
        XCTAssertEqual(en.line(try schedule(#"{"kind": "withSessions", "sport": "run", "types": ["easy"]}"#)), "After sessions: easy")
        XCTAssertNil(en.line(try schedule(#"{"kind": "lunar"}"#)))

        let cs = ScheduleFormatter(text: czech)
        XCTAssertEqual(cs.line(try schedule(#"{"kind": "daily", "perDay": 2}"#)), "2× denně")
        // Czech typography binds the one-letter conjunction with a no-break space
        // (U+00A0); which spaces Foundation uses is CLDR data, so compare them as one.
        XCTAssertEqual(cs.line(try schedule(#"{"kind": "weekly", "days": ["MO", "TH"]}"#))?.replacingOccurrences(of: "\u{00A0}", with: " "), "po a čt")
        XCTAssertEqual(cs.line(try schedule(#"{"kind": "everyNWeeks", "n": 2, "day": "SA"}"#)), "každé 2 týdny · so")
    }

    // MARK: Names

    func testUnknownTypeHasNoName() {
        XCTAssertNil(english.typeName(.unknown("hike")))
        XCTAssertEqual(english.typeName(.known(.easy)), "Easy")
        XCTAssertEqual(czech.statusName(.known(.missed)), "Vynecháno")
        XCTAssertEqual(SportSymbol.name(.unknown("kayak")), "figure.mixed.cardio")
    }
}
