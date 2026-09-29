// AppShell — which tabs the app shows, which one it opens on, and where an
// external route lands, per experience (rebrand-to-jirkas-arc design.md D6,
// D8). Two experiences share one tab shell:
//
//   - `.foodFirst`: the default and the only experience without a vault
//     connection (every standalone install, so the second install always
//     stays here). Exactly the three tabs the app had before: Today (the
//     food log), Progress, Profile.
//   - `.training`: only when the app reports training enabled (an enabled
//     vault connection on a Garmin-connected install, since
//     add-training-today-and-plan). Four tabs: Today, Plan, Progress,
//     Profile.
//
// Why it lives here and not in the app: the tab set, the start-tab fallback
// and the route targets are the rules worth pinning, and the app can't be
// unit-tested (no Mac). The app uses `ShellTab` as its `AppRouter.Tab` and
// draws the labels; nothing user-facing lives here. AppearanceKit
// doesn't know what a vault is -- it takes one Bool (`AppExperience(
// trainingEnabled:)`).
//
// Depended on by: LayoutCatalog.today(for:) (LayoutModel.swift), the app's
// ContentView (tab set), AppRouter (start tab, route targets, correcting the
// selection when the experience changes) and AppearanceSettingsView (the
// "Start on" picker). Tested by AppShellTests.

import Foundation

/// Which experience an install runs (design D6).
public enum AppExperience: String, CaseIterable, Sendable {
    case foodFirst
    case training

    public static let `default`: AppExperience = .foodFirst

    /// `.training` only when the app says training is enabled; everything
    /// else, including every standalone install, is `.foodFirst`.
    public init(trainingEnabled: Bool) {
        self = trainingEnabled ? .training : .foodFirst
    }

    /// Whether the app presents itself with its training plan (Settings ->
    /// About): only in the training experience. Food-first installs,
    /// including every standalone one, describe food and weight only.
    public var mentionsTrainingPlan: Bool {
        self == .training
    }
}

/// A tab of the shell. Tabs are never reordered or hidden by the user; the
/// experience alone decides the set.
public enum ShellTab: String, CaseIterable, Sendable {
    case today
    case plan
    case progress
    case profile
}

/// An external entry point the shell routes (widget link, Control, `plan`
/// link). Theme links open a sheet over any tab and are not routed here.
public enum ShellRoute: String, CaseIterable, Sendable {
    /// `garminfood://logFood`, the barcode Control: Today plus the catalog.
    case logFood
    /// `garminfood://plan[?date=YYYY-MM-DD]`.
    case plan
}

public enum AppShell {
    /// The tabs in order (design D6's table).
    public static func tabs(for experience: AppExperience) -> [ShellTab] {
        switch experience {
        case .foodFirst: return [.today, .progress, .profile]
        case .training: return [.today, .plan, .progress, .profile]
        }
    }

    public static func shows(_ tab: ShellTab, in experience: AppExperience) -> Bool {
        tabs(for: experience).contains(tab)
    }

    /// The tab a start tab opens.
    public static func tab(for startTab: StartTab) -> ShellTab {
        switch startTab {
        case .today: return .today
        case .plan: return .plan
        case .progress: return .progress
        }
    }

    /// What the "Start on" picker offers: the experience's tabs that can be
    /// a start tab (Profile never is), in tab order.
    public static func startTabs(for experience: AppExperience) -> [StartTab] {
        tabs(for: experience).compactMap { shellTab in
            StartTab.allCases.first { AppShell.tab(for: $0) == shellTab }
        }
    }

    /// The stored start tab when this experience shows it; Today for
    /// anything else -- nothing stored, a value this build doesn't know, or
    /// `plan` on a food-first install (design D8).
    public static func resolvedStartTab(stored: String?, experience: AppExperience) -> StartTab {
        guard let stored, let tab = StartTab(rawValue: stored), startTabs(for: experience).contains(tab) else {
            return .default
        }
        return tab
    }

    /// The tab to keep selected after the experience changed: the same one
    /// if the new set still shows it, else Today (design D8).
    public static func correctedSelection(_ selected: ShellTab, experience: AppExperience) -> ShellTab {
        shows(selected, in: experience) ? selected : .today
    }

    /// Where an external route lands (design D8): the food routes always on
    /// Today; `plan` on Plan in training, on Today in food-first.
    public static func destination(for route: ShellRoute, experience: AppExperience) -> ShellTab {
        switch route {
        case .logFood: return .today
        case .plan: return shows(.plan, in: experience) ? .plan : .today
        }
    }

    /// The `date` of a `plan` link, as calendar-free year/month/day, or
    /// `nil` unless it is exactly `YYYY-MM-DD` and a real Gregorian day.
    /// The Plan tab interprets it in the plan's own time zone later
    /// (add-training-today-and-plan), so no `Date` is made here.
    public static func planLinkDate(_ value: String?) -> DateComponents? {
        guard let value, value.count == 10 else { return nil }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ part in part.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              year >= 1, (1...12).contains(month), day >= 1
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        // The month's length from its first day: a date made from the day
        // itself would roll 2026-02-30 over into March.
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: firstOfMonth),
              days.contains(day)
        else { return nil }
        return DateComponents(year: year, month: month, day: day)
    }
}

public extension LayoutConfig {
    /// The start tab for `experience` (`AppShell.resolvedStartTab`).
    func resolvedStartTab(for experience: AppExperience) -> StartTab {
        AppShell.resolvedStartTab(stored: startTab, experience: experience)
    }
}
