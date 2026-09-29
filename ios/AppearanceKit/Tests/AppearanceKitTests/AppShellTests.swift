// AppShellTests — rebrand-to-jirkas-arc tasks 1.1, 1.2 and 1.6 (design.md
// D6, D8, D11): the tab set per experience (food-first pinned to the three
// tabs the app had before), the start tab resolved for every stored value in
// both experiences, the selection fixed up when the experience changes,
// where each external route lands, the `plan` link's date parser, and the
// per-experience Today catalog (food-first byte for byte the pre-change
// catalog).

import XCTest
@testable import AppearanceKit

final class AppShellTests: XCTestCase {

    // MARK: Experience

    func testExperienceFromTheOneInput() {
        XCTAssertEqual(AppExperience(trainingEnabled: false), .foodFirst)
        XCTAssertEqual(AppExperience(trainingEnabled: true), .training)
        XCTAssertEqual(AppExperience.default, .foodFirst)
    }

    /// Settings -> About names the training plan only in training.
    func testOnlyTrainingMentionsTheTrainingPlan() {
        XCTAssertTrue(AppExperience.training.mentionsTrainingPlan)
        XCTAssertFalse(AppExperience.foodFirst.mentionsTrainingPlan)
        XCTAssertFalse(AppExperience(trainingEnabled: false).mentionsTrainingPlan)
    }

    // MARK: Tabs

    /// The shell before this change: Today, Progress, Profile.
    func testFoodFirstTabsAreTheOriginalThree() {
        XCTAssertEqual(AppShell.tabs(for: .foodFirst), [.today, .progress, .profile])
        XCTAssertFalse(AppShell.shows(.plan, in: .foodFirst))
    }

    func testTrainingTabsAddPlanSecond() {
        XCTAssertEqual(AppShell.tabs(for: .training), [.today, .plan, .progress, .profile])
        XCTAssertTrue(AppShell.shows(.plan, in: .training))
    }

    // MARK: Start tab

    func testStartTabsOfferedPerExperience() {
        XCTAssertEqual(AppShell.startTabs(for: .foodFirst), [.today, .progress])
        XCTAssertEqual(AppShell.startTabs(for: .training), [.today, .plan, .progress])
    }

    func testStartTabMapsToItsTab() {
        XCTAssertEqual(AppShell.tab(for: .today), .today)
        XCTAssertEqual(AppShell.tab(for: .plan), .plan)
        XCTAssertEqual(AppShell.tab(for: .progress), .progress)
    }

    /// Every stored value x experience, including an unknown string and
    /// `plan` on a food-first install.
    func testResolvedStartTabForEveryStoredValue() {
        let cases: [(stored: String?, foodFirst: StartTab, training: StartTab)] = [
            (nil, .today, .today),
            ("today", .today, .today),
            ("plan", .today, .plan),
            ("progress", .progress, .progress),
            ("profile", .today, .today),
            ("season", .today, .today),
            ("", .today, .today),
            ("Plan", .today, .today),
        ]
        for c in cases {
            XCTAssertEqual(AppShell.resolvedStartTab(stored: c.stored, experience: .foodFirst), c.foodFirst, "food-first, stored \(String(describing: c.stored))")
            XCTAssertEqual(AppShell.resolvedStartTab(stored: c.stored, experience: .training), c.training, "training, stored \(String(describing: c.stored))")
        }
    }

    func testLayoutConfigStartTabPerExperience() {
        var config = LayoutConfig.default
        config.setStartTab(.plan)
        XCTAssertEqual(config.startTab, "plan")
        XCTAssertEqual(config.resolvedStartTab(for: .training), .plan)
        XCTAssertEqual(config.resolvedStartTab(for: .foodFirst), .today)
        // The stored choice survives a food-first stretch untouched.
        XCTAssertEqual(config.startTab, "plan")
    }

    // MARK: Selection

    func testLeavingTrainingWhileOnPlanSelectsToday() {
        XCTAssertEqual(AppShell.correctedSelection(.plan, experience: .foodFirst), .today)
    }

    func testSelectionKeptWhenStillShown() {
        for tab in ShellTab.allCases {
            XCTAssertEqual(AppShell.correctedSelection(tab, experience: .training), tab)
        }
        XCTAssertEqual(AppShell.correctedSelection(.progress, experience: .foodFirst), .progress)
        XCTAssertEqual(AppShell.correctedSelection(.profile, experience: .foodFirst), .profile)
    }

    // MARK: Routes

    func testRouteDestinations() {
        XCTAssertEqual(AppShell.destination(for: .logFood, experience: .foodFirst), .today)
        XCTAssertEqual(AppShell.destination(for: .logFood, experience: .training), .today)
        XCTAssertEqual(AppShell.destination(for: .plan, experience: .training), .plan)
        XCTAssertEqual(AppShell.destination(for: .plan, experience: .foodFirst), .today)
    }

    func testPlanLinkDateAcceptsARealDay() {
        XCTAssertEqual(AppShell.planLinkDate("2026-11-04"), DateComponents(year: 2026, month: 11, day: 4))
        XCTAssertEqual(AppShell.planLinkDate("2028-02-29"), DateComponents(year: 2028, month: 2, day: 29))
        XCTAssertEqual(AppShell.planLinkDate("2026-12-31"), DateComponents(year: 2026, month: 12, day: 31))
    }

    func testPlanLinkDateRejectsAnythingElse() {
        let bad: [String?] = [
            nil, "", "2026-11-4", "2026-1-04", "26-11-04", "2026/11/04", "2026-11-04T00:00",
            "2026-13-01", "2026-00-10", "2026-11-00", "2026-02-29", "2026-02-30", "2026-04-31",
            "abcd-ef-gh", "+026-11-04", "2026-1a-04", "٢٠٢٦-١١-٠٤",
        ]
        for value in bad {
            XCTAssertNil(AppShell.planLinkDate(value), "accepted \(String(describing: value))")
        }
    }

    // MARK: Today catalog per experience

    /// The food-first catalog is exactly the pre-change one (the same
    /// golden order LayoutResolverTests pins), so a food-first user's Today
    /// and layout editor are unchanged.
    func testFoodFirstTodayCatalogIsThePreChangeCatalog() {
        XCTAssertEqual(LayoutCatalog.today(for: .foodFirst), LayoutCatalog.today)
        XCTAssertEqual(LayoutCatalog.today(for: .foodFirst).map(\.id), [
            "daySwitcher", "summary", "progressStrip", "fasting", "banners",
            "meals", "supplements", "logAgain", "logMeal", "weightWater", "dayNote", "signature",
        ])
        XCTAssertEqual(LayoutCatalog.specs(for: .today, experience: .foodFirst), LayoutCatalog.specs(for: .today))
    }

    /// add-training-today-and-plan D7: the training catalog's golden order
    /// -- the training cards lead, the summary is compact.
    func testTrainingTodayCatalogOrder() {
        XCTAssertEqual(LayoutCatalog.today(for: .training).map(\.id), [
            "daySwitcher", "raceCountdown", "trainingDay", "habitsToday", "weeklyNote",
            "summary", "logAgain", "meals", "weightWater", "logMeal",
            "progressStrip", "fasting", "supplements", "banners", "dayNote", "signature",
        ])
        let specs = LayoutCatalog.today(for: .training)
        XCTAssertEqual(specs.first { $0.id == "summary" }?.defaultVariant, SummaryVariant.compact.rawValue)
        XCTAssertEqual(specs.first { $0.id == "meals" }?.defaultVariant, MealsVariant.expanded.rawValue)
        XCTAssertEqual(specs.first { $0.id == "trainingDay" }?.variants, ["options", "compact"])
        XCTAssertEqual(specs.first { $0.id == "trainingDay" }?.defaultVariant, "options")
        XCTAssertEqual(specs.first?.pin, .top)
        XCTAssertEqual(specs.last?.pin, .bottom)
        // Same cards as food-first plus the four training cards, once each.
        XCTAssertEqual(
            Set(specs.map(\.id)),
            Set(LayoutCatalog.today.map(\.id)).union(TodayCardID.trainingCards.map(\.rawValue))
        )
        XCTAssertEqual(Set(specs.map(\.id)).count, specs.count)
    }

    func testFoodFirstCatalogHasNoTrainingCard() {
        let ids = Set(LayoutCatalog.today(for: .foodFirst).map(\.id))
        for card in TodayCardID.trainingCards {
            XCTAssertFalse(ids.contains(card.rawValue), card.rawValue)
            XCTAssertTrue(card.isTrainingCard)
        }
        XCTAssertEqual(TodayCardID.foodCards.map(\.rawValue), LayoutCatalog.today.map(\.id))
    }

    func testOtherScreensDoNotDependOnExperience() {
        for screen in [LayoutScreen.logFood, .progress] {
            for experience in AppExperience.allCases {
                XCTAssertEqual(LayoutCatalog.specs(for: screen, experience: experience), LayoutCatalog.specs(for: screen))
            }
        }
    }

    func testConfigResolvesPerExperience() {
        let config = LayoutConfig.default
        XCTAssertEqual(config.resolved(.today, experience: .foodFirst), config.resolved(.today))
        XCTAssertTrue(config.isDefaultLayout(.today, experience: .training))
    }
}
