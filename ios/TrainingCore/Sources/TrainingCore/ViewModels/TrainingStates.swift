// TrainingStates.swift
//
// The inputs every screen builder shares, and the states that aren't the
// happy path (design D11), so Today and Plan say the same thing in the
// same words:
//
//   - `TrainingSource`: where the plan stands -- still fetching, not
//     published, unreadable with no last good copy, or a loaded snapshot;
//   - `TrainingEmptyState`: a designed empty state (symbol, title,
//     message) for each of them and for rest days, outline-only weeks and
//     weeks outside every phase -- never a spinner forever;
//   - `TrainingNotice`: the subtle lines under a card or in a header
//     ("Plan as of Tue 20 Oct", "Last synced 2 days ago", "Couldn't read
//     the latest plan; showing ...") and the one LOUD one, "Update Jirka's
//     Arc to read this plan";
//   - `TrainingFormatting`: the formatters for one language and snapshot.
//
// Depended on by: every builder and, through them, the app's views.
// Tests: TodayBuilderTests, PlanBuilderTests.

import Foundation

/// The plan as the builders receive it.
public enum TrainingSource: Equatable, Sendable {
    /// Connection on, nothing cached, no answer yet.
    case waitingForFirstSync
    /// Repository reachable, projection not published.
    case notGenerated
    /// A downloaded file was refused and there is no last good copy.
    case unreadable(ProjectionRejection)
    case loaded(TrainingSnapshot)

    public var snapshot: TrainingSnapshot? {
        if case .loaded(let snapshot) = self { return snapshot }
        return nil
    }

    /// From the store's availability and the freshness to attach, with
    /// the phone's check-ins and what it may record (add-training-checkins)
    /// and its plan commands (add-plan-editing).
    public static func from(
        _ availability: ProjectionAvailability,
        freshness: TrainingFreshness,
        checkIns: CheckInOverlay = .empty,
        planEdits: PendingOverlay = .empty,
        capabilities: TrainingCapabilities = .readOnly
    ) -> TrainingSource {
        switch availability {
        case .waitingForFirstSync: return .waitingForFirstSync
        case .notGenerated: return .notGenerated
        case .unreadable(let rejection): return .unreadable(rejection)
        case .loaded(let cached):
            return .loaded(TrainingSnapshot(projection: cached.projection, freshness: freshness, overlay: planEdits, checkIns: checkIns, capabilities: capabilities))
        }
    }
}

public struct TrainingEmptyState: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case fetching, notGenerated, unreadable, updateApp, noActivePlan, restDay, weekNotWritten, noPlanThisWeek
    }

    public let kind: Kind
    /// An SF Symbol name.
    public let symbol: String
    public let title: String
    public let message: String?

    public init(kind: Kind, symbol: String, title: String, message: String?) {
        self.kind = kind
        self.symbol = symbol
        self.title = title
        self.message = message
    }
}

public struct TrainingNotice: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        /// The one loud notice: this build can't read the new file.
        case updateApp
        case unreadable
        case behind
        case stale
        case newerVersion
        case dateUnknown
    }

    public let kind: Kind
    public let text: String

    public var id: Kind { kind }
    public var isLoud: Bool { kind == .updateApp }

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// The formatters for one language and one snapshot.
public struct TrainingFormatting: Sendable {
    public let language: TrainingLanguage
    public let text: TrainingText
    public let dates: DateText
    public let targets: TargetFormatter
    public let steps: StepFormatter
    public let fuel: FuelFormatter
    public let countdown: CountdownFormatter
    public let schedule: ScheduleFormatter

    public init(language: TrainingLanguage, zones: HRZones?) {
        let text = TrainingText(language)
        self.language = language
        self.text = text
        dates = DateText(language)
        targets = TargetFormatter(text: text, zones: HRZoneMapper(zones: zones))
        steps = StepFormatter(text: text)
        fuel = FuelFormatter(text: text)
        countdown = CountdownFormatter(text: text)
        schedule = ScheduleFormatter(text: text)
    }

    // MARK: Empty states

    public func emptyState(_ kind: TrainingEmptyState.Kind, target: Double? = nil) -> TrainingEmptyState {
        switch kind {
        case .fetching:
            return TrainingEmptyState(kind: kind, symbol: "arrow.triangle.2.circlepath", title: text(.stateFetchingTitle), message: text(.stateFetchingMessage))
        case .notGenerated:
            return TrainingEmptyState(kind: kind, symbol: "tray", title: text(.stateNotGeneratedTitle), message: text(.stateNotGeneratedMessage))
        case .unreadable:
            return TrainingEmptyState(kind: kind, symbol: "exclamationmark.triangle", title: text(.noticeUnreadable), message: nil)
        case .updateApp:
            return TrainingEmptyState(kind: kind, symbol: "arrow.down.app", title: text(.noticeUpdateApp), message: nil)
        case .noActivePlan:
            return TrainingEmptyState(kind: kind, symbol: "calendar.badge.exclamationmark", title: text(.stateNoActivePlanTitle), message: text(.stateNoActivePlanMessage))
        case .restDay:
            return TrainingEmptyState(kind: kind, symbol: "bed.double", title: text(.stateRestDayTitle), message: text(.stateRestDayMessage))
        case .weekNotWritten:
            let message = target.map { text.format(.weekRunTarget, NumberText.decimal($0, language)) }
            return TrainingEmptyState(kind: kind, symbol: "square.and.pencil", title: text(.stateWeekNotWrittenTitle), message: message)
        case .noPlanThisWeek:
            return TrainingEmptyState(kind: kind, symbol: "calendar", title: text(.stateNoPlanWeekTitle), message: text(.stateNoPlanWeekMessage))
        }
    }

    /// The state for a source that has no snapshot; `nil` when loaded.
    public func emptyState(for source: TrainingSource) -> TrainingEmptyState? {
        switch source {
        case .waitingForFirstSync: return emptyState(.fetching)
        case .notGenerated: return emptyState(.notGenerated)
        case .unreadable(let rejection): return emptyState(rejection.isUnsupportedMajor ? .updateApp : .unreadable)
        case .loaded: return nil
        }
    }

    // MARK: Notices

    /// The lines that go with a loaded plan (design D11), loud first.
    public func notices(_ freshness: TrainingFreshness) -> [TrainingNotice] {
        var result: [TrainingNotice] = []
        let asOfText = freshness.asOf.map(dates.short)
        switch freshness.rejection {
        case .unsupportedMajor?:
            result.append(TrainingNotice(kind: .updateApp, text: text(.noticeUpdateApp)))
        case .invalid?:
            let line = asOfText.map { text.format(.noticeUnreadableShowing, $0) } ?? text(.noticeUnreadable)
            result.append(TrainingNotice(kind: .unreadable, text: line))
        case nil:
            break
        }
        if let asOfText {
            // The date is shown when the file lags behind the day, and
            // whenever a newer file was refused (the plan is "as of").
            if freshness.isBehind || freshness.rejection?.isUnsupportedMajor == true {
                result.append(TrainingNotice(kind: .behind, text: text.format(.noticePlanAsOf, asOfText)))
            }
        } else {
            result.append(TrainingNotice(kind: .dateUnknown, text: text(.noticePlanDateUnknown)))
        }
        if let days = freshness.staleDays {
            result.append(TrainingNotice(kind: .stale, text: text.format(.noticeLastSynced, days)))
        }
        if freshness.hasNewerVersionHint {
            result.append(TrainingNotice(kind: .newerVersion, text: text(.noticeNewerVersion)))
        }
        return result
    }

    // MARK: Shared pieces

    /// A session's title: its own, else its workout's, else its type's or
    /// sport's name.
    func title(of session: Session, in snapshot: TrainingSnapshot) -> String {
        session.title.resolvedText(language)
            ?? snapshot.workout(session.workout)?.title.resolvedText(language)
            ?? text.typeName(session.type)
            ?? text.sportName(session.sport)
            ?? ""
    }

    /// "W43 · 21–27 Oct".
    func weekTitle(_ week: ISOWeek) -> String {
        text.format(.weekLabel, week.week, dates.range(week.monday, week.sunday))
    }

    /// "Unplanned · Ride · 8.4 km · 24 min".
    func unplannedLine(_ activity: ActivityRef) -> String {
        var parts = [text(.unplanned)]
        if let name = text.sportName(activity.group) ?? activity.sport { parts.append(name) }
        if let km = activity.km { parts.append(NumberText.distance(km, language)) }
        if let minutes = activity.min { parts.append(NumberText.duration(minutes: minutes)) }
        return parts.joined(separator: " · ")
    }

    /// A reserved-field text (rule notes): a string, or `{ en, cz }`.
    func freeText(_ value: JSONValue) -> String? {
        switch value {
        case .string(let string):
            return string.isEmpty ? nil : string
        case .object(let fields):
            var values: [String: String] = [:]
            for (key, field) in fields {
                if let string = field.stringValue { values[key] = string }
            }
            let resolved = LocalizedText(values: values).resolved(language)
            return resolved.isEmpty ? nil : resolved
        default:
            return nil
        }
    }
}
