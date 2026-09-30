// TodayBuilderTests.swift
//
// Golden tests of the Today cards on the vault's example fixture (tasks
// 3.3, 1.4; spec training-today): the traffic-light day before the run,
// a red day recognised from the sport, done with the option unknown, a
// carb-load day, test and race badges, the non-happy states, habits,
// the race chip (polish-training-today: the next race of any priority,
// with the main race as a second line), the Habits card (the ladder step,
// active habits, the day's progress, the next step and what unlocks it)
// and the weekly note from last week.

import XCTest
@testable import TrainingCore

final class TodayBuilderTests: XCTestCase {
    private func builder(_ language: TrainingLanguage = .english, data: Data? = nil) throws -> TodayTrainingBuilder {
        let bytes = try data ?? Fixtures.example()
        guard case .success(let decoded) = ProjectionDecoder.decode(bytes) else {
            XCTFail("fixture did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return TodayTrainingBuilder(source: .loaded(TrainingSnapshot(projection: decoded.projection)), language: language)
    }

    // MARK: Sessions

    func testTrafficLightDayBeforeTheRun() throws {
        let model = try builder().trainingDay(on: D.asOf)
        XCTAssertNil(model.emptyState)
        XCTAssertEqual(model.dateText, "Wed 23 Oct")
        XCTAssertEqual(model.sessions.count, 1)
        let session = model.sessions[0]
        XCTAssertEqual(session.id, "2030-w43-wed-am")
        XCTAssertEqual(session.title, "Easy 10 km")
        XCTAssertEqual(session.slotText, "Morning")
        XCTAssertEqual(session.status, .planned)
        XCTAssertEqual(session.statusText, "Planned")
        XCTAssertNil(session.badge)
        XCTAssertNil(session.single)
        XCTAssertEqual(session.options.map(\.code), ["G", "A", "R"])
        XCTAssertEqual(session.options.map(\.label), ["Easy 10 km", "Easy 6 km, flat", "Bike 45 min Z1 + holds"])
        XCTAssertEqual(session.options[0].targetLines, ["10 km", "≤140 bpm · Z1"])
        XCTAssertEqual(session.options[1].targetLines, ["6 km", "≤135 bpm · Z2"])
        XCTAssertEqual(session.options[2].targetLines, ["45 min", "≤128 bpm · Z1"])
        // The vault published this morning's amber check-in: A matches it.
        XCTAssertEqual(session.options.map(\.highlight), [nil, .morningLight, nil])
        XCTAssertEqual(model.lightLine, "Morning check: Amber")
        XCTAssertEqual(session.options.map(\.watchLine), ["On Garmin calendar", "Not on Garmin calendar yet", "Couldn't send to Garmin calendar"])
        XCTAssertEqual(session.options[1].action, .openDetail(sessionID: "2030-w43-wed-am", option: "A"))
        XCTAssertEqual(session.options[1].accessibilityLabel, "Option A, Easier: Easy 6 km, flat, 6 km, ≤135 bpm · Z2. Not on Garmin calendar yet. Matches your morning check")
        XCTAssertNil(session.pendingBadge)
        XCTAssertEqual(session.compactLine, "Morning · Easy 10 km · 10 km · Planned")
    }

    func testCzechLabels() throws {
        let session = try builder(.czech).trainingDay(on: D.asOf).sessions[0]
        XCTAssertEqual(session.options[1].label, "Klidných 6 km po rovině")
        XCTAssertEqual(session.options[1].meaning, "Lehčí")
        XCTAssertEqual(session.statusText, "Naplánováno")
        XCTAssertEqual(session.options[0].watchLine, "V kalendáři Garmin")
    }

    func testRedDayRecognisedFromTheSport() throws {
        let session = try builder().trainingDay(on: D.date("2030-10-15")).sessions[0]
        XCTAssertEqual(session.status, .done)
        XCTAssertEqual(session.statusText, "Done")
        XCTAssertEqual(session.options.map(\.highlight), [nil, nil, .done])
        XCTAssertFalse(session.doneOptionUnknown)
        XCTAssertTrue(session.options[2].accessibilityLabel.hasSuffix(". Done"))
    }

    func testDoneRecognisedFromTheActivityName() throws {
        let session = try builder().trainingDay(on: D.date("2030-10-18")).sessions[0]
        XCTAssertEqual(session.status, .done)
        XCTAssertEqual(session.options.map(\.highlight), [nil, .done])
        XCTAssertFalse(session.doneOptionUnknown)
    }

    func testDoneWithTheOptionUnknown() throws {
        let session = try builder(data: try Fixtures.exampleWithAnonymousFridayRun()).trainingDay(on: D.date("2030-10-18")).sessions[0]
        XCTAssertEqual(session.status, .done)
        XCTAssertTrue(session.doneOptionUnknown)
        XCTAssertTrue(session.options.allSatisfy { $0.highlight == nil })
    }

    func testMorningLightHighlightsItsOption() throws {
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateDay(&object, week: 2, day: 2) { $0["light"] = "amber" }
        }
        let model = try builder(data: data).trainingDay(on: D.asOf)
        XCTAssertEqual(model.sessions[0].options.map(\.highlight), [nil, .morningLight, nil])
        XCTAssertEqual(model.lightLine, "Morning check: Amber")
    }

    func testCarbLoadDay() throws {
        // Friday's easy run was swapped away: a rest day with a carb load.
        let model = try builder().trainingDay(on: D.date("2030-11-01"))
        XCTAssertEqual(model.emptyState?.kind, .restDay)
        XCTAssertEqual(model.carbLoadLine, "Carb load: 560 g carbs (8 g/kg)")
        let saturday = try builder().trainingDay(on: D.date("2030-11-02"))
        XCTAssertEqual(saturday.carbLoadLine, "Carb load: 700 g carbs (10 g/kg)")
    }

    func testTestAndRaceBadgesAndSessionFuel() throws {
        let test = try builder().trainingDay(on: D.date("2030-10-24")).sessions[0]
        XCTAssertEqual(test.badge, .test)
        XCTAssertEqual(test.badgeText, "Test")
        XCTAssertEqual(test.single?.targetLines, ["3 km"])
        let race = try builder().trainingDay(on: try Fixtures.exampleDate(ofSession: "2030-w44-sun-am")).sessions[0]
        XCTAssertEqual(race.badge, .race)
        XCTAssertEqual(race.fuelLine, "Fuel: 70 g carbs/h")
        XCTAssertEqual(race.title, "Race: Test Valley 30K")
    }

    func testNewSessionTypeIsShownNeutrally() throws {
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateSession(&object, week: 2, day: 2, session: 0) { $0["type"] = "hike" }
        }
        let session = try builder(data: data).trainingDay(on: D.asOf).sessions[0]
        XCTAssertEqual(session.title, "Easy 10 km")
        XCTAssertNil(session.badge)
    }

    // MARK: States (design D11)

    func testRestDayOutlinedWeekAndNoPlan() throws {
        // Sunday: its walk was moved to Friday by a plan command.
        let rest = try builder().trainingDay(on: D.date("2030-10-27"))
        XCTAssertEqual(rest.emptyState?.kind, .restDay)
        XCTAssertEqual(rest.emptyState?.title, "Rest day")

        let outlined = try builder().trainingDay(on: D.date("2030-11-06"))
        XCTAssertEqual(outlined.emptyState?.kind, .weekNotWritten)
        XCTAssertEqual(outlined.emptyState?.title, "Week not written yet")
        XCTAssertEqual(outlined.emptyState?.message, "Run target 45 km")

        let none = try builder().trainingDay(on: D.date("2031-03-04"))
        XCTAssertEqual(none.emptyState?.kind, .noPlanThisWeek)
    }

    func testMinimalFixtureHasNoActivePlan() throws {
        let today = try builder(data: try Fixtures.minimal())
        XCTAssertEqual(today.trainingDay(on: D.asOf).emptyState?.title, "No active plan")
        XCTAssertNil(today.raceChip(from: D.asOf))
        XCTAssertNil(today.weeklyNote(for: D.asOf))
        XCTAssertTrue(today.habits(on: D.asOf).isEmpty)
    }

    func testSourceStates() {
        let fetching = TodayTrainingBuilder(source: .waitingForFirstSync, language: .english).trainingDay(on: D.asOf)
        XCTAssertEqual(fetching.emptyState?.title, "Fetching your plan…")
        let missing = TodayTrainingBuilder(source: .notGenerated, language: .english).trainingDay(on: D.asOf)
        XCTAssertEqual(missing.emptyState?.title, "No plan data yet")
        XCTAssertEqual(missing.emptyState?.message, "Your vault hasn't published it.")
        let tooNew = TodayTrainingBuilder(source: .unreadable(.unsupportedMajor(found: 2)), language: .english).trainingDay(on: D.asOf)
        XCTAssertEqual(tooNew.emptyState?.title, "Update Jirka's Arc to read this plan")
        let broken = TodayTrainingBuilder(source: .unreadable(.invalid(reason: "x")), language: .czech).trainingDay(on: D.asOf)
        XCTAssertEqual(broken.emptyState?.title, "Nejnovější plán se nepodařilo přečíst")
    }

    func testNoticesTravelWithTheCard() throws {
        let decoded = try Fixtures.exampleProjection()
        let freshness = TrainingFreshness(asOf: D.date("2030-10-23"), isBehind: true)
        let source = TrainingSource.loaded(TrainingSnapshot(projection: decoded.projection, freshness: freshness))
        let model = TodayTrainingBuilder(source: source, language: .english).trainingDay(on: D.date("2030-10-24"))
        XCTAssertEqual(model.notices.map(\.text), ["Plan as of Wed 23 Oct"])
    }

    // MARK: Habits, race chip, weekly note

    func testHabitsOfTheDay() throws {
        let rows = try builder().habits(on: D.asOf)
        XCTAssertEqual(rows.map(\.id), ["holds"])
        let holds = rows[0]
        XCTAssertEqual(holds.icon, "🦶")
        XCTAssertEqual(holds.label, "Holds")
        XCTAssertEqual(holds.dose, "5 × 45 s, twice a day")
        XCTAssertEqual(holds.schedule, "2× a day")
        XCTAssertEqual(holds.adherence, "18 of 24 · 75 % · over 12 recorded days")
        XCTAssertEqual(holds.fraction, 0.75)
        XCTAssertEqual(holds.gateFraction, 0.8)
        XCTAssertEqual(holds.doneToday, "Today: 2 of 2")
        XCTAssertEqual(holds.tick, .displayOnly)

        let monday = try builder().habits(on: D.date("2030-10-21"))
        XCTAssertEqual(monday.map(\.id), ["holds", "gym"])
        XCTAssertEqual(monday[1].schedule, "Mon and Thu")
        XCTAssertEqual(monday[1].doneToday, "Today: 0 of 1")

        // A future day: the vault knows nothing yet, so no count.
        XCTAssertNil(try builder().habits(on: D.date("2030-10-24")).first?.doneToday)
    }

    // MARK: Habits card (polish-training-today D2)

    func testHabitsCardShowsTheLadderStepAndTheDay() throws {
        let card = try XCTUnwrap(try builder().habitsCard(on: D.asOf))
        XCTAssertEqual(card.stepText, "Step 2 of 6")
        // Both active habits; only "holds" is expected on Wednesday.
        XCTAssertEqual(card.rows.map(\.id), ["holds", "gym"])
        XCTAssertEqual(card.rows.map(\.isScheduledToday), [true, false])
        XCTAssertEqual(card.rows[0].doneToday, "Today: 2 of 2")
        XCTAssertNil(card.rows[0].notTodayText)
        XCTAssertEqual(card.rows[1].notTodayText, "Not on today's plan")
        XCTAssertNil(card.rows[1].doneToday)
        XCTAssertEqual(card.rows[1].adherence, "2 of 3 · 66 % · over 9 recorded days")
        XCTAssertEqual(card.rows[1].tick, .displayOnly)
        XCTAssertEqual(card.expectedCount, 1)
        XCTAssertEqual(card.doneCount, 1)
        XCTAssertEqual(card.progressText, "1 of 1 done today")

        let next = try XCTUnwrap(card.next)
        XCTAssertEqual(next.id, "stretch")
        XCTAssertEqual(next.title, "Next step: Stretch after easy runs")
        XCTAssertEqual(next.unlockText, "Unlocks when Gym twice a week holds 80 % over a 14-day window")
        XCTAssertEqual(next.earliestText, "Earliest start 28 Oct")
        XCTAssertEqual(next.accessibilityLabel, "Next step: Stretch after easy runs. Unlocks when Gym twice a week holds 80 % over a 14-day window. Earliest start 28 Oct")

        // Monday expects both.
        let monday = try XCTUnwrap(try builder().habitsCard(on: D.date("2030-10-21")))
        XCTAssertEqual(monday.rows.map(\.isScheduledToday), [true, true])
        XCTAssertEqual(monday.expectedCount, 2)
    }

    func testHabitsCardInCzech() throws {
        let card = try XCTUnwrap(try builder(.czech).habitsCard(on: D.asOf))
        XCTAssertEqual(card.stepText, "Krok 2 z 6")
        XCTAssertEqual(card.progressText, "Dnes hotovo 1 z 1")
        XCTAssertEqual(card.rows[1].notTodayText, "Dnes není v plánu")
        XCTAssertEqual(card.next?.title, "Další krok: Protažení po klidném běhu")
        XCTAssertEqual(card.next?.unlockText, "Odemkne se, až návyk Posilovna 2× týdně udrží 80 % v okně 14 dnů")
    }

    func testHabitsCardSaysWhenTheGateIsMet() throws {
        let data = try Fixtures.mutatedExample { object in
            var habits = try XCTUnwrap(object["habits"] as? [String: Any])
            var ladder = try XCTUnwrap(habits["ladder"] as? [[String: Any]])
            ladder[1]["gateMet"] = true
            habits["ladder"] = ladder
            object["habits"] = habits
        }
        let card = try XCTUnwrap(try builder(data: data).habitsCard(on: D.asOf))
        XCTAssertEqual(card.next?.unlockText, "Gate met: the next habit can start at your Sunday review")
    }

    func testHabitsCardShowsOnADayWithoutExpectedHabits() throws {
        // A day outside the written weeks: nothing expected, the ladder
        // still shows (it used to hide the card).
        let card = try XCTUnwrap(try builder().habitsCard(on: D.date("2031-03-02")))
        XCTAssertEqual(card.rows.map(\.id), ["holds", "gym"])
        XCTAssertTrue(card.rows.allSatisfy { !$0.isScheduledToday && $0.tick == .displayOnly })
        XCTAssertNil(card.progressText)
        XCTAssertEqual(card.expectedCount, 0)
    }

    func testNoLadderNoHabitsCard() throws {
        XCTAssertNil(try builder(data: try Fixtures.minimal()).habitsCard(on: D.asOf))
        XCTAssertNil(TodayTrainingBuilder(source: .waitingForFirstSync, language: .english).habitsCard(on: D.asOf))
    }

    // MARK: Race chip (polish-training-today D3)

    func testRaceChipPicksTheNextRaceOfAnyPriority() throws {
        let chip = try XCTUnwrap(try builder().raceChip(from: D.asOf))
        XCTAssertEqual(chip.raceID, "valley-30k-2030")
        XCTAssertEqual(chip.name, "Test Valley 30K")
        XCTAssertEqual(chip.countdown, "in 11 days")
        XCTAssertEqual(chip.priorityCode, "B")
        XCTAssertEqual(chip.priority, .b)
        XCTAssertEqual(chip.priorityText, "B race")
        XCTAssertFalse(chip.isHero)
        // The hero race stays visible as the second line.
        let main = try XCTUnwrap(chip.mainRace)
        XCTAssertEqual(main.raceID, "ridge-ultra-2031")
        XCTAssertEqual(main.countdown, "in about 241 days")
        XCTAssertEqual(main.text, "Main race: Ridge Ultra · in about 241 days")
        XCTAssertEqual(chip.accessibilityLabel, "Test Valley 30K, B race, in 11 days. Main race: Ridge Ultra · in about 241 days")
        XCTAssertEqual(try builder(.czech).raceChip(from: D.asOf)?.mainRace?.text, "Hlavní závod: Ridge Ultra · zhruba za 241 dní")

        // After the B race: the hero is next, and no second line.
        let hero = try XCTUnwrap(try builder().raceChip(from: D.date("2030-11-04")))
        XCTAssertEqual(hero.raceID, "ridge-ultra-2031")
        XCTAssertTrue(hero.isHero)
        XCTAssertEqual(hero.priorityText, "Hero race")
        XCTAssertEqual(hero.countdown, "in about 229 days")
        XCTAssertNil(hero.mainRace)
        XCTAssertNil(try builder().raceChip(from: D.date("2031-06-22")))
    }

    func testRaceChipIncludesCRaces() throws {
        // Before the C race in September, the chip shows it.
        let chip = try XCTUnwrap(try builder().raceChip(from: D.date("2030-09-20")))
        XCTAssertEqual(chip.raceID, "lakeside-10k-2030")
        XCTAssertEqual(chip.priorityText, "C race")
        XCTAssertEqual(chip.countdown, "tomorrow")
        XCTAssertEqual(chip.mainRace?.raceID, "ridge-ultra-2031")
    }

    func testRaceChipCountdownForAnExactARace() throws {
        let data = try Fixtures.mutatedExample { object in
            var season = try XCTUnwrap(object["season"] as? [String: Any])
            var races = try XCTUnwrap(season["races"] as? [[String: Any]])
            races[1]["priority"] = "A"
            season["races"] = races
            object["season"] = season
        }
        let chip = try XCTUnwrap(try builder(data: data).raceChip(from: D.date("2030-10-11")))
        XCTAssertEqual(chip.raceID, "valley-30k-2030")
        XCTAssertEqual(chip.countdown, "in 23 days")
        // The hero (not the A race) is the main race.
        XCTAssertEqual(chip.mainRace?.raceID, "ridge-ultra-2031")
        XCTAssertEqual(try builder(.czech, data: data).raceChip(from: D.date("2030-11-02"))?.countdown, "zítra")
    }

    func testNoSeasonNoChip() throws {
        let data = try Fixtures.mutatedExample { $0["season"] = NSNull() }
        XCTAssertNil(try builder(data: data).raceChip(from: D.asOf))
    }

    func testWeeklyNoteFromLastWeek() throws {
        let note = try XCTUnwrap(try builder().weeklyNote(for: D.asOf))
        XCTAssertEqual(note.week, D.week("2030-W42"))
        XCTAssertEqual(note.weekLabel, "W42 · 14–20 Oct")
        XCTAssertFalse(note.isCurrentWeek)
        XCTAssertEqual(note.text, "Last week settled well; this week adds one long run.")

        let raceWeek = try XCTUnwrap(try builder(.czech).weeklyNote(for: D.date("2030-10-30")))
        XCTAssertTrue(raceWeek.isCurrentWeek)
        XCTAssertEqual(raceWeek.text, "Závodní týden: objem dolů, sacharidy nahoru.")
        XCTAssertEqual(raceWeek.weekLabel, "T44 · 28. 10. – 3. 11.")

        XCTAssertNil(try builder().weeklyNote(for: D.date("2030-10-10")))
    }
}
