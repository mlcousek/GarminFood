// DailyLedger.swift
//
// add-journeys-and-records design D1: the "count every day exactly once"
// helper behind lifetime journey totals (and the records' qualifying-day
// counts). The signals snapshot only covers 42 days and the usage history
// is capped, so a lifetime total can't be recomputed from scratch on every
// run -- instead each day is FOLDED into the owner's running aggregate
// exactly once, when it is "sealed".
//
// A day is sealed once it is older than the open window (the last 3 days of
// the snapshot: today, yesterday, the day before), because until then a late
// log can still change it. While open, its value is recomputed from the
// snapshot on every run (never added), so ten refreshes a day add nothing
// twice and a late log for yesterday simply changes yesterday's open value.
//
// First run (`sealedThrough == nil`): every window day older than the open
// window is sealed at once -- the 42-day back-fill.
//
// Accepted trade-off (design D1): an edit to a day that is already sealed
// (4+ days old) no longer changes the aggregate.
//
// Pure value type over `yyyy-MM-dd` keys (which sort chronologically as
// strings); no calendar, no I/O. Persisted inside the owning feature's store,
// every field Optional so the format can grow.
//
// Depends on: nothing. Depended on by: JourneysEvaluator, RecordsEvaluator.

import Foundation

public struct DailyLedger<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    /// The newest day already folded into the aggregate (`yyyy-MM-dd`).
    public var sealedThrough: String?
    /// The last computed value of each still-open day. Kept so a day that
    /// falls out of the snapshot window before it could be sealed (the app
    /// wasn't opened for weeks) is still folded with its last known value.
    public var openDays: [String: Value]?

    /// Days in the open window (today + the two days before).
    public static var openWindowLength: Int { 3 }

    public init(sealedThrough: String? = nil, openDays: [String: Value]? = nil) {
        self.sealedThrough = sealedThrough
        self.openDays = openDays
    }

    public struct SealedDay: Sendable, Equatable {
        public let day: String
        public let value: Value
    }

    /// `true` before the first `advance` (nothing ever sealed or opened).
    public var isFresh: Bool { sealedThrough == nil && (openDays ?? [:]).isEmpty }

    /// One run: recomputes the open days from `value` and returns every day
    /// that became sealed in this call (oldest first, only days that had a
    /// value), each exactly once over the ledger's lifetime.
    ///
    /// - Parameters:
    ///   - windowDays: the snapshot's consecutive day keys, oldest first,
    ///     ending with today.
    ///   - value: the day's value from the snapshot, `nil` when the day has
    ///     no usable data (it then contributes nothing).
    public mutating func advance(
        windowDays: [String],
        openCount: Int = 3,
        value: (String) -> Value?
    ) -> [SealedDay] {
        let open = Array(windowDays.suffix(max(0, openCount)))
        let oldestOpen = open.first
        let windowSet = Set(windowDays)
        let previousOpen = openDays ?? [:]

        func isAfterSealed(_ day: String) -> Bool {
            guard let sealedThrough else { return true }
            return day > sealedThrough
        }
        func isBeforeOpen(_ day: String) -> Bool {
            guard let oldestOpen else { return true }
            return day < oldestOpen
        }

        var candidates = Set<String>()
        for day in windowDays where isBeforeOpen(day) && isAfterSealed(day) {
            candidates.insert(day)
        }
        for day in previousOpen.keys where isBeforeOpen(day) && isAfterSealed(day) {
            candidates.insert(day)
        }

        var sealed: [SealedDay] = []
        for day in candidates.sorted() {
            // In the window: the snapshot is authoritative (a late log shows
            // up there). Out of the window: the last value we saw while open.
            let dayValue = windowSet.contains(day) ? value(day) : previousOpen[day]
            if let dayValue {
                sealed.append(SealedDay(day: day, value: dayValue))
            }
        }

        // Advance the seal mark to the newest day before the open window.
        var newMark = sealedThrough
        if let last = candidates.sorted().last, newMark.map({ last > $0 }) ?? true {
            newMark = last
        }
        if let lastClosedWindowDay = windowDays.last(where: { isBeforeOpen($0) }),
           newMark.map({ lastClosedWindowDay > $0 }) ?? true {
            newMark = lastClosedWindowDay
        }
        sealedThrough = newMark

        var nextOpen: [String: Value] = [:]
        for day in open where isAfterSealed(day) {
            if let dayValue = value(day) {
                nextOpen[day] = dayValue
            }
        }
        openDays = nextOpen
        return sealed
    }

    /// The open days' current values (not yet part of any aggregate).
    public var openValues: [Value] {
        (openDays ?? [:]).keys.sorted().compactMap { openDays?[$0] }
    }
}
