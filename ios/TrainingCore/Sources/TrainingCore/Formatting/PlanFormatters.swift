// PlanFormatters.swift
//
// The small pieces of text the screens are made of, in English and Czech
// (design D7, D10; tasks 3.2):
//
//   TargetFormatter    "12 km", "45 min", "<=144 bpm . Z2", "129-144 bpm",
//                      "Z2 . 129-145 bpm" -- heart rate in the athlete's
//                      zones (HRZoneMapper)
//   StepFormatter      one line per workout step: "Warm-up 10 min . Z1",
//                      "4 x 5 min . Z3, 2 min recovery", "Seated calf raise
//                      . 3 x 8-12 . 3-0-3 . 40 kg", "Hold 45 s . left"
//   FuelFormatter      "Carb load: 680 g carbs (8 g/kg)", "Fuel: 60 g carbs/h"
//   CountdownFormatter "today", "tomorrow", "in 23 days", "in about 23 days"
//   ScheduleFormatter  every habit schedule kind in words
//
// Units are the same in both languages; numbers follow the language
// (`NumberText`). Values come from the file as they are: nothing is
// summed or recomputed here.
//
// Depended on by: the builders. Tests: FormattingTests (both languages).

import Foundation

// MARK: - Targets

public struct TargetFormatter: Sendable {
    public let text: TrainingText
    public let zones: HRZoneMapper

    public init(text: TrainingText, zones: HRZoneMapper) {
        self.text = text
        self.zones = zones
    }

    /// "12 km", "45 min" or "12 km · 60 min"; `nil` without either.
    public func amount(_ targets: Targets) -> String? {
        var parts: [String] = []
        if let km = targets.km { parts.append(NumberText.distance(km, text.language)) }
        if let minutes = targets.min { parts.append(NumberText.duration(minutes: minutes)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The heart-rate target in the athlete's zones; `nil` without one.
    public func heartRate(_ targets: Targets) -> String? {
        let label = zones.label(zone: targets.zone, hrMin: targets.hrMin, hrMax: targets.hrMax)
        switch (targets.hrMin, targets.hrMax) {
        case let (low?, high?):
            return join("\(low)–\(high) bpm", label)
        case let (nil, high?):
            return join("≤\(high) bpm", label)
        case let (low?, nil):
            return join("≥\(low) bpm", label)
        case (nil, nil):
            guard let label else { return nil }
            if let zone = zones.zone(named: label) {
                return "\(label) · \(zone.low)–\(zone.high) bpm"
            }
            return label
        }
    }

    /// Up to two lines: the amount, then the heart rate.
    public func lines(_ targets: Targets) -> [String] {
        [amount(targets), heartRate(targets)].compactMap { $0 }
    }

    /// Everything on one line.
    public func summary(_ targets: Targets) -> String? {
        let parts = lines(targets)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The one target a list row shows: the amount, else the heart rate.
    public func key(_ targets: Targets) -> String? {
        amount(targets) ?? heartRate(targets)
    }

    private func join(_ bpm: String, _ label: String?) -> String {
        guard let label else { return bpm }
        return "\(bpm) · \(label)"
    }
}

// MARK: - Steps

public struct StepFormatter: Sendable {
    public let text: TrainingText

    public init(text: TrainingText) {
        self.text = text
    }

    public func line(_ step: Step) -> String {
        let language = text.language
        let amount = amountText(step, language)
        let intensity = intensityText(step)
        var parts: [String] = []

        switch step.kind?.known {
        case .warmup?:
            parts.append(labelled(text(.stepWarmUp), amount))
            parts.append(contentsOf: intensity)
        case .cooldown?:
            parts.append(labelled(text(.stepCoolDown), amount))
            parts.append(contentsOf: intensity)
        case .recovery?:
            parts.append(labelled(text(.recovery), amount))
            parts.append(contentsOf: intensity)
        case .rest?:
            parts.append(labelled(text(.stepRest), amount))
        case .interval?:
            let head: String
            if let times = step.times, let amount {
                head = "\(times) × \(amount)"
            } else {
                head = amount ?? ""
            }
            var line = ([head] + intensity).filter { !$0.isEmpty }.joined(separator: " · ")
            if let recovery = recoveryText(step, language) {
                let suffix = text.format(.stepRecoveryAfter, recovery)
                line = line.isEmpty ? suffix : "\(line), \(suffix)"
            }
            parts.append(line)
        case .exercise?:
            if let name = step.name { parts.append(name) }
            if let sets = setsAndReps(step) { parts.append(sets) }
            if let tempo = step.tempo { parts.append(tempo) }
            if let load = step.load { parts.append(load.text) }
            if let side = sideText(step.side) { parts.append(side) }
        case .hold?:
            var hold = text(.stepHold)
            if let seconds = step.sec {
                let duration = NumberText.seconds(seconds)
                hold += step.sets.map { " \($0) × \(duration)" } ?? " \(duration)"
            } else if let amount {
                hold += " \(amount)"
            }
            parts.append(hold)
            if let side = sideText(step.side) { parts.append(side) }
        case .active?, nil:
            if let name = step.name { parts.append(name) }
            if let amount { parts.append(amount) }
            parts.append(contentsOf: intensity)
            if let sets = setsAndReps(step) { parts.append(sets) }
        }

        if let pace = step.pace { parts.append("\(pace) /km") }
        if let note = step.note, !note.isEmpty { parts.append(note) }
        let line = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        return line.isEmpty ? (step.kind?.rawValue ?? "") : line
    }

    private func labelled(_ label: String, _ amount: String?) -> String {
        guard let amount else { return label }
        return "\(label) \(amount)"
    }

    private func amountText(_ step: Step, _ language: TrainingLanguage) -> String? {
        if let km = step.km { return NumberText.distance(km, language) }
        if let minutes = step.min { return NumberText.duration(minutes: minutes, language) }
        if let seconds = step.sec, step.kind?.known != .hold { return NumberText.seconds(seconds) }
        return nil
    }

    private func intensityText(_ step: Step) -> [String] {
        var parts: [String] = []
        if let zone = HRZoneMapper.normalizedLabel(step.zone) { parts.append(zone) }
        if let low = step.hrLo, let high = step.hrHi {
            parts.append("\(low)–\(high) bpm")
        } else if let high = step.hrMax ?? step.hrHi {
            parts.append("≤\(high) bpm")
        } else if let low = step.hrLo {
            parts.append("≥\(low) bpm")
        }
        return parts
    }

    private func recoveryText(_ step: Step, _ language: TrainingLanguage) -> String? {
        if let minutes = step.recoverMin { return NumberText.duration(minutes: minutes, language) }
        if let seconds = step.recoverSec { return NumberText.seconds(seconds) }
        return nil
    }

    private func setsAndReps(_ step: Step) -> String? {
        switch (step.sets, step.reps) {
        case let (sets?, reps?): return "\(sets) × \(reps.text)"
        case let (nil, reps?): return reps.text
        case let (sets?, nil): return "\(sets) ×"
        case (nil, nil): return nil
        }
    }

    private func sideText(_ side: OpenEnum<StepSide>?) -> String? {
        switch side?.known {
        case .each?: return text(.sideEach)
        case .left?: return text(.sideLeft)
        case .right?: return text(.sideRight)
        case .both?: return text(.sideBoth)
        case nil: return nil
        }
    }
}

// MARK: - Fuel

public struct FuelFormatter: Sendable {
    public let text: TrainingText

    public init(text: TrainingText) {
        self.text = text
    }

    /// "Carb load: 680 g carbs (8 g/kg)"; `nil` for another fuel kind --
    /// every day has a `fuel` since add-daily-checkin-and-pain-mode, and
    /// only a carb-load day (`DayFuel.isCarbLoad`) gets this line.
    public func dayLine(_ fuel: DayFuel?) -> String? {
        guard let fuel, fuel.isCarbLoad else { return nil }
        let perKg = fuel.carbsGPerKg.map { NumberText.decimal($0, text.language) }
        switch (fuel.carbsG, perKg) {
        case let (grams?, perKg?): return text.format(.fuelCarbLoad, String(grams), perKg)
        case let (grams?, nil): return text.format(.fuelCarbLoadGrams, String(grams))
        case let (nil, perKg?): return text.format(.fuelCarbLoadPerKg, perKg)
        case (nil, nil): return nil
        }
    }

    /// "Fuel: 60 g carbs/h"
    public func sessionLine(_ fuel: SessionFuel?) -> String? {
        guard let perHour = fuel?.carbsPerHour else { return nil }
        return text.format(.fuelPerHour, NumberText.decimal(perHour, text.language))
    }
}

// MARK: - Countdown

public struct CountdownFormatter: Sendable {
    public let text: TrainingText

    public init(text: TrainingText) {
        self.text = text
    }

    /// `days` from today to the date; "about" when the date is approximate.
    public func phrase(days: Int, approximate: Bool) -> String {
        switch (days, approximate) {
        case (...0, false): return text(.countdownToday)
        case (...0, true): return text(.countdownAboutToday)
        case (1, false): return text(.countdownTomorrow)
        case (1, true): return text(.countdownAboutTomorrow)
        case (_, false): return text.format(.countdownInDays, days)
        case (_, true): return text.format(.countdownInAboutDays, days)
        }
    }
}

// MARK: - Habit schedules

public struct ScheduleFormatter: Sendable {
    public let text: TrainingText

    public init(text: TrainingText) {
        self.text = text
    }

    public func line(_ schedule: HabitSchedule?) -> String? {
        guard let schedule else { return nil }
        let dates = DateText(text.language)
        switch schedule.kind.known {
        case .daily?:
            let perDay = schedule.perDay ?? 1
            return perDay <= 1 ? text(.scheduleEveryDay) : text.format(.scheduleTimesPerDay, perDay)
        case .weekly?:
            let names = schedule.days.compactMap(Self.isoWeekday).map(dates.weekdayShort)
            return names.isEmpty ? nil : list(names)
        case .weeklyCount?:
            let times = schedule.times ?? 1
            return times <= 1 ? text(.scheduleOnceAWeek) : text.format(.scheduleTimesPerWeek, times)
        case .everyNWeeks?:
            let every = text.format(.scheduleEveryNWeeks, max(schedule.n ?? 1, 1))
            guard let day = schedule.day.flatMap(Self.isoWeekday) else { return every }
            return "\(every) · \(dates.weekdayShort(day))"
        case .withSessions?:
            var names = schedule.types.map { raw -> String in
                text.typeName(OpenEnum<SessionType>(rawValue: raw))?.lowercased(with: text.language.locale) ?? raw
            }
            if names.isEmpty, let sport = schedule.sport {
                names = [text.sportName(OpenEnum<Sport>(rawValue: sport))?.lowercased(with: text.language.locale) ?? sport]
            }
            return text.format(.scheduleWithSessions, list(names))
        case nil:
            return nil
        }
    }

    /// "MO" ... "SU" (also "Mon", "monday") -> 1 ... 7.
    static func isoWeekday(_ code: String) -> Int? {
        let prefix = code.prefix(2).uppercased()
        return ["MO", "TU", "WE", "TH", "FR", "SA", "SU"].firstIndex(of: prefix).map { $0 + 1 }
    }

    private func list(_ items: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = text.language.locale
        return formatter.string(from: items) ?? items.joined(separator: ", ")
    }
}
