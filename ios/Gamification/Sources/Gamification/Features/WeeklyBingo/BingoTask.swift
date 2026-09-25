// BingoTask.swift
//
// add-weekly-bingo design D2: the shape of one bingo square's task -- a
// persisted `id` (cards store ids only, never display text), a difficulty
// used by the card composition (3 easy / 3 medium / 2 hard), a `family`
// (no two tasks of the same family on one card), and the rule written in
// the SHARED predicate vocabulary (`DayPredicate` for "on any single day of
// the week", `WeekPredicate` for "across the week so far"), so a bingo
// square and a boss rule that say the same thing are judged by the same
// `SignalEvaluator` code.
//
// `requirement` is derived from the rule, never hand-written, so a water
// square can never be offered to someone with no water data by mistake.
//
// Depends on: DayPredicate, WeekPredicate, DataRequirement.
// Depended on by: BingoTaskCatalog, BingoCardGenerator, BingoEvaluator,
// WeeklyBingoFeature, the app's BingoCardView.

import Foundation

public enum BingoDifficulty: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case easy, medium, hard
}

public enum BingoTaskScope: Sendable, Equatable {
    /// Completes when the predicate holds on any single logged day of the
    /// card's week (up to today).
    case day(DayPredicate)
    /// Completes when the predicate holds over the card's week so far.
    case week(WeekPredicate)

    public var requirement: DataRequirement {
        switch self {
        case .day(let predicate): return predicate.requirement
        case .week(let predicate): return predicate.requirement
        }
    }
}

public struct BingoTask: Sendable, Equatable, Identifiable {
    /// Persisted in cards; never reused for a different rule.
    public let id: String
    /// Localized display title.
    public let title: String
    /// Localized one-line rule shown in the square sheet.
    public let detail: String
    public let difficulty: BingoDifficulty
    /// No two tasks of the same family on one card ("fruit", "water", ...).
    public let family: String
    public let scope: BingoTaskScope
    /// An SF Symbol for the square.
    public let symbol: String

    public init(
        id: String,
        title: String,
        detail: String,
        difficulty: BingoDifficulty,
        family: String,
        scope: BingoTaskScope,
        symbol: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.difficulty = difficulty
        self.family = family
        self.scope = scope
        self.symbol = symbol
    }

    public var requirement: DataRequirement { scope.requirement }
}
