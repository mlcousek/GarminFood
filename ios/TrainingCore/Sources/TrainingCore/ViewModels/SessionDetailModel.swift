// SessionDetailModel.swift
//
// One session explained (spec "The session detail explains the session";
// design D10): date, slot, sport, status, type badge; for each option (or
// the session itself) its targets in the athlete's zones, the steps of its
// workout ("Steps not published" when there are none) and its watch state
// once published; why -- the session's, then its workout's, then rule
// notes; where it came from once published; the done option or "Option not
// identified", the matched activity and how it was recognised; fuel; a
// test's results labelled by the test's measures next to the previous
// value from the test history; the race it is.
//
// It opens on the tapped option, else the done one, else the one the
// morning light points at, else G.
//
// Depended on by: the app's SessionDetailView. Tests: PlanBuilderTests.

import Foundation

public struct DetailOptionModel: Equatable, Sendable, Identifiable {
    public let id: String
    /// "G", "A", "R"; `nil` for a session without options.
    public let code: String?
    public let knownCode: OptionCode?
    public let meaning: String?
    public let label: String
    public let targetLines: [String]
    public let steps: [String]
    /// "Steps not published" when the workout has no steps.
    public let stepsPlaceholder: String?
    public let watchLine: String?
}

public struct DoneDetailModel: Equatable, Sendable {
    /// "Option R · Alternative" / "Option not identified"; `nil` for a
    /// session without options.
    public let optionText: String?
    /// "Ride · 05:10 · 21.3 km · 46 min".
    public let activityLine: String?
    /// "Inferred from the sport", ...
    public let recognisedText: String?
}

public enum TestTrend: String, Equatable, Sendable {
    case improved, worse, unchanged
}

public struct TestResultRowModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// "24 reps".
    public let valueText: String
    /// "Previous 22 reps".
    public let previousText: String?
    public let trend: TestTrend?
    public let trendText: String?
}

public struct TestDetailModel: Equatable, Sendable {
    public let rows: [TestResultRowModel]
    /// "No result yet" before the test.
    public let placeholder: String?
    public let note: String?
}

public struct SessionDetailModel: Equatable, Sendable {
    public let id: String
    public let title: String
    /// "Wed 23 Oct · Morning".
    public let dateLine: String
    public let sportName: String?
    public let sportSymbol: String
    public let status: SessionStatusKind
    public let statusText: String?
    public let badgeText: String?
    /// G, A, R; empty for a session without options (then `single`).
    public let options: [DetailOptionModel]
    public let single: DetailOptionModel?
    /// Index into `options` the picker opens on.
    public let initialOptionIndex: Int
    public let whyLines: [String]
    public let originText: String?
    public let done: DoneDetailModel?
    public let fuelLines: [String]
    public let test: TestDetailModel?
    public let raceLine: String?
    /// add-training-checkins: RPE and note, when rating is allowed.
    public var rating: SessionRatingModel? = nil
}

public extension PlanBuilder {
    /// The detail of session `id`; `nil` when the plan doesn't have it.
    /// `option` is the tapped card's code, if any.
    func sessionDetail(id: String, option: String? = nil) -> SessionDetailModel? {
        guard let snapshot = source.snapshot, let plan = snapshot.plan else { return nil }
        for week in plan.weeks {
            for day in week.days {
                if let session = day.sessions.first(where: { $0.id == id }) {
                    return sessionDetail(session, day: day, snapshot: snapshot, tapped: option)
                }
            }
        }
        return nil
    }

    internal func sessionDetail(_ session: Session, day: Day, snapshot: TrainingSnapshot, tapped: String?) -> SessionDetailModel {
        let text = format.text
        let language = format.language
        let status = SessionStatusKind(session.status)
        let title = format.title(of: session, in: snapshot)

        let dateLine = [format.dates.short(day.date), text.slotName(session.slot)].compactMap { $0 }.joined(separator: " · ")
        let badgeText: String?
        switch session.type?.known {
        case .test?: badgeText = text(.badgeTest)
        case .race?: badgeText = text(.race)
        default: badgeText = nil
        }

        let options = session.options.map { option in
            detailOption(
                id: option.code.rawValue,
                code: option.code,
                label: option.label.resolvedText(language) ?? option.code.rawValue,
                targets: option.targets,
                workout: snapshot.workout(option.workout),
                watch: option.watch
            )
        }
        let single: DetailOptionModel? = session.options.isEmpty
            ? detailOption(id: session.id, code: nil, label: title, targets: session.targets, workout: snapshot.workout(session.workout), watch: nil)
            : nil

        // Pre-selection: tapped, else done, else the light's, else G.
        let codes = session.options.map { $0.code.rawValue }
        let doneCode = status == .done ? session.done?.option?.rawValue : nil
        let lightCode = day.light?.known?.option.rawValue
        let preferred = [tapped, doneCode, lightCode, OptionCode.g.rawValue].compactMap { $0 }
        let initialIndex = preferred.lazy.compactMap { codes.firstIndex(of: $0) }.first ?? 0

        // Why: the session's, then its workout's, then rule notes.
        var why: [String] = []
        if let own = session.why.resolvedText(language) { why.append(own) }
        if let workoutWhy = snapshot.workout(session.workout)?.why.resolvedText(language), !why.contains(workoutWhy) {
            why.append(workoutWhy)
        }
        why.append(contentsOf: session.ruleNotes.compactMap(format.freeText))

        var fuel: [String] = []
        if let line = format.fuel.sessionLine(session.fuel) { fuel.append(line) }
        if let line = format.fuel.dayLine(day.fuel) { fuel.append(line) }

        let raceLine = snapshot.race(id: session.raceId).map { race in
            text.format(.raceDayLine, race.name.resolvedText(language) ?? race.id) + " · " + format.dates.short(race.date)
        }

        var model = SessionDetailModel(
            id: session.id,
            title: title,
            dateLine: dateLine,
            sportName: text.sportName(session.sport),
            sportSymbol: SportSymbol.name(session.sport),
            status: status,
            statusText: text.statusName(session.status),
            badgeText: badgeText,
            options: options,
            single: single,
            initialOptionIndex: options.isEmpty ? 0 : min(initialIndex, options.count - 1),
            whyLines: why,
            originText: originText(session.origin),
            done: doneDetail(session),
            fuelLines: fuel,
            test: testDetail(session, day: day, snapshot: snapshot),
            raceLine: raceLine
        )
        model.rating = ratingModel(session, day: day, snapshot: snapshot)
        return model
    }

    private func detailOption(id: String, code: OpenEnum<OptionCode>?, label: String, targets: Targets, workout: Workout?, watch: OptionWatch?) -> DetailOptionModel {
        let steps = (workout?.steps ?? []).map(format.steps.line)
        let today = TodayTrainingBuilder(source: source, language: format.language)
        return DetailOptionModel(
            id: id,
            code: code?.rawValue,
            knownCode: code?.known,
            meaning: code.flatMap { format.text.optionMeaning($0) },
            label: label,
            targetLines: format.targets.lines(targets),
            steps: steps,
            stepsPlaceholder: steps.isEmpty ? format.text(.stepsNotPublished) : nil,
            watchLine: today.watchLine(watch)
        )
    }

    private func doneDetail(_ session: Session) -> DoneDetailModel? {
        guard let done = session.done else { return nil }
        let text = format.text
        var optionText: String?
        if !session.options.isEmpty {
            if let code = done.option {
                let meaning = text.optionMeaning(code) ?? code.rawValue
                optionText = text.format(.doneOptionMeaning, code.rawValue, meaning)
            } else {
                optionText = text(.optionNotIdentified)
            }
        }
        var activityLine: String?
        if let activity = done.activity {
            var parts: [String] = []
            if let name = text.sportName(activity.group) ?? activity.sport { parts.append(name) }
            if let start = activity.start { parts.append(format.dates.clock(start)) }
            if let km = activity.km { parts.append(NumberText.distance(km, format.language)) }
            if let minutes = activity.min { parts.append(NumberText.duration(minutes: minutes)) }
            activityLine = parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        var recognised: String?
        if done.source?.known == .activityName {
            recognised = text(.recognisedName)
        } else if done.source?.known == .sportInferred {
            recognised = text(.recognisedSport)
        } else {
            switch done.matchedBy?.known {
            case .testResult?: recognised = text(.recognisedTest)
            case .dateSportGroup?: recognised = text(.recognisedDateSport)
            case nil: recognised = nil
            }
        }
        return DoneDetailModel(optionText: optionText, activityLine: activityLine, recognisedText: recognised)
    }

    /// Reserved (`null` in v1): "Moved from Mon 19 Oct", "Changed by a rule".
    private func originText(_ origin: JSONValue?) -> String? {
        guard let origin else { return nil }
        let text = format.text
        if let moved = origin["movedFrom"]?.stringValue ?? origin["from"]?.stringValue, let date = LocalDate(moved) {
            return text.format(.originMovedFrom, format.dates.short(date))
        }
        if origin["rule"] != nil || origin["kind"]?.stringValue == "rule" {
            return text(.originRule)
        }
        if let plain = origin.stringValue, !plain.isEmpty {
            return plain
        }
        return text(.originChanged)
    }

    private func testDetail(_ session: Session, day: Day, snapshot: TrainingSnapshot) -> TestDetailModel? {
        guard session.type?.known == .test || session.test != nil else { return nil }
        let text = format.text
        let workoutID = session.test?.workout ?? session.workout
        let history = snapshot.testHistory(workout: workoutID)
        let measures = snapshot.workout(workoutID)?.measures.nilIfEmpty ?? history?.measures ?? []
        guard let result = session.test?.result, !result.isEmpty else {
            return TestDetailModel(rows: [], placeholder: text(.testNoResult), note: session.test?.note)
        }
        let earlier = (history?.history ?? []).filter { entry in
            entry.date < day.date && entry.sessionId != session.id
        }
        let measured = measures.map(\.key)
        let keys = measured + result.keys.sorted().filter { !measured.contains($0) }
        let rows = keys.compactMap { key -> TestResultRowModel? in
            guard let value = result[key] else { return nil }
            let measure = measures.first { $0.key == key }
            let unit = measure?.unit
            let previous = earlier.last { $0.values[key] != nil }?.values[key]
            var trend: TestTrend?
            if let previous {
                if value == previous {
                    trend = .unchanged
                } else {
                    let higher = value > previous
                    switch measure?.better?.known {
                    case .higher?: trend = higher ? .improved : .worse
                    case .lower?: trend = higher ? .worse : .improved
                    case nil: trend = nil
                    }
                }
            }
            let trendText: String?
            switch trend {
            case .improved?: trendText = text(.testImproved)
            case .worse?: trendText = text(.testWorse)
            case .unchanged?: trendText = text(.testUnchanged)
            case nil: trendText = nil
            }
            return TestResultRowModel(
                id: key,
                label: measure?.label.resolvedText(format.language) ?? key,
                valueText: valueText(value, unit: unit),
                previousText: previous.map { text.format(.testPrevious, valueText($0, unit: unit)) },
                trend: trend,
                trendText: trendText
            )
        }
        return TestDetailModel(rows: rows, placeholder: nil, note: session.test?.note)
    }

    private func valueText(_ value: Double, unit: String?) -> String {
        let number = NumberText.decimal(value, format.language, maxFractionDigits: 2)
        guard let unit, !unit.isEmpty else { return number }
        return "\(number) \(unit)"
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}
