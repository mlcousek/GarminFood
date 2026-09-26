// SupplementScheduleEditor.swift
//
// add-supplements task 3.2 (schedule editor, design D2/D3): when a product
// is taken -- which time slots, how many servings per slot, and on which
// days: daily, every N days, chosen weekdays, training days, a loading
// phase then maintenance (creatine: 4 servings for 7 days, then 1), or an
// on/off cycle ("8 weeks on, 4 off").
//
// `ScheduleDraft` is the form's state and converts to and from FoodLogCore's
// `SupplementSchedule`; what a schedule plans on a given day is decided
// only by `ScheduleEvaluator` (unit-tested). A cycle's anchor is the day it
// is saved, so the loading phase starts today.
//
// Depends on: FoodLogCore (SupplementSchedule, SchedulePattern, TimeSlot).
// Depended on by: SupplementProductEditorView.

import SwiftUI
import FoodLogCore

/// The editor's state for one schedule.
struct ScheduleDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case daily, everyNDays, weekdays, trainingDays, loading, onOff
        var id: String { rawValue }
    }

    var slots: [TimeSlot] = [.morning]
    var servingsPerSlot: Double = 1
    var kind: Kind = .daily
    var everyN = 2
    /// Calendar weekday numbers, 1 = Sunday.
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var loadingServings: Double = 4
    var loadingDays = 7
    var onDays = 56
    var offDays = 28
    /// Kept from an existing schedule so re-saving doesn't move it.
    var anchor: String?

    init(slots: [TimeSlot] = [.morning], servingsPerSlot: Double = 1) {
        self.slots = slots
        self.servingsPerSlot = servingsPerSlot
    }

    init(_ schedule: SupplementSchedule) {
        slots = schedule.slots
        servingsPerSlot = schedule.servingsPerSlot
        switch schedule.pattern {
        case .daily, .unknown:
            kind = .daily
        case .everyNDays(let n, let anchor):
            kind = .everyNDays
            everyN = max(2, n)
            self.anchor = anchor
        case .weekdays(let days):
            kind = .weekdays
            weekdays = days
        case .trainingDays:
            kind = .trainingDays
        case .cycle(let phases, let anchor, let repeats):
            self.anchor = anchor
            if repeats, phases.count == 2, phases[1].servingsPerSlot == 0 {
                kind = .onOff
                servingsPerSlot = phases[0].servingsPerSlot
                onDays = phases[0].days
                offDays = phases[1].days
            } else if phases.count == 2 {
                kind = .loading
                loadingServings = phases[0].servingsPerSlot
                loadingDays = phases[0].days
                servingsPerSlot = phases[1].servingsPerSlot
            } else {
                // A shape this editor doesn't offer: show it as daily at
                // the last phase's dose; saving is then a deliberate change.
                kind = .daily
                servingsPerSlot = phases.last?.servingsPerSlot ?? 1
            }
        }
    }

    /// The schedule to save; new cycles and every-N-days start on `anchor`
    /// (today) unless the draft kept one.
    func schedule(anchor today: String) -> SupplementSchedule {
        let start = anchor ?? today
        let pattern: SchedulePattern
        switch kind {
        case .daily:
            pattern = .daily
        case .everyNDays:
            pattern = .everyNDays(n: max(2, everyN), anchor: start)
        case .weekdays:
            pattern = .weekdays(weekdays.isEmpty ? Set(1...7) : weekdays)
        case .trainingDays:
            pattern = .trainingDays
        case .loading:
            pattern = .cycle(
                phases: [CyclePhase(servingsPerSlot: loadingServings, days: max(1, loadingDays)),
                         CyclePhase(servingsPerSlot: servingsPerSlot, days: 1)],
                anchor: start,
                repeats: false
            )
        case .onOff:
            pattern = .cycle(
                phases: [CyclePhase(servingsPerSlot: servingsPerSlot, days: max(1, onDays)),
                         CyclePhase(servingsPerSlot: 0, days: max(1, offDays))],
                anchor: start,
                repeats: true
            )
        }
        return SupplementSchedule(slots: slots.sorted(), servingsPerSlot: servingsPerSlot, pattern: pattern)
    }
}

@MainActor
struct SupplementScheduleEditor: View {
    @Binding var draft: ScheduleDraft
    /// Garmin mode has activities; standalone uses only race-tagged days.
    let hasTrainingData: Bool

    var body: some View {
        Section {
            ForEach(SupplementSlotTimes.builtInSlots, id: \.key) { slot in
                Toggle(isOn: Binding(
                    get: { draft.slots.contains(slot) },
                    set: { isOn in
                        if isOn { draft.slots.append(slot) } else { draft.slots.removeAll { $0 == slot } }
                    }
                )) {
                    Label(slot.displayName, systemImage: slot.symbolName)
                }
            }
            if draft.kind != .loading {
                servingsStepper(String(localized: "Servings each time"), value: $draft.servingsPerSlot)
            }
        } header: {
            Text("When")
        }

        Section {
            Picker("Days", selection: $draft.kind) {
                ForEach(ScheduleDraft.Kind.allCases) { kind in
                    Text(Self.title(kind)).tag(kind)
                }
            }
            switch draft.kind {
            case .daily, .trainingDays:
                EmptyView()
            case .everyNDays:
                Stepper(value: $draft.everyN, in: 2...30) {
                    Text("Every \(draft.everyN) days", comment: "Supplement schedule: taken every N days. Plural.")
                }
            case .weekdays:
                WeekdayPicker(selection: $draft.weekdays)
            case .loading:
                servingsStepper(String(localized: "Loading servings"), value: $draft.loadingServings)
                Stepper(value: $draft.loadingDays, in: 1...60) {
                    Text("Loading for \(draft.loadingDays) days", comment: "Supplement schedule: length of the loading phase. Plural.")
                }
                servingsStepper(String(localized: "Then, servings each time"), value: $draft.servingsPerSlot)
            case .onOff:
                Stepper(value: $draft.onDays, in: 1...365) {
                    Text("\(draft.onDays) days on", comment: "Supplement schedule: on-phase length of an on/off cycle. Plural.")
                }
                Stepper(value: $draft.offDays, in: 1...365) {
                    Text("\(draft.offDays) days off", comment: "Supplement schedule: off-phase length of an on/off cycle. Plural.")
                }
            }
        } footer: {
            if draft.kind == .trainingDays {
                Text(hasTrainingData
                     ? String(localized: "Days with an activity in Garmin, or a day note tagged race.", comment: "Supplement schedule footer: what counts as a training day in Garmin mode.")
                     : String(localized: "Without Garmin, a training day is a day note tagged race.", comment: "Supplement schedule footer: what counts as a training day in standalone mode."))
            } else if draft.kind == .loading || draft.kind == .onOff || draft.kind == .everyNDays {
                Text("Counts from the day you save it. Changes apply from today; past days keep their plan.", comment: "Supplement schedule footer for patterns anchored to a start day.")
            }
        }
    }

    private func servingsStepper(_ title: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 0.5...20, step: 0.5) {
            HStack {
                Text(verbatim: title)
                Spacer()
                Text(verbatim: SupplementFormat.servings(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func title(_ kind: ScheduleDraft.Kind) -> String {
        switch kind {
        case .daily: return String(localized: "Every day")
        case .everyNDays: return String(localized: "Every few days")
        case .weekdays: return String(localized: "On chosen weekdays")
        case .trainingDays: return String(localized: "On training days")
        case .loading: return String(localized: "Loading, then maintenance")
        case .onOff: return String(localized: "On/off cycle")
        }
    }
}

/// Seven toggle chips, in the locale's week order.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack {
            ForEach(order, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    if isOn { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(verbatim: symbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? Theme.accent : Color.clear, in: Circle())
                        .foregroundStyle(isOn ? Theme.onAccent : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: calendar.standaloneWeekdaySymbols[weekday - 1]))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
