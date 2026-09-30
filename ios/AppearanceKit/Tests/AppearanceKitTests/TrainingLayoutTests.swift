// TrainingLayoutTests — the training experience's Today layout and its
// readiness colours (add-training-today-and-plan tasks 3.5, 3.6; design D7,
// D9):
//
//   - an owner who already customised Today gets the four training cards
//     right after the day switcher (LayoutResolver rule 3), with every food
//     card keeping its position, visibility and variant;
//   - the `training` preset is the training default order and is offered
//     only in the training experience;
//   - polish-training-today: the Habits card joins a stored layout visible,
//     right after the training card, and the retired "habitsToday" id is
//     kept in storage but not rendered;
//   - `success`, `warning` and `danger` (the G, A and R option cards) stay
//     pairwise apart in every theme x scheme x contrast.

import XCTest
@testable import AppearanceKit

final class TrainingLayoutTests: XCTestCase {
    private let trainingIDs = ["raceCountdown", "trainingDay", "habits", "weeklyNote"]

    func testNothingStoredIsTheTrainingDefault() {
        let rows = LayoutConfig.default.resolved(.today, experience: .training)
        XCTAssertEqual(rows.map(\.id), LayoutCatalog.trainingToday.map(\.id))
        XCTAssertEqual(rows.first { $0.id == "summary" }?.variant, SummaryVariant.compact.rawValue)
        XCTAssertEqual(rows.first { $0.id == "trainingDay" }?.variant, TrainingDayVariant.options.rawValue)
        XCTAssertTrue(rows.allSatisfy(\.isVisible))
    }

    func testTrainingCardsJoinACustomisedFoodLayoutAfterTheDaySwitcher() {
        // The owner's own food layout: Athlete (weight & water moved up,
        // ring summary), then meals collapsed and the day note hidden.
        var config = LayoutConfig.default
        config.apply(.athlete)
        config.edit(.today) { stored, specs in
            LayoutResolver.setVariant(MealsVariant.collapsed.rawValue, for: "meals", in: stored, specs: specs)
        }
        config.edit(.today) { stored, specs in
            LayoutResolver.setVisible(false, for: "dayNote", in: stored, specs: specs)
        }
        let foodRows = config.resolved(.today, experience: .foodFirst)

        let rows = config.resolved(.today, experience: .training)
        XCTAssertEqual(rows.map(\.id), ["daySwitcher"] + trainingIDs + [
            "summary", "progressStrip", "weightWater", "meals",
            "supplements", "fasting", "logAgain", "logMeal", "banners", "dayNote", "signature",
        ])
        // Every food card keeps its order, visibility and variant.
        let foodInTraining = rows.filter { !trainingIDs.contains($0.id) }
        XCTAssertEqual(foodInTraining.map(\.id), foodRows.map(\.id))
        XCTAssertEqual(foodInTraining.map(\.isVisible), foodRows.map(\.isVisible))
        XCTAssertEqual(foodInTraining.map(\.variant), foodRows.map(\.variant))
        XCTAssertEqual(rows.first { $0.id == "summary" }?.variant, SummaryVariant.ring.rawValue)
        XCTAssertEqual(rows.first { $0.id == "meals" }?.variant, MealsVariant.collapsed.rawValue)
        XCTAssertEqual(rows.first { $0.id == "dayNote" }?.isVisible, false)
        // The training cards arrive visible.
        XCTAssertTrue(rows.filter { trainingIDs.contains($0.id) }.allSatisfy(\.isVisible))
    }

    func testFoodFirstNeverRendersAStoredTrainingPlacement() {
        var config = LayoutConfig.default
        config.edit(.today, experience: .training) { stored, specs in
            LayoutResolver.setVisible(false, for: "weeklyNote", in: stored, specs: specs)
        }
        let stored = config.today?.placements.map(\.id) ?? []
        XCTAssertTrue(stored.contains("weeklyNote"))
        let foodRows = config.resolved(.today, experience: .foodFirst)
        XCTAssertFalse(foodRows.contains { trainingIDs.contains($0.id) })
        XCTAssertEqual(Set(foodRows.map(\.id)), Set(LayoutCatalog.today.map(\.id)))
        // Back in training, the hidden choice is still there.
        XCTAssertEqual(config.resolved(.today, experience: .training).first { $0.id == "weeklyNote" }?.isVisible, false)
    }

    func testTrainingPresetOnlyInTraining() {
        XCTAssertFalse(LayoutPreset.presets(for: .foodFirst).contains(.training))
        XCTAssertEqual(LayoutPreset.presets(for: .training).first, .training)
        var config = LayoutConfig.default
        XCTAssertEqual(LayoutPreset.current(in: config, experience: .training), .training)
        XCTAssertEqual(LayoutPreset.current(in: config, experience: .foodFirst), .full)
        config.apply(.training)
        XCTAssertEqual(config.resolved(.today, experience: .training).map(\.id), LayoutCatalog.trainingToday.map(\.id))
        XCTAssertEqual(LayoutPreset.current(in: config, experience: .training), .training)
    }

    func testFoodPresetsInTrainingPutTheTrainingCardsFirst() {
        var config = LayoutConfig.default
        config.apply(.minimal)
        let rows = config.resolved(.today, experience: .training)
        XCTAssertEqual(Array(rows.map(\.id).prefix(5)), ["daySwitcher"] + trainingIDs)
        XCTAssertEqual(rows.first { $0.id == "fasting" }?.isVisible, false)
    }

    /// polish-training-today D2: a layout stored with the old "Today's
    /// habits" card (even hidden, even moved to the bottom) gets the new
    /// Habits card visible right after the training card; the retired id
    /// stays in storage, unrendered.
    func testHabitsCardJoinsAStoredLayoutVisibleAfterTheTrainingCard() {
        let specs = LayoutCatalog.today(for: .training)
        var ids = specs.map(\.id).filter { $0 != "habits" }
        ids.removeAll { $0 == "signature" }
        ids.append("habitsToday")
        ids.append("signature")
        let stored = ScreenLayout(placements: ids.map { CardPlacement(id: $0, isVisible: $0 != "habitsToday") })

        let rows = LayoutResolver.resolve(stored: stored, specs: specs)
        let order = rows.map(\.id)
        XCTAssertFalse(order.contains("habitsToday"))
        let training = order.firstIndex(of: "trainingDay")
        XCTAssertEqual(order.firstIndex(of: "habits"), training.map { $0 + 1 })
        XCTAssertEqual(rows.first { $0.id == "habits" }?.isVisible, true)
        XCTAssertTrue(LayoutResolver.merged(stored: stored, specs: specs).contains { $0.id == "habitsToday" })
        XCTAssertFalse(TodayCardID.foodCards.contains(.habits))
    }

    // MARK: Readiness colours (D9)

    func testReadinessColoursStayApartInEveryPalette() {
        let roles: [ThemeRole] = [.success, .warning, .danger]
        for theme in ThemeCatalog.all {
            for scheme in ThemeColorScheme.allCases {
                for increased in [false, true] {
                    let palette = PaletteResolver.resolve(theme: theme, requestedScheme: scheme, increasedContrast: increased)
                    let colors = roles.map { palette.referenceValue($0) }
                    for i in colors.indices {
                        for j in colors.indices where j > i {
                            let distance = ColorMath.deltaEOK(colors[i], colors[j])
                            XCTAssertGreaterThanOrEqual(
                                distance,
                                ContrastPolicy.minimumReadinessDistance,
                                "\(theme.id) \(scheme) increased=\(increased): \(roles[i]) vs \(roles[j]) ΔE \(String(format: "%.3f", distance))"
                            )
                        }
                    }
                }
            }
        }
    }
}
