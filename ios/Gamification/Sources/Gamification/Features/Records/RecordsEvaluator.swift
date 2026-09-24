// RecordsEvaluator.swift
//
// add-journeys-and-records design D6: the pure step behind
// `PersonalRecordsFeature`. For every record it
//   1. computes the per-day values from the snapshot (closed-day records:
//      only days before today);
//   2. advances the record's `DailyLedger`, so each qualifying day adds to
//      `qualifyingDays` exactly once (the 7-day warm-up);
//   3. walks the candidate days oldest first and keeps the best value.
//
// An improvement is ANNOUNCED (a "New PR!" moment + 20 XP) only when all of:
// it isn't the first run (silent baseline), there was a previous value,
// the record has >= 7 qualifying days, and the day is still open (today,
// yesterday, the day before -- an old day that only now got data updates
// the record silently). A second improvement on the SAME day updates the
// value silently and keeps `previous` (design D6: "later increases the
// same day update the value silently"), so the grant key
// `records.<id>.<day>` is paid at most once per record per day.
//
// Sequence metrics:
//   - water-goal streak: consecutive days with water >= goal, carried over
//     from the newest sealed day (`WaterStreakCarry`) because the snapshot
//     is only 42 days; a day without water data or goal breaks it.
//   - longest fast: hours between consecutive entries across days,
//     attributed to the day of the entry that ENDED the fast; gaps over
//     48 h are unlogged days, not a fast.
//
// Accepted: a record never goes down when an old entry is deleted.
//
// Depends on: PersonalRecordCatalog, RecordsState, DailyLedger, FoodLogCore.
// Depended on by: PersonalRecordsFeature, PersonalRecordsTests.

import Foundation
import FoodLogCore

public enum RecordsEvaluator {
    public struct NewRecord: Sendable, Equatable {
        public let id: PersonalRecordId
        public let day: String
        public let value: Double
        public let previousValue: Double
    }

    public struct Result: Sendable, Equatable {
        public let state: RecordsState
        /// PRs announced in this run, catalog order then day order.
        public let announced: [NewRecord]
        public let wasFirstRun: Bool
    }

    // MARK: - Sequence metrics

    /// The water-goal streak length on every processed window day (days at
    /// or before `carry.day` are skipped: already counted). Days without
    /// water data or goal have length 0.
    static func waterStreakRuns(_ snapshot: SignalsSnapshot, carry: WaterStreakCarry?) -> [String: Int] {
        var running = 0
        var runs: [String: Int] = [:]
        for key in snapshot.windowDays {
            if let carryDay = carry?.day {
                if key < carryDay { continue }
                if key == carryDay {
                    running = carry?.length ?? 0
                    runs[key] = running
                    continue
                }
            }
            if let day = snapshot.days[key], PersonalRecordCatalog.metWaterGoal(day) == true {
                running += 1
            } else {
                running = 0
            }
            runs[key] = running
        }
        return runs
    }

    /// Longest gap (hours) between consecutive entries ending on each day;
    /// gaps over 48 h are ignored.
    public static func longestFastHours(_ snapshot: SignalsSnapshot) -> [String: Double] {
        var stamps: [(day: String, time: Date)] = []
        for day in snapshot.orderedDays {
            for entry in day.entries {
                stamps.append((day: day.day, time: entry.timestamp))
            }
        }
        stamps.sort { $0.time < $1.time }
        var result: [String: Double] = [:]
        guard stamps.count > 1 else { return result }
        for index in 1..<stamps.count {
            let hours = stamps[index].time.timeIntervalSince(stamps[index - 1].time) / 3600
            guard hours > 0, hours <= PersonalRecordCatalog.maxFastGapHours else { continue }
            let day = stamps[index].day
            result[day] = max(result[day] ?? 0, hours)
        }
        return result
    }

    /// Every qualifying day's value for `id` in the snapshot window.
    public static func dayValues(
        _ id: PersonalRecordId,
        snapshot: SignalsSnapshot,
        streakCarry: WaterStreakCarry? = nil
    ) -> [String: Double] {
        func perDay(_ metric: (DaySignals) -> Double?) -> [String: Double] {
            var values: [String: Double] = [:]
            for day in snapshot.orderedDays {
                if let value = metric(day) {
                    values[day.day] = value
                }
            }
            return values
        }
        switch id {
        case .proteinDay: return perDay(PersonalRecordCatalog.proteinGrams)
        case .fruitVegDay: return perDay(PersonalRecordCatalog.fruitVegEntries)
        case .distinctFoodsDay: return perDay(PersonalRecordCatalog.distinctFoods)
        case .waterDay: return perDay(PersonalRecordCatalog.waterML)
        case .activeKcalDay: return perDay(PersonalRecordCatalog.activeKcal)
        case .lowSugarOnTarget: return perDay(PersonalRecordCatalog.onTargetSugarGrams)
        case .longestFast: return longestFastHours(snapshot)
        case .waterStreak:
            let runs = waterStreakRuns(snapshot, carry: streakCarry)
            var values: [String: Double] = [:]
            for (key, length) in runs {
                // Qualifying = the day has water data and a goal.
                if let day = snapshot.days[key], PersonalRecordCatalog.metWaterGoal(day) != nil {
                    values[key] = Double(length)
                }
            }
            return values
        }
    }

    // MARK: - Evaluation

    public static func evaluate(state: RecordsState, snapshot: SignalsSnapshot) -> Result {
        let wasFirstRun = state.isFirstRun
        let openDays = Set(snapshot.windowDays.suffix(DailyLedger<Double>.openWindowLength))
        var next = state
        var records = state.records ?? [:]
        var history = state.history ?? []
        var announced: [NewRecord] = []

        for definition in PersonalRecordCatalog.all {
            var record = records[definition.id.rawValue] ?? PersonalRecordState()
            var values = dayValues(definition.id, snapshot: snapshot, streakCarry: state.waterStreakCarry)
            if definition.timing == .closedDay {
                values = values.filter { $0.key < snapshot.today }
            }

            var ledger = record.ledger ?? DailyLedger<Double>()
            let sealed = ledger.advance(windowDays: snapshot.windowDays) { values[$0] }
            record.ledger = ledger
            record.sealedQualifyingDays = (record.sealedQualifyingDays ?? 0) + sealed.count
            let qualifyingDays = record.qualifyingDays

            // Days that left the window before they could be sealed keep
            // their last value (silent); then every window day, oldest first.
            var candidates: [(day: String, value: Double)] = sealed
                .filter { values[$0.day] == nil }
                .map { (day: $0.day, value: $0.value) }
            for key in snapshot.windowDays {
                if let value = values[key] {
                    candidates.append((day: key, value: value))
                }
            }

            for candidate in candidates {
                guard definition.isImprovement(candidate.value, over: record.current?.value) else { continue }
                if record.current?.day == candidate.day {
                    // Same day again: silent update, `previous` unchanged.
                    record.current = RecordMark(value: candidate.value, day: candidate.day)
                    if let index = history.lastIndex(where: { $0.recordId == definition.id.rawValue && $0.day == candidate.day }) {
                        history[index].value = candidate.value
                    }
                    continue
                }
                let previous = record.current
                record.previous = previous
                record.current = RecordMark(value: candidate.value, day: candidate.day)
                guard !wasFirstRun,
                      let previousValue = previous?.value,
                      qualifyingDays >= PersonalRecordCatalog.warmUpDays,
                      openDays.contains(candidate.day)
                else { continue }
                record.prCount = (record.prCount ?? 0) + 1
                announced.append(NewRecord(id: definition.id, day: candidate.day, value: candidate.value, previousValue: previousValue))
                history.append(PersonalRecordEvent(
                    recordId: definition.id.rawValue,
                    day: candidate.day,
                    value: candidate.value,
                    previousValue: previousValue
                ))
            }

            if definition.id == .waterStreak, let sealedThrough = ledger.sealedThrough,
               sealedThrough != state.waterStreakCarry?.day {
                let runs = waterStreakRuns(snapshot, carry: state.waterStreakCarry)
                next.waterStreakCarry = WaterStreakCarry(day: sealedThrough, length: runs[sealedThrough] ?? 0)
            }
            records[definition.id.rawValue] = record
        }

        if history.count > PersonalRecordCatalog.historyLimit {
            history = Array(history.suffix(PersonalRecordCatalog.historyLimit))
        }
        next.records = records
        next.history = history
        if next.startedOn == nil {
            next.startedOn = snapshot.today.isEmpty ? nil : snapshot.today
        }
        return Result(state: next, announced: announced, wasFirstRun: wasFirstRun)
    }

    // MARK: - Badges

    /// Design D6: first PR, 10 PRs, 50 PRs, and a PR in every record that
    /// has a value (at least `fullHouseMinRecords` of them).
    public static func earnedBadgeIds(_ state: RecordsState) -> [String] {
        var ids: [String] = []
        let total = state.totalPRs
        if total >= 1 { ids.append("record.first-pr") }
        if total >= 10 { ids.append("record.pr-10") }
        if total >= 50 { ids.append("record.pr-50") }
        let withValue = PersonalRecordId.allCases.filter { state.record($0).current?.value != nil }
        if withValue.count >= PersonalRecordCatalog.fullHouseMinRecords,
           withValue.allSatisfy({ (state.record($0).prCount ?? 0) > 0 }) {
            ids.append("record.full-house")
        }
        return ids
    }
}
