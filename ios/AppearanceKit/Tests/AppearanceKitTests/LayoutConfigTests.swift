// LayoutConfigTests — task 3.1: `layout.v1` is decoded leniently (D7) -- an
// absent blob is the default, a missing or garbled field falls back on its
// own, a garbled placement is dropped alone, unknown fields are ignored, and
// only a payload that isn't a JSON object is reported undecodable (for
// quarantine) -- plus the Today presets (D9, screen-layout spec "Presets
// and reset").

import XCTest
@testable import AppearanceKit

final class LayoutConfigTests: XCTestCase {

    private func load(_ json: String) -> LayoutConfig.LoadResult {
        LayoutConfig.load(from: Data(json.utf8))
    }

    // MARK: Coding

    func testAbsentGivesDefaults() {
        let result = LayoutConfig.load(from: nil)
        XCTAssertEqual(result.status, .absent)
        XCTAssertEqual(result.config, .default)
        XCTAssertNil(result.config.today)
        XCTAssertNil(result.config.appliedPreset)
    }

    func testEmptyObjectGivesDefaults() {
        let result = load("{}")
        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.config, .default)
    }

    func testGarbageIsUndecodable() {
        XCTAssertEqual(LayoutConfig.load(from: Data([0xFF, 0x00, 0x13])).status, .undecodable)
        XCTAssertEqual(load("[1,2,3]").status, .undecodable)
        XCTAssertEqual(load("\"today\"").status, .undecodable)
        XCTAssertEqual(load("{\"today\":").status, .undecodable)
    }

    func testRoundTrip() throws {
        var config = LayoutConfig(startTab: "progress")
        config.apply(.minimal)
        let result = LayoutConfig.load(from: try config.encoded())
        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.config, config)
    }

    func testGarbledFieldsFallBackIndividually() {
        let json = #"""
        {"version":"one","today":{"placements":[{"id":"dayNote","isVisible":false}]},
         "logFood":42,"progress":{"placements":"nope"},"startTab":7,"appliedPreset":"minimal",
         "someFutureField":{"x":1}}
        """#
        let result = load(json)
        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.config.version, AppearanceSchema.layoutVersion)
        XCTAssertEqual(result.config.today?.placements, [CardPlacement(id: "dayNote", isVisible: false)])
        XCTAssertNil(result.config.logFood)
        XCTAssertEqual(result.config.progress, ScreenLayout())
        XCTAssertNil(result.config.startTab)
        XCTAssertEqual(result.config.appliedPreset, "minimal")
    }

    func testGarbledPlacementIsDroppedAlone() {
        let json = #"""
        {"today":{"placements":[
          {"id":"summary","variant":"compact"},
          {"isVisible":false},
          {"id":""},
          17,
          {"id":"meals","isVisible":"yes","variant":3},
          {"id":"futureCard","isVisible":false,"extra":true}
        ]}}
        """#
        let placements = load(json).config.today?.placements
        XCTAssertEqual(placements, [
            CardPlacement(id: "summary", isVisible: true, variant: "compact"),
            CardPlacement(id: "meals", isVisible: true, variant: nil),
            CardPlacement(id: "futureCard", isVisible: false, variant: nil),
        ])
    }

    // MARK: Editing and presets

    func testEditClearsAppliedPresetOnlyForToday() {
        var config = LayoutConfig.default
        config.apply(.athlete)
        config.edit(.logFood) { stored, specs in LayoutResolver.setVisible(false, for: "recent", in: stored, specs: specs) }
        XCTAssertEqual(LayoutPreset.current(in: config), .athlete)
        config.edit(.today) { stored, specs in LayoutResolver.setVisible(false, for: "dayNote", in: stored, specs: specs) }
        XCTAssertNil(config.appliedPreset)
        XCTAssertNil(LayoutPreset.current(in: config))
    }

    func testNoOpEditKeepsThePreset() {
        var config = LayoutConfig.default
        config.edit(.today) { stored, specs in LayoutResolver.setVisible(true, for: "dayNote", in: stored, specs: specs) }
        XCTAssertNil(config.today, "a no-op edit stores nothing")
        XCTAssertEqual(LayoutPreset.current(in: config), .full)

        config.edit(.today) { stored, specs in LayoutResolver.move("daySwitcher", .down, in: stored, specs: specs) }
        XCTAssertEqual(LayoutPreset.current(in: config), .full, "a pinned card can't move")

        config.apply(.athlete)
        config.edit(.today) { stored, specs in LayoutResolver.setVisible(true, for: "dayNote", in: stored, specs: specs) }
        XCTAssertEqual(LayoutPreset.current(in: config), .athlete)
    }

    func testMigrationKeepsANewerVersion() {
        let newer = AppearanceSchema.layoutVersion + 3
        let result = load("{\"version\":\(newer)}")
        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.config.version, newer)
        XCTAssertEqual(LayoutMigration.migrate(LayoutConfig(version: 0)).version, AppearanceSchema.layoutVersion)
    }

    func testResetReturnsToFull() {
        var config = LayoutConfig.default
        config.apply(.minimal)
        config.reset(.today)
        XCTAssertNil(config.today)
        XCTAssertEqual(LayoutPreset.current(in: config), .full)
        XCTAssertEqual(config.resolved(.today), LayoutConfig.default.resolved(.today))
    }

    func testFullIsTheDefault() {
        var config = LayoutConfig.default
        config.apply(.full)
        XCTAssertEqual(config.resolved(.today), LayoutConfig.default.resolved(.today))
        XCTAssertEqual(LayoutPreset.current(in: config), .full)
        XCTAssertEqual(LayoutPreset.current(in: .default), .full)
    }

    /// Spec: Minimal shows the day switcher, a compact summary, collapsed
    /// meals, Log again and the signature, and hides the rest.
    func testMinimal() {
        var config = LayoutConfig.default
        config.apply(.minimal)
        let rows = config.resolved(.today)
        XCTAssertEqual(rows.filter(\.isVisible).map(\.id), ["daySwitcher", "summary", "meals", "logAgain", "signature"])
        XCTAssertEqual(rows.filter { !$0.isVisible }.map(\.id),
                       ["progressStrip", "fasting", "banners", "logMeal", "weightWater", "dayNote"])
        XCTAssertEqual(rows.first { $0.id == "summary" }?.variant, SummaryVariant.compact.rawValue)
        XCTAssertEqual(rows.first { $0.id == "meals" }?.variant, MealsVariant.collapsed.rawValue)
        XCTAssertEqual(config.appliedPreset, "minimal")
    }

    /// D9: Athlete moves Weight & Water up under the streak strip and shows
    /// everything.
    func testAthlete() {
        var config = LayoutConfig.default
        config.apply(.athlete)
        let rows = config.resolved(.today)
        XCTAssertEqual(rows.map(\.id), [
            "daySwitcher", "summary", "progressStrip", "weightWater", "meals",
            "fasting", "logAgain", "logMeal", "banners", "dayNote", "signature",
        ])
        XCTAssertTrue(rows.allSatisfy(\.isVisible))
        XCTAssertEqual(rows.first { $0.id == "summary" }?.variant, SummaryVariant.ring.rawValue)
        XCTAssertEqual(rows.first { $0.id == "weightWater" }?.variant, WeightWaterVariant.both.rawValue)
    }

    func testEveryPresetNamesEveryTodayCardOnce() {
        for preset in LayoutPreset.allCases {
            let ids = preset.todayLayout.placements.map(\.id)
            XCTAssertEqual(ids.sorted(), TodayCardID.allCases.map(\.rawValue).sorted(), "\(preset)")
        }
    }

    func testUnknownAppliedPresetIsCustom() {
        let config = LayoutConfig(today: LayoutPreset.minimal.todayLayout, appliedPreset: "zen")
        XCTAssertNil(LayoutPreset.current(in: config))
    }

    func testCatalogIDsMatchEnums() {
        XCTAssertEqual(LayoutCatalog.today.map(\.id), TodayCardID.allCases.map(\.rawValue))
        XCTAssertEqual(LayoutCatalog.logFood.map(\.id), LogFoodShelfID.allCases.map(\.rawValue))
        XCTAssertEqual(LayoutCatalog.progress.map(\.id), ProgressCardID.allCases.map(\.rawValue))
        for screen in LayoutScreen.allCases {
            let specs = LayoutCatalog.specs(for: screen)
            XCTAssertEqual(Set(specs.map(\.id)).count, specs.count, "\(screen) has duplicate ids")
            for spec in specs where !spec.variants.isEmpty {
                XCTAssertNotNil(spec.defaultVariant)
                XCTAssertTrue(spec.variants.contains(spec.defaultVariant ?? ""))
            }
        }
    }
}
