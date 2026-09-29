// PlanTabView.swift
//
// The Plan tab, shown only in the training experience (rebrand-to-jirkas-arc
// D6; add-training-today-and-plan task 5.1, design D10, D11): a Week ·
// Month segmented control (remembered per install; opens on Week, owner
// decision 0.2 defaulted), the week agenda or the month calendar, the
// session detail pushed from either, the habit ladder from the toolbar,
// and every non-happy state (fetching, not published, no active plan,
// unreadable, update the app) through TrainingCore's builders.
//
// Read-only: nothing on this tab moves, swaps, skips, checks in or rates a
// session. It consumes the router's pending plan date: a
// `garminfood://plan?date=YYYY-MM-DD` link opens the week containing it,
// the race chip on Today opens the month at the race day.
//
// add-season-phase-race-screens (design D2): a third segment, Season --
// the season timeline, whose phases and races push the Phase and Race
// screens -- and Today's race chip opens that race's screen here
// (`AppRouter.pendingRaceID`).
//
// Depended on by: ContentView (the Plan tab's root).

import SwiftUI
import TrainingCore

enum PlanMode: String, CaseIterable, Hashable {
    case week
    case month
    /// add-season-phase-race-screens: the season timeline.
    case season
}

/// A race whose screen is pushed (Today's race chip).
struct PlanRaceTarget: Identifiable, Hashable {
    let raceID: String
    var id: String { raceID }
}

/// A month the calendar shows.
struct PlanMonth: Hashable {
    let year: Int
    let month: Int
}

/// A day whose sheet is open.
struct PlanDaySheet: Identifiable, Hashable {
    let date: LocalDate
    var id: LocalDate { date }
}

@MainActor
struct PlanTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("plan.mode.v1") private var modeRaw = PlanMode.week.rawValue
    @State private var week: ISOWeek?
    @State private var month: PlanMonth?
    @State private var sessionTarget: SessionDetailTarget?
    @State private var daySheet: PlanDaySheet?
    @State private var isShowingLadder = false
    @State private var raceTarget: PlanRaceTarget?

    private var mode: Binding<PlanMode> {
        Binding(
            get: { PlanMode(rawValue: modeRaw) ?? .week },
            set: { modeRaw = $0.rawValue }
        )
    }

    var body: some View {
        let training = environment.training
        let builder = training.planBuilder()
        let today = training.today()

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                Picker("View", selection: mode) {
                    Text("Week").tag(PlanMode.week)
                    Text("Month").tag(PlanMode.month)
                    Text("Season").tag(PlanMode.season)
                }
                .pickerStyle(.segmented)

                switch mode.wrappedValue {
                case .week:
                    WeekAgendaView(
                        model: builder.week(week ?? ISOWeek(containing: today)),
                        onPage: { week = $0 },
                        onOpen: { sessionTarget = $0 }
                    )
                case .month:
                    let shown = month ?? PlanMonth(year: today.year, month: today.month)
                    MonthCalendarView(
                        model: builder.month(year: shown.year, month: shown.month),
                        onPage: { month = $0 },
                        onSelectDay: { daySheet = PlanDaySheet(date: $0) }
                    )
                case .season:
                    SeasonTimelineView(model: builder.seasonTimeline())
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background { GradientHeaderBackground() }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingLadder = true
                } label: {
                    Label("Habit ladder", systemImage: "stairs")
                }
            }
        }
        .navigationDestination(item: $sessionTarget) { target in
            SessionDetailView(target: target)
        }
        .navigationDestination(isPresented: $isShowingLadder) {
            HabitLadderView()
        }
        .navigationDestination(item: $raceTarget) { target in
            RaceDetailView(raceID: target.raceID)
        }
        .sheet(item: $daySheet) { sheet in
            PlanDaySheetView(row: builder.dayRow(sheet.date)) { target in
                daySheet = nil
                sessionTarget = target
            }
        }
        .refreshable {
            await environment.refreshOnForeground(userInitiated: true)
        }
        .task {
            if !training.hasLoaded { await training.reload() }
        }
        .onChange(of: environment.router.pendingPlanDate, initial: true) { _, pending in
            guard let pending else { return }
            consume(pending, showsMonth: environment.router.pendingPlanShowsMonth)
            environment.router.pendingPlanDate = nil
            environment.router.pendingPlanShowsMonth = false
        }
        .onChange(of: environment.router.pendingRaceID, initial: true) { _, pending in
            guard let pending else { return }
            modeRaw = PlanMode.season.rawValue
            raceTarget = PlanRaceTarget(raceID: pending)
            environment.router.pendingRaceID = nil
        }
    }

    /// A link or the race chip: the week (or month) containing the date.
    private func consume(_ components: DateComponents, showsMonth: Bool) {
        guard let year = components.year, let monthNumber = components.month, let day = components.day,
              let date = LocalDate(year: year, month: monthNumber, day: day)
        else { return }
        if showsMonth {
            month = PlanMonth(year: date.year, month: date.month)
            modeRaw = PlanMode.month.rawValue
        } else {
            week = ISOWeek(containing: date)
            modeRaw = PlanMode.week.rawValue
        }
    }
}

/// A day's sessions and unplanned activities (the month's day sheet).
struct PlanDaySheetView: View {
    let row: DayRowModel
    let onOpen: (SessionDetailTarget) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DayRowView(row: row, onOpen: onOpen)
                    .card()
                    .padding(Theme.Spacing.md)
            }
            .navigationTitle(Text(verbatim: row.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
