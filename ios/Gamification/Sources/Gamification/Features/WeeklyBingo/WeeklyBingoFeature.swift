// WeeklyBingoFeature.swift
//
// add-weekly-bingo: the "bingo" gamification feature -- a 3x3 card per
// ISO week (free centre + 8 tasks from BingoTaskCatalog), squares that tick
// themselves from the week's day signals, 25 XP per completed line and
// 150 XP + a streak-freeze grant for a full card. Replaces the empty stub
// registered by add-gamification-signals (design D7);
// `GamificationFeatureRegistry` still creates it with `init(directory:)`.
//
// Each run (FeatureHost, after every refresh/confirm; local reads only):
//   1. week = ISO week of the snapshot's logged-date "today";
//   2. loads this week's card, or generates it ONCE (BingoCardGenerator,
//      eligibility from the last 14 days, last week's card excluded) and
//      stores it -- it never changes again that week;
//   3. merges fresh completions into the stored, sticky ones
//      (BingoEvaluator; only this week's days count);
//   4. grants `bingo.line.<week>.<line>` per complete line and
//      `bingo.full.<week>` + `bingo.freeze.<week>` for a full card -- every
//      run, because `RewardLedger` makes them idempotent. The freeze is a
//      plain `.streakFreeze` grant: the ledger records it
//      (`RewardLedger.freezeGrants()`), and the streak-freeze change turns
//      recorded grants into a balance -- nothing freeze-specific lives here;
//   5. emits a moment and bumps the lifetime counters only the first time
//      a line / the full card is recorded on the card, then requests the
//      badges (D6) the counters and stored cards justify.
//
// The previous week's card is simply no longer evaluated from Monday on:
// it is frozen as-is and stays in the 12-week history.
//
// Depends on: GamificationFeature, BingoTaskCatalog, BingoCardGenerator,
// BingoEvaluator, BingoStore, XPAward+Features, FoodLogCore.
// Depended on by: GamificationFeatureRegistry, the app's BingoSlotView /
// BingoCardView.

import Foundation
import FoodLogCore

/// One square as the UI shows it.
public struct BingoSquareStatus: Sendable, Equatable, Identifiable {
    public let index: Int
    /// `nil` = the FREE square (or an id no longer in the catalog).
    public let task: BingoTask?
    /// `yyyy-MM-dd` the square completed, if it has.
    public let completedDay: String?

    public init(index: Int, task: BingoTask?, completedDay: String?) {
        self.index = index
        self.task = task
        self.completedDay = completedDay
    }

    public var id: Int { index }
    public var isFree: Bool { task == nil }
    public var isDone: Bool { isFree || completedDay != nil }
    /// 1-based, top to bottom.
    public var row: Int { index / 3 + 1 }
    /// 1-based, left to right.
    public var column: Int { index % 3 + 1 }
}

/// One week's card as the UI shows it.
public struct BingoCardStatus: Sendable, Equatable, Identifiable {
    public let week: WeekKey
    public let squares: [BingoSquareStatus]
    public let lines: [BingoLine]
    public let isFull: Bool

    public init(week: WeekKey, squares: [BingoSquareStatus], lines: [BingoLine], isFull: Bool) {
        self.week = week
        self.squares = squares
        self.lines = lines
        self.isFull = isFull
    }

    public var id: String { week.rawValue }
    public var doneCount: Int { squares.filter(\.isDone).count }
}

public actor WeeklyBingoFeature: GamificationFeature {
    public static let id = "bingo"
    public static let symbol = "square.grid.3x3.fill"

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { BingoTaskCatalog.badges }

    let directory: URL
    let store: BingoStore

    public init(directory: URL) {
        self.directory = directory
        self.store = BingoStore(directory: directory)
    }

    // MARK: - GamificationFeature

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        let calendar = context.calendar
        let today = context.snapshot.today.isEmpty
            ? NutritionDate.string(from: context.now, calendar: calendar)
            : context.snapshot.today
        guard let week = WeekKey(dayKey: today, calendar: calendar) else { return .empty }

        var record = await cardForWeek(week, snapshot: context.snapshot, calendar: calendar)
        let merged = BingoEvaluator.completions(
            taskIds: record.taskIds,
            week: week,
            today: today,
            snapshot: context.snapshot,
            calendar: calendar,
            stored: record.completedByIndex
        )
        record.setCompleted(merged)

        var update = FeatureUpdate()

        var linesDone = record.linesDone ?? []
        var newLines: [BingoLine] = []
        for line in BingoEvaluator.completedLines(taskIds: record.taskIds, completed: merged) {
            update.grants.append(RewardGrant(key: BingoEvaluator.lineGrantKey(week: week, line: line), kind: .xp(XPAward.bingoLine)))
            if !linesDone.contains(line.id) {
                linesDone.append(line.id)
                newLines.append(line)
            }
        }
        record.linesDone = linesDone.isEmpty ? nil : linesDone
        await store.addLines(newLines.count)
        for line in newLines {
            update.moments.append(FeatureMoment(
                featureId: Self.id,
                title: String(
                    format: String(localized: "BINGO! %@", bundle: .module, comment: "Moment title when a bingo line completes. %@ = line name, e.g. 'Row 2'."),
                    line.displayName
                ),
                message: String(localized: "A full line on your weekly card.", bundle: .module, comment: "Moment message when a bingo line completes."),
                symbol: Self.symbol,
                style: .celebration,
                xpAwarded: XPAward.bingoLine
            ))
        }

        if BingoEvaluator.isFull(taskIds: record.taskIds, completed: merged) {
            update.grants.append(RewardGrant(key: BingoEvaluator.fullCardGrantKey(week: week), kind: .xp(XPAward.bingoFullCard)))
            update.grants.append(RewardGrant(key: BingoEvaluator.freezeGrantKey(week: week), kind: .streakFreeze))
            if !record.isFull {
                record.full = true
                await store.addFullCard()
                update.moments.append(FeatureMoment(
                    featureId: Self.id,
                    title: String(localized: "Blackout! Full card", bundle: .module, comment: "Moment title when every bingo square is done."),
                    message: String(localized: "Every square done. You earned a streak freeze.", bundle: .module, comment: "Moment message for a full bingo card."),
                    symbol: Self.symbol,
                    style: .celebration,
                    xpAwarded: XPAward.bingoFullCard
                ))
            }
        }

        await store.setCard(record, week: week)
        update.unlockBadgeIds = await badgeIds(alreadyUnlocked: context.unlockedBadgeIds)
        await store.prune()
        // A failed save costs at most a repeated moment next run: grants
        // are idempotent in RewardLedger and badges in AchievementStore.
        try? await store.save()

        update.summary = Self.summary(for: Self.status(week: week, record: record), daysLeft: Self.daysLeft(week: week, today: today, calendar: calendar))
        return update
    }

    // MARK: - UI reads (store only -- work before this launch's first run)

    /// This week's card, `nil` until the feature has run this week.
    public func currentCard(now: Date = Date(), calendar: Calendar = .current) async -> BingoCardStatus? {
        let week = WeekKey(date: now, calendar: calendar)
        guard let record = await store.card(week: week) else { return nil }
        return Self.status(week: week, record: record)
    }

    /// Earlier stored cards (up to 11), newest first.
    public func pastCards(now: Date = Date(), calendar: Calendar = .current) async -> [BingoCardStatus] {
        let week = WeekKey(date: now, calendar: calendar)
        return await store.allCards()
            .filter { $0.week < week }
            .map { Self.status(week: $0.week, record: $0.card) }
    }

    // MARK: - Pure helpers

    public static func status(week: WeekKey, record: BingoCardRecord) -> BingoCardStatus {
        let completed = record.completedByIndex
        var squares: [BingoSquareStatus] = []
        for (index, taskId) in record.taskIds.enumerated() {
            squares.append(BingoSquareStatus(
                index: index,
                task: BingoEvaluator.isFree(taskId) ? nil : BingoTaskCatalog.task(id: taskId),
                completedDay: completed[index]
            ))
        }
        return BingoCardStatus(
            week: week,
            squares: squares,
            lines: BingoEvaluator.completedLines(taskIds: record.taskIds, completed: completed),
            isFull: BingoEvaluator.isFull(taskIds: record.taskIds, completed: completed)
        )
    }

    /// Days of `week` from `today` (a `yyyy-MM-dd` key) to Sunday,
    /// including today; 0 once the week is over.
    public static func daysLeft(week: WeekKey, today: String, calendar: Calendar) -> Int {
        week.dayKeys(calendar: calendar).filter { $0 >= today }.count
    }

    static func summary(for card: BingoCardStatus, daysLeft: Int) -> FeatureSummary {
        FeatureSummary(
            title: String(localized: "Weekly Bingo", bundle: .module, comment: "Bingo hub card title."),
            subtitle: String(
                format: String(localized: "Lines: %1$lld · Squares: %2$lld/9 · Days left: %3$lld", bundle: .module, comment: "Bingo hub card subtitle: completed lines, done squares out of 9, days left this week."),
                card.lines.count,
                card.doneCount,
                daysLeft
            ),
            fraction: Double(card.doneCount) / Double(BingoCardGenerator.cardSize),
            symbol: symbol
        )
    }

    // MARK: - Private

    private func cardForWeek(_ week: WeekKey, snapshot: SignalsSnapshot, calendar: Calendar) async -> BingoCardRecord {
        if let existing = await store.card(week: week), existing.taskIds.count == BingoCardGenerator.cardSize {
            return existing
        }
        let recent = snapshot.days(snapshot.recentDayKeys(BingoCardGenerator.eligibilityWindowDays))
        let eligible = BingoCardGenerator.eligibleTasks(recentDays: recent)
        var previousIds: [String]?
        if let previousWeek = week.adding(weeks: -1, calendar: calendar) {
            previousIds = await store.card(week: previousWeek)?.taskIds
        }
        let record = BingoCardRecord(taskIds: BingoCardGenerator.generate(week: week, eligible: eligible, previousCard: previousIds))
        await store.setCard(record, week: week)
        return record
    }

    private func badgeIds(alreadyUnlocked: Set<String>) async -> [String] {
        let totalLines = await store.totalLines()
        let fullCards = await store.fullCards()
        var ids: [String] = []
        if totalLines >= 1 { ids.append(BingoTaskCatalog.firstLineBadgeId) }
        if totalLines >= 50 { ids.append(BingoTaskCatalog.lines50BadgeId) }
        if fullCards >= 1 { ids.append(BingoTaskCatalog.blackout1BadgeId) }
        if fullCards >= 4 { ids.append(BingoTaskCatalog.blackout4BadgeId) }
        if fullCards >= 12 { ids.append(BingoTaskCatalog.blackout12BadgeId) }
        for entry in await store.allCards() {
            let completed = entry.card.completedByIndex
            if BingoEvaluator.hasFourCorners(taskIds: entry.card.taskIds, completed: completed),
               !ids.contains(BingoTaskCatalog.fourCornersBadgeId) {
                ids.append(BingoTaskCatalog.fourCornersBadgeId)
            }
            let lines = Set(entry.card.linesDone ?? [])
            if lines.contains("diag0"), lines.contains("diag1"), !ids.contains(BingoTaskCatalog.xMarksBadgeId) {
                ids.append(BingoTaskCatalog.xMarksBadgeId)
            }
        }
        return ids.filter { !alreadyUnlocked.contains($0) }
    }
}
