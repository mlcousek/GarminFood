// LayoutResolverTests — task 3.1: the golden default order of every screen
// (it must equal the order the screens rendered before this change, so a
// user who never edits sees zero difference), each D8 resolver rule, and the
// editor operations (drag, VoiceOver move up/down, hide, variant) including
// a round trip with a card this build doesn't know.

import XCTest
@testable import AppearanceKit

final class LayoutResolverTests: XCTestCase {

    private let today = LayoutCatalog.today

    private func ids(_ rows: [ResolvedPlacement]) -> [String] {
        rows.map(\.id)
    }

    private func layout(_ ids: [String]) -> ScreenLayout {
        ScreenLayout(placements: ids.map { CardPlacement(id: $0) })
    }

    // MARK: Golden defaults (rule 6)

    /// `TodayView`'s pre-change body, top to bottom: DaySwitcher,
    /// DaySummaryCard, ProgressStrip, FastingHomeSection, TodaySlotHost,
    /// the meal cards, Log again, Log a meal, Weight & Water, DayNoteCard,
    /// AppSignatureView.
    func testGoldenTodayDefault() {
        let rows = LayoutResolver.resolve(stored: nil, specs: today)
        XCTAssertEqual(ids(rows), [
            "daySwitcher", "summary", "progressStrip", "fasting", "banners",
            "meals", "logAgain", "logMeal", "weightWater", "dayNote", "signature",
        ])
        XCTAssertTrue(rows.allSatisfy(\.isVisible))
        let variants = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.variant) })
        XCTAssertEqual(variants["summary"], "ring")
        XCTAssertEqual(variants["meals"], "expanded")
        XCTAssertEqual(variants["weightWater"], "both")
        XCTAssertEqual(variants["logAgain"], .some(nil))
    }

    /// `FoodCatalogView`'s empty-search shelves, then the custom foods.
    func testGoldenLogFoodDefault() {
        let rows = LayoutResolver.resolve(stored: nil, specs: LayoutCatalog.logFood)
        XCTAssertEqual(ids(rows), ["quickPick", "favorites", "usual", "meals", "recent", "customFoods"])
        XCTAssertTrue(rows.allSatisfy(\.isVisible))
    }

    /// `ProgressHomeView`: Streak, Level, `ProgressSlotHost`'s eight slots
    /// in their order, Challenges, Achievements, Weight, Hydration, Trends,
    /// Goals.
    func testGoldenProgressDefault() {
        let rows = LayoutResolver.resolve(stored: nil, specs: LayoutCatalog.progress)
        XCTAssertEqual(ids(rows), [
            "streak", "level",
            "boss", "bingo", "seasonal", "journeys", "records", "collections", "sportBody", "secrets",
            "challenges", "achievements", "weight", "hydration", "trends", "goalHistory",
        ])
        XCTAssertTrue(rows.allSatisfy(\.isVisible))
    }

    func testEmptyStoredLayoutResolvesToDefault() {
        let rows = LayoutResolver.resolve(stored: ScreenLayout(), specs: today)
        XCTAssertEqual(ids(rows), ids(LayoutResolver.resolve(stored: nil, specs: today)))
    }

    func testDefaultLayoutRoundTripsToDefault() throws {
        var config = LayoutConfig.default
        config.edit(.today) { stored, specs in LayoutResolver.setVisible(true, for: "dayNote", in: stored, specs: specs) }
        let reloaded = LayoutConfig.load(from: try config.encoded()).config
        XCTAssertEqual(reloaded.resolved(.today), LayoutConfig.default.resolved(.today))
    }

    // MARK: Rule 1

    func testDuplicatesKeepFirstOccurrence() {
        let stored = ScreenLayout(placements: [
            CardPlacement(id: "dayNote", isVisible: false),
            CardPlacement(id: "summary"),
            CardPlacement(id: "dayNote", isVisible: true),
        ])
        let rows = LayoutResolver.resolve(stored: stored, specs: today)
        XCTAssertEqual(rows.filter { $0.id == "dayNote" }.count, 1)
        XCTAssertEqual(rows.first { $0.id == "dayNote" }?.isVisible, false)
        XCTAssertEqual(Array(ids(rows).prefix(3)), ["daySwitcher", "dayNote", "summary"])
    }

    // MARK: Rule 2

    func testUnknownCardIsKeptButNotRendered() {
        let stored = layout([
            "daySwitcher", "summary", "futureCard", "progressStrip", "fasting", "banners",
            "meals", "logAgain", "logMeal", "weightWater", "dayNote", "signature",
        ])
        let rows = LayoutResolver.resolve(stored: stored, specs: today)
        XCTAssertFalse(ids(rows).contains("futureCard"))
        let merged = LayoutResolver.merged(stored: stored, specs: today)
        let summary = merged.firstIndex { $0.id == "summary" }!
        XCTAssertEqual(merged[summary + 1].id, "futureCard")
    }

    func testUnknownCardSurvivesEditsAndStorage() throws {
        var placements = layout([
            "daySwitcher", "summary", "progressStrip", "fasting", "banners",
            "meals", "logAgain", "logMeal", "weightWater", "dayNote", "signature",
        ]).placements
        placements.insert(CardPlacement(id: "futureCard", isVisible: false, variant: "shiny"), at: 2)
        var config = LayoutConfig(today: ScreenLayout(placements: placements))
        // Move Weight & Water above the meals, hide the day note.
        config.edit(.today) { stored, specs in LayoutResolver.move(in: stored, specs: specs, fromOffsets: [8], toOffset: 5) }
        config.edit(.today) { stored, specs in LayoutResolver.setVisible(false, for: "dayNote", in: stored, specs: specs) }

        let reloaded = LayoutConfig.load(from: try config.encoded())
        XCTAssertEqual(reloaded.status, .loaded)
        let stored = reloaded.config.today!.placements
        let future = stored.first { $0.id == "futureCard" }
        XCTAssertEqual(future, CardPlacement(id: "futureCard", isVisible: false, variant: "shiny"))
        // Still right after the card it followed.
        let index = stored.firstIndex { $0.id == "futureCard" }!
        XCTAssertEqual(stored[index - 1].id, "summary")
        // And a build that knows the card renders it where it was kept.
        let newer = today + [CardSpec(id: "futureCard", variants: ["plain", "shiny"], defaultVariant: "plain")]
        let rows = LayoutResolver.resolve(stored: reloaded.config.today, specs: newer)
        let futureRow = rows.first { $0.id == "futureCard" }
        XCTAssertEqual(futureRow?.isVisible, false)
        XCTAssertEqual(futureRow?.variant, "shiny")
    }

    // MARK: Rule 3

    func testNewCardGoesAfterItsDefaultPredecessor() {
        // A layout saved before "bingo" existed, with boss moved to the end.
        let stored = layout(["streak", "level", "seasonal", "challenges", "boss"])
        let rows = LayoutResolver.resolve(stored: stored, specs: LayoutCatalog.progress)
        let order = ids(rows)
        let boss = order.firstIndex(of: "boss")!
        XCTAssertEqual(order[boss + 1], "bingo")
        // The user's own placements keep their relative order.
        XCTAssertEqual(order.filter { ["streak", "level", "seasonal", "challenges", "boss"].contains($0) },
                       ["streak", "level", "seasonal", "challenges", "boss"])
    }

    func testNewCardWithoutPresentPredecessorGoesFirst() {
        let stored = layout(["goalHistory"])
        let order = ids(LayoutResolver.resolve(stored: stored, specs: LayoutCatalog.progress))
        XCTAssertEqual(order.first, "streak")
        XCTAssertEqual(order.last, "goalHistory")
        XCTAssertEqual(Array(order.dropLast()), ids(LayoutResolver.resolve(stored: nil, specs: LayoutCatalog.progress)).filter { $0 != "goalHistory" })
    }

    func testNewCardUsesDefaultVisibility() {
        let specs = [CardSpec(id: "a"), CardSpec(id: "b", defaultVisible: false)]
        let rows = LayoutResolver.resolve(stored: layout(["a"]), specs: specs)
        XCTAssertEqual(rows.map(\.isVisible), [true, false])
    }

    // MARK: Rule 4

    func testInvalidVariantFallsBackToDefault() {
        let stored = ScreenLayout(placements: [
            CardPlacement(id: "summary", variant: "hologram"),
            CardPlacement(id: "meals", variant: "collapsed"),
            CardPlacement(id: "dayNote", variant: "ignored"),
        ])
        let rows = LayoutResolver.resolve(stored: stored, specs: today)
        XCTAssertEqual(rows.first { $0.id == "summary" }?.variant, "ring")
        XCTAssertEqual(rows.first { $0.id == "meals" }?.variant, "collapsed")
        XCTAssertNotNil(rows.first { $0.id == "dayNote" })
        XCTAssertNil(rows.first { $0.id == "dayNote" }?.variant)
        // Kept verbatim in storage (a newer build's variant).
        XCTAssertEqual(LayoutResolver.merged(stored: stored, specs: today).first { $0.id == "summary" }?.variant, "hologram")
    }

    // MARK: Rule 5

    func testPinnedCardsAreForcedToTheirEdgesAndVisible() {
        let stored = ScreenLayout(placements: [
            CardPlacement(id: "signature", isVisible: false),
            CardPlacement(id: "meals"),
            CardPlacement(id: "daySwitcher", isVisible: false),
            CardPlacement(id: "summary"),
        ])
        let rows = LayoutResolver.resolve(stored: stored, specs: today)
        XCTAssertEqual(rows.first?.id, "daySwitcher")
        XCTAssertEqual(rows.last?.id, "signature")
        XCTAssertEqual(rows.first?.isVisible, true)
        XCTAssertEqual(rows.last?.isVisible, true)
        XCTAssertEqual(ids(rows)[1], "meals")
    }

    func testPinnedCardsCannotBeHidden() {
        let result = LayoutResolver.setVisible(false, for: "daySwitcher", in: nil, specs: today)
        XCTAssertEqual(LayoutResolver.resolve(stored: result, specs: today).first?.isVisible, true)
    }

    // MARK: Editing

    func testMoveMatchesListOnMove() {
        // Move weightWater (index 8) above meals (index 5).
        let result = LayoutResolver.move(in: nil, specs: today, fromOffsets: [8], toOffset: 5)
        XCTAssertEqual(ids(LayoutResolver.resolve(stored: result, specs: today)), [
            "daySwitcher", "summary", "progressStrip", "fasting", "banners",
            "weightWater", "meals", "logAgain", "logMeal", "dayNote", "signature",
        ])
        // Moving down: summary (1) to just before logMeal (offset 7).
        let down = LayoutResolver.move(in: nil, specs: today, fromOffsets: [1], toOffset: 7)
        XCTAssertEqual(ids(LayoutResolver.resolve(stored: down, specs: today)), [
            "daySwitcher", "progressStrip", "fasting", "banners", "meals",
            "logAgain", "summary", "logMeal", "weightWater", "dayNote", "signature",
        ])
    }

    func testMovePastAPinnedCardIsUndoneByThePin() {
        // Dropping a card above the day switcher still leaves the switcher first.
        let result = LayoutResolver.move(in: nil, specs: today, fromOffsets: [9], toOffset: 0)
        let order = ids(LayoutResolver.resolve(stored: result, specs: today))
        XCTAssertEqual(order.first, "daySwitcher")
        XCTAssertEqual(order[1], "dayNote")
    }

    func testMoveUpAndDown() {
        let up = LayoutResolver.move("dayNote", .up, in: nil, specs: today)
        let order = ids(LayoutResolver.resolve(stored: up, specs: today))
        XCTAssertEqual(Array(order.suffix(3)), ["dayNote", "weightWater", "signature"])

        let down = LayoutResolver.move("summary", .down, in: nil, specs: today)
        XCTAssertEqual(Array(ids(LayoutResolver.resolve(stored: down, specs: today)).prefix(3)),
                       ["daySwitcher", "progressStrip", "summary"])
    }

    func testMoveStopsAtPinnedNeighbors() {
        XCTAssertFalse(LayoutResolver.canMove("summary", .up, in: nil, specs: today))
        XCTAssertFalse(LayoutResolver.canMove("dayNote", .down, in: nil, specs: today))
        XCTAssertFalse(LayoutResolver.canMove("daySwitcher", .down, in: nil, specs: today))
        XCTAssertFalse(LayoutResolver.canMove("signature", .up, in: nil, specs: today))
        XCTAssertTrue(LayoutResolver.canMove("summary", .down, in: nil, specs: today))
        XCTAssertTrue(LayoutResolver.canMove("dayNote", .up, in: nil, specs: today))
        // An impossible move changes nothing.
        let unchanged = LayoutResolver.move("summary", .up, in: nil, specs: today)
        XCTAssertEqual(LayoutResolver.resolve(stored: unchanged, specs: today),
                       LayoutResolver.resolve(stored: nil, specs: today))
    }

    /// Spec: hiding the day note and showing it again restores it at the
    /// same position.
    func testHideAndShowKeepsPosition() {
        let moved = LayoutResolver.move("dayNote", .up, in: nil, specs: today)
        let hidden = LayoutResolver.setVisible(false, for: "dayNote", in: moved, specs: today)
        XCTAssertEqual(LayoutResolver.resolve(stored: hidden, specs: today).first { $0.id == "dayNote" }?.isVisible, false)
        let shown = LayoutResolver.setVisible(true, for: "dayNote", in: hidden, specs: today)
        XCTAssertEqual(LayoutResolver.resolve(stored: shown, specs: today), LayoutResolver.resolve(stored: moved, specs: today))
    }

    func testSetVariantAcceptsOnlyTheCardsVariants() {
        let compact = LayoutResolver.setVariant("compact", for: "summary", in: nil, specs: today)
        XCTAssertEqual(LayoutResolver.resolve(stored: compact, specs: today).first { $0.id == "summary" }?.variant, "compact")
        let invalid = LayoutResolver.setVariant("collapsed", for: "summary", in: compact, specs: today)
        XCTAssertEqual(LayoutResolver.resolve(stored: invalid, specs: today).first { $0.id == "summary" }?.variant, "compact")
    }

    /// Spec: Weight & Water dragged above the meals survives a relaunch.
    func testMovedLayoutSurvivesStorage() throws {
        var config = LayoutConfig.default
        config.edit(.today) { stored, specs in LayoutResolver.move(in: stored, specs: specs, fromOffsets: [8], toOffset: 5) }
        let reloaded = LayoutConfig.load(from: try config.encoded()).config
        let order = reloaded.resolved(.today).map(\.id)
        XCTAssertLessThan(order.firstIndex(of: "weightWater")!, order.firstIndex(of: "meals")!)
    }

    func testArrayMoveElements() {
        var values = ["a", "b", "c", "d", "e"]
        values.moveElements(fromOffsets: [1, 3], toOffset: 5)
        XCTAssertEqual(values, ["a", "c", "e", "b", "d"])
        values.moveElements(fromOffsets: [4], toOffset: 0)
        XCTAssertEqual(values, ["d", "a", "c", "e", "b"])
        values.moveElements(fromOffsets: [9], toOffset: 0)
        XCTAssertEqual(values, ["d", "a", "c", "e", "b"])
    }
}
