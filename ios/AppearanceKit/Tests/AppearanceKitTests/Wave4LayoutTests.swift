// Wave4LayoutTests — tasks 4.1-4.3: the Log Food and Progress orders the
// screens now render from `LayoutConfig` (edits, persistence, hiding one
// gamification slot without touching its neighbours), the "Default"/"Custom"
// read the Appearance page shows, and the start tab's parse/default rules.
// The golden default orders themselves are in LayoutResolverTests.

import XCTest
@testable import AppearanceKit

final class Wave4LayoutTests: XCTestCase {

    private func ids(_ config: LayoutConfig, _ screen: LayoutScreen) -> [String] {
        config.resolved(screen).map(\.id)
    }

    private func visibleIDs(_ config: LayoutConfig, _ screen: LayoutScreen) -> [String] {
        config.resolved(screen).filter(\.isVisible).map(\.id)
    }

    // MARK: Log Food (4.1)

    /// Spec: shelf order persists -- Recent dragged to the top survives a
    /// relaunch, the others keep their relative order.
    func testLogFoodReorderSurvivesStorage() throws {
        var config = LayoutConfig.default
        config.edit(.logFood) { stored, specs in
            LayoutResolver.move(in: stored, specs: specs, fromOffsets: [4], toOffset: 0)
        }
        let reloaded = LayoutConfig.load(from: try config.encoded()).config
        XCTAssertEqual(ids(reloaded, .logFood), ["recent", "quickPick", "favorites", "usual", "meals", "customFoods"])
        // Log Food edits never touch Today or its preset.
        XCTAssertNil(reloaded.today)
    }

    func testLogFoodHiddenShelfStaysInPlace() {
        var config = LayoutConfig.default
        config.edit(.logFood) { stored, specs in LayoutResolver.setVisible(false, for: "favorites", in: stored, specs: specs) }
        XCTAssertEqual(visibleIDs(config, .logFood), ["quickPick", "usual", "meals", "recent", "customFoods"])
        config.edit(.logFood) { stored, specs in LayoutResolver.setVisible(true, for: "favorites", in: stored, specs: specs) }
        XCTAssertEqual(ids(config, .logFood), ids(.default, .logFood))
        XCTAssertTrue(config.isDefaultLayout(.logFood))
    }

    func testLogFoodShelvesHaveNoPinsOrVariants() {
        for spec in LayoutCatalog.logFood {
            XCTAssertNil(spec.pin, spec.id)
            XCTAssertTrue(spec.hideable, spec.id)
            XCTAssertTrue(spec.variants.isEmpty, spec.id)
        }
    }

    // MARK: Progress (4.2)

    /// Spec: hiding Bingo keeps Boss (each slot is its own entry).
    func testHidingBingoKeepsBoss() {
        var config = LayoutConfig.default
        config.edit(.progress) { stored, specs in LayoutResolver.setVisible(false, for: "bingo", in: stored, specs: specs) }
        let visible = visibleIDs(config, .progress)
        XCTAssertFalse(visible.contains("bingo"))
        XCTAssertTrue(visible.contains("boss"))
        XCTAssertEqual(visible.count, ProgressCardID.allCases.count - 1)
        XCTAssertFalse(config.isDefaultLayout(.progress))
    }

    func testProgressSlotCanMoveAboveStreak() throws {
        var config = LayoutConfig.default
        // Achievements (index 11) to the very top.
        config.edit(.progress) { stored, specs in LayoutResolver.move(in: stored, specs: specs, fromOffsets: [11], toOffset: 0) }
        let reloaded = LayoutConfig.load(from: try config.encoded()).config
        XCTAssertEqual(Array(ids(reloaded, .progress).prefix(3)), ["achievements", "streak", "level"])
    }

    func testProgressCardsHaveNoPinsOrVariants() {
        for spec in LayoutCatalog.progress {
            XCTAssertNil(spec.pin, spec.id)
            XCTAssertTrue(spec.hideable, spec.id)
            XCTAssertTrue(spec.variants.isEmpty, spec.id)
        }
    }

    func testResetOneScreenLeavesTheOthers() {
        var config = LayoutConfig.default
        config.edit(.progress) { stored, specs in LayoutResolver.setVisible(false, for: "bingo", in: stored, specs: specs) }
        config.edit(.logFood) { stored, specs in LayoutResolver.setVisible(false, for: "recent", in: stored, specs: specs) }
        config.reset(.progress)
        XCTAssertTrue(config.isDefaultLayout(.progress))
        XCTAssertFalse(config.isDefaultLayout(.logFood))
    }

    // MARK: isDefaultLayout

    func testDefaultIsDefaultForEveryScreen() {
        for screen in LayoutScreen.allCases {
            XCTAssertTrue(LayoutConfig.default.isDefaultLayout(screen), "\(screen)")
        }
    }

    /// A stored layout equal to the default (e.g. moved and moved back)
    /// still reads as Default.
    func testStoredButEquivalentLayoutIsDefault() {
        let config = LayoutConfig(progress: ScreenLayout(placements: ProgressCardID.allCases.map { CardPlacement(id: $0.rawValue) }))
        XCTAssertTrue(config.isDefaultLayout(.progress))
    }

    // MARK: Start tab (4.3)

    func testStartTabDefaultsToToday() {
        XCTAssertEqual(LayoutConfig.default.resolvedStartTab, .today)
        XCTAssertEqual(StartTab.default, .today)
    }

    func testStartTabUnknownValueFallsBackToToday() {
        XCTAssertEqual(LayoutConfig(startTab: "profile").resolvedStartTab, .today)
        XCTAssertEqual(LayoutConfig(startTab: "").resolvedStartTab, .today)
        XCTAssertEqual(LayoutConfig(startTab: "progress").resolvedStartTab, .progress)
    }

    func testSettingTodayStoresNothing() {
        var config = LayoutConfig.default
        config.setStartTab(.progress)
        XCTAssertEqual(config.startTab, "progress")
        config.setStartTab(.today)
        XCTAssertNil(config.startTab)
        XCTAssertEqual(config, .default)
    }

    func testStartTabSurvivesStorage() throws {
        var config = LayoutConfig.default
        config.setStartTab(.progress)
        let reloaded = LayoutConfig.load(from: try config.encoded())
        XCTAssertEqual(reloaded.status, .loaded)
        XCTAssertEqual(reloaded.config.resolvedStartTab, .progress)
    }

    /// Setting the start tab isn't a Today edit: an applied preset stays.
    func testStartTabKeepsTodayPreset() {
        var config = LayoutConfig.default
        config.apply(.minimal)
        config.setStartTab(.progress)
        XCTAssertEqual(LayoutPreset.current(in: config), .minimal)
    }
}
