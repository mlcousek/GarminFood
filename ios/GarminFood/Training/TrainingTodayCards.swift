// TrainingTodayCards.swift
//
// The four training cards that lead Today in the training experience
// (add-training-today-and-plan tasks 4.3-4.5, design D7, D9):
//
//   TrainingDayCard    the day's sessions: slot, sport, title, status, a
//                      Test/Race badge, the morning light; three option
//                      cards G/A/R (or one card for a session without
//                      options); carb-load and session fuel lines; every
//                      non-happy state; a `compact` variant (one line per
//                      session).
//   HabitsTodayCard    polish-training-today D2: the Habits card -- the
//                      ladder step, the active habits with today's ticks,
//                      the day's progress bar, the next step and what
//                      unlocks it; the header and the next step open the
//                      full ladder.
//   RaceCountdownChip  the next race of any priority with its priority
//                      letter, and the season's main race as a second line
//                      when that is a later one (polish-training-today D3).
//   WeeklyNoteCard     the week's AI note teaser, and its full-text sheet.
//
// Tapping an option pushes the session detail at that option and records
// nothing (design D8). add-training-checkins (its D6) adds, when the
// builders allow it: the morning check-in row (G/A/R buttons, letter and
// shape as well as colour, one VoiceOver element each, "Saved on phone" /
// "Sent") at the top of the training card, and an on/off toggle per habit.
// add-plan-editing: a session with a plan change of this phone still
// waiting for the vault (or not applied) shows it under its header.
// add-checkin-pain-score (its D5): once a light is chosen, the check-in row
// carries the pain step -- open while the day's pain is not asked (the
// default sites at 0, so Save alone confirms "0"), else folded to "Edit
// pain" -- and the card shows the day's recorded pain as a line.
// Both only call back; TodayView turns the callbacks into TrainingModel
// actions (local events, never a network wait). Option cards follow D9: a token tint
// only as a light wash, the letter AND a shape, larger shapes with
// Differentiate Without Color, stacked at accessibility text sizes, one
// VoiceOver element each with the option's meaning spoken.
//
// Every model and string comes from TrainingCore's `TodayTrainingBuilder`
// (tested there); these views only draw it. Depended on by: TodayView.

import SwiftUI
import TrainingCore

// MARK: - Training day

struct TrainingDayCard: View {
    let model: TodayTrainingModel
    let compact: Bool
    let onOpen: (SessionDetailTarget) -> Void
    /// add-training-checkins: a check-in button was tapped.
    var onCheckIn: (CheckInRowModel, MorningLight) -> Void = { _, _ in }
    /// add-checkin-pain-score: the pain step's Save (the whole check-in).
    var onSavePain: (MorningCheckInPayload) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let row = model.checkIn {
                CheckInRowView(row: row, onSelect: { light in onCheckIn(row, light) }, onSavePain: onSavePain)
            }
            if let state = model.emptyState {
                TrainingEmptyStateView(state: state)
            }
            ForEach(model.sessions) { session in
                if compact {
                    CompactSessionRow(session: session) {
                        onOpen(SessionDetailTarget(sessionID: session.id, option: nil))
                    }
                } else {
                    SessionBlock(session: session, onOpen: onOpen)
                }
            }
            if let carbLoad = model.carbLoadLine {
                Label {
                    Text(verbatim: carbLoad)
                } icon: {
                    Image(systemName: "fork.knife.circle")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
            }
            if let light = model.lightLine {
                Label {
                    Text(verbatim: light)
                } icon: {
                    Image(systemName: "sunrise")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let pain = model.painLine {
                Label {
                    Text(verbatim: pain)
                } icon: {
                    Image(systemName: "bandage")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            TrainingNoticeLines(notices: model.notices)
        }
        .card()
    }
}

/// One session: header, then the option cards (or its single card).
private struct SessionBlock: View {
    let session: SessionCardModel
    let onOpen: (SessionDetailTarget) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            if let pending = session.pendingBadge {
                Label {
                    Text(verbatim: pending)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.sm))
            if !session.options.isEmpty {
                layout {
                    ForEach(session.options) { option in
                        OptionCardView(option: option) { open(option) }
                    }
                }
            } else if let single = session.single {
                OptionCardView(option: single) { open(single) }
            }
            if let fuel = session.fuelLine {
                Label {
                    Text(verbatim: fuel)
                } icon: {
                    Image(systemName: "bolt.heart")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Image(systemName: session.sportSymbol)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                if let slot = session.slotText {
                    Text(verbatim: slot)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: session.title)
                    .font(.headline)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let badge = session.badgeText {
                Text(verbatim: badge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Capsule().strokeBorder(Theme.stroke))
            }
            SessionStatusChip(status: session.status, text: session.statusText)
        }
        .accessibilityElement(children: .combine)
    }

    private func open(_ option: OptionCardModel) {
        switch option.action {
        case .openDetail(let sessionID, let code):
            onOpen(SessionDetailTarget(sessionID: sessionID, option: code))
        }
    }
}

/// One G/A/R card (or a session's single card).
struct OptionCardView: View {
    let option: OptionCardModel
    let onTap: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    if option.code != nil {
                        OptionCodeBadge(code: option.code, knownCode: option.knownCode)
                    } else {
                        Image(systemName: option.sportSymbol)
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer(minLength: 0)
                    if option.highlight == .done {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                    } else if option.highlight == .morningLight {
                        Image(systemName: "sunrise.fill")
                            .foregroundStyle(OptionStyle.tint(option.knownCode))
                    }
                }
                Text(verbatim: option.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(option.targetLines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let watch = option.watchLine {
                    Label {
                        Text(verbatim: watch)
                    } icon: {
                        Image(systemName: "calendar.badge.checkmark")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { background }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityHint("Opens the session")
        .accessibilityAddTraits(option.highlight != nil ? [.isButton, .isSelected] : .isButton)
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        let tint = OptionStyle.tint(option.knownCode)
        let isHighlighted = option.highlight != nil
        return shape
            .fill(differentiateWithoutColor ? Theme.groupedBackground : tint.opacity(isHighlighted ? 0.22 : 0.10))
            .overlay(
                shape.strokeBorder(
                    isHighlighted ? tint : Theme.stroke,
                    lineWidth: isHighlighted ? 2 : 1
                )
            )
    }
}

/// The compact variant: one line per session.
private struct CompactSessionRow: View {
    let session: SessionCardModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: session.sportSymbol)
                    .foregroundStyle(Theme.accent)
                Text(verbatim: session.compactLine)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let doneOption = session.options.first(where: { $0.highlight == .done }) {
                    OptionCodeBadge(code: doneOption.code, knownCode: doneOption.knownCode)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the session")
    }
}

// MARK: - Morning check-in (add-training-checkins D6)

/// "Morning check-in" and three buttons G · A · R. The chosen one is
/// filled and marked selected; the tint is a token (success, warning,
/// danger), never the only signal: each has its letter and its shape.
struct CheckInRowView: View {
    let row: CheckInRowModel
    let onSelect: (MorningLight) -> Void
    /// add-checkin-pain-score: the pain step's Save.
    var onSavePain: (MorningCheckInPayload) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: Theme.Spacing.xs)
                if let delivery = row.deliveryLine {
                    Text(verbatim: delivery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
            layout {
                ForEach(row.buttons) { button in
                    CheckInButton(button: button) {
                        Haptics.selection()
                        onSelect(button.light)
                    }
                }
            }
            if let pain = row.pain {
                PainStepView(step: pain, onSave: onSavePain)
            }
        }
    }
}

// MARK: - Morning pain (add-checkin-pain-score D5)

/// The pain step under the lights. Every string, the default rows and the
/// payload come from TrainingCore's `PainStepModel` / `PainDraft`; this
/// view holds the owner's edits and draws them. Nothing is recorded until
/// Save.
private struct PainStepView: View {
    let step: PainStepModel
    let onSave: (MorningCheckInPayload) -> Void

    /// The owner's edits; `nil` = the model's draft untouched.
    @State private var editing: PainDraft?
    /// "Edit pain" was tapped on a recorded answer.
    @State private var isEditingRecorded = false
    /// "Not now" (or Save) folded the step for this day, on this screen.
    @State private var foldedDate: LocalDate?

    private var current: PainDraft { editing ?? step.draft }

    private var showsEditor: Bool {
        isEditingRecorded || (!step.isRecorded && foldedDate != step.date)
    }

    var body: some View {
        Group {
            if showsEditor {
                editor
            } else {
                folded
            }
        }
        .onChange(of: step.date) { _, _ in
            editing = nil
            isEditingRecorded = false
        }
    }

    /// A recorded answer: "Edit pain". Not asked but folded: the title, to
    /// open it again.
    private var folded: some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                editing = nil
                if step.isRecorded {
                    isEditingRecorded = true
                } else {
                    foldedDate = nil
                }
            } label: {
                Label {
                    Text(verbatim: step.isRecorded ? step.editTitle : step.title)
                } icon: {
                    Image(systemName: "bandage")
                }
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderless)
            Spacer(minLength: Theme.Spacing.xs)
            if let delivery = step.deliveryLine {
                Text(verbatim: delivery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(verbatim: step.title)
                } icon: {
                    Image(systemName: "bandage")
                }
                .font(.subheadline.weight(.semibold))
                Spacer(minLength: Theme.Spacing.xs)
                if let delivery = step.deliveryLine {
                    Text(verbatim: delivery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(verbatim: step.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
            if current.isEmpty {
                Text(verbatim: step.nothingHurtsText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(current.rows) { row in
                PainSiteRow(
                    row: row,
                    step: step,
                    onScore: { score in mutate { $0.setScore(score, for: row.site) } },
                    onNote: { note in mutate { $0.setNote(note, for: row.site) } },
                    onRemove: { mutate { $0.remove(row.site) } }
                )
            }
            if !current.addableSites.isEmpty {
                Menu {
                    ForEach(current.addableSites, id: \.self) { site in
                        Button {
                            mutate { $0.add(site) }
                        } label: {
                            Text(verbatim: step.siteName(site))
                        }
                    }
                } label: {
                    Label {
                        Text(verbatim: step.addSiteTitle)
                    } icon: {
                        Image(systemName: "plus.circle")
                    }
                    .font(.subheadline)
                }
            }
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    editing = nil
                    isEditingRecorded = false
                    foldedDate = step.date
                } label: {
                    Text(verbatim: step.notNowTitle)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
                Button {
                    Haptics.success()
                    onSave(step.payload(current))
                    editing = nil
                    isEditingRecorded = false
                    foldedDate = step.date
                } label: {
                    Text(verbatim: step.saveTitle)
                        .fontWeight(.semibold)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.groupedBackground)
        )
    }

    private func mutate(_ change: (inout PainDraft) -> Void) {
        var draft = current
        change(&draft)
        editing = draft
    }
}

/// One site: its name, the score as text, a 0-10 half-step slider (one
/// VoiceOver element, adjustable by half steps), remove, and a short note
/// for "other".
private struct PainSiteRow: View {
    let row: PainDraftRow
    let step: PainStepModel
    let onScore: (Double) -> Void
    let onNote: (String) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(verbatim: step.siteName(row.site))
                    .font(.subheadline)
                Spacer(minLength: Theme.Spacing.xs)
                Text(verbatim: step.scoreText(row.score))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .accessibilityHidden(true)
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: step.removeLabels[row.site] ?? step.siteName(row.site)))
            }
            Slider(
                value: Binding(get: { row.score }, set: { onScore($0) }),
                in: PainEntry.scoreRange,
                step: PainEntry.scoreStep
            )
            .tint(Theme.accent)
            .accessibilityLabel(Text(verbatim: step.siteName(row.site)))
            .accessibilityValue(Text(verbatim: step.scoreAccessibilityValue(row.score)))
            if row.site == .other {
                TextField(
                    step.notePlaceholder,
                    text: Binding(get: { row.note }, set: { onNote(String($0.prefix(PainEntry.noteMaxLength))) })
                )
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            }
        }
    }
}

private struct CheckInButton: View {
    let button: CheckInButtonModel
    let onTap: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ScaledMetric(relativeTo: .body) private var shapeSize: CGFloat = 14

    var body: some View {
        let tint = OptionStyle.tint(button.code)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: OptionStyle.symbol(button.code))
                    .font(.system(size: differentiateWithoutColor ? shapeSize * 1.4 : shapeSize))
                    .foregroundStyle(tint)
                Text(verbatim: button.letter)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.primary)
                if button.isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                shape.fill(differentiateWithoutColor ? Theme.groupedBackground : tint.opacity(button.isSelected ? 0.28 : 0.10))
            )
            .overlay(
                shape.strokeBorder(button.isSelected ? tint : Theme.stroke, lineWidth: button.isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(button.accessibilityLabel)
        .accessibilityAddTraits(button.isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Habits

struct HabitsTodayCard: View {
    let model: HabitsCardModel
    let onOpenLadder: () -> Void
    /// add-training-checkins: a habit toggle changed (id, done).
    var onTick: (String, Bool) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button(action: onOpenLadder) {
                HStack {
                    SectionHeader(
                        title: String(localized: "Habits", comment: "polish-training-today: Layout editor row and title of the Habits card on Today (the habit ladder)."),
                        trailing: model.stepText
                    )
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the habit ladder")
            if let progress = model.progressText {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView(value: Double(model.doneCount), total: Double(max(model.expectedCount, 1)))
                        .tint(model.doneCount >= model.expectedCount ? Theme.success : Theme.accent)
                        .accessibilityHidden(true)
                    Text(verbatim: progress)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(model.rows) { row in
                HabitRow(row: row) { done in onTick(row.id, done) }
            }
            if let next = model.next {
                Button(action: onOpenLadder) {
                    HabitNextStepRow(next: next)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the habit ladder")
            }
        }
        .card()
    }
}

/// The ladder's next step and what unlocks it (polish-training-today D2).
private struct HabitNextStepRow: View {
    let next: HabitNextStepModel

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            if let icon = next.icon {
                Text(verbatim: icon)
                    .font(.title3)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: next.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let unlock = next.unlockText {
                    Text(verbatim: unlock)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let earliest = next.earliestText {
                    Text(verbatim: earliest)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.groupedBackground)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: next.accessibilityLabel))
    }
}

private struct HabitRow: View {
    let row: HabitRowModel
    var onTick: (Bool) -> Void = { _ in }

    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            info
            if case .tickable(let done, let pending) = row.tick {
                HabitTickButton(label: row.label, done: done, pending: pending) {
                    Haptics.selection()
                    onTick(!done)
                }
            }
        }
    }

    private var info: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            if let icon = row.icon {
                Text(verbatim: icon)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.label)
                    .font(.subheadline.weight(.semibold))
                let detail = [row.dose, row.schedule].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: row.adherence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notToday = row.notTodayText {
                    Text(verbatim: notToday)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let doneToday = row.doneToday {
                Text(verbatim: doneToday)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            ProgressRing(
                fraction: row.fraction ?? 0,
                lineWidth: 4,
                tint: (row.fraction ?? 0) >= (row.gateFraction ?? 1) ? Theme.success : Theme.accent
            ) {
                EmptyView()
            }
            .frame(width: ringSize, height: ringSize)
            .opacity(row.fraction == nil ? 0.35 : 1)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// add-training-checkins (decision A42): a habit is on or off for the day.
/// A check shape as well as colour; a small clock while the phone's tick
/// isn't uploaded yet.
private struct HabitTickButton: View {
    let label: String
    let done: Bool
    let pending: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(done ? Theme.success : Color.secondary)
                .overlay(alignment: .bottomTrailing) {
                    if pending {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .offset(x: 4, y: 4)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(done ? Text("Done") : Text("Not done"))
        .accessibilityAddTraits(done ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Race countdown

struct RaceCountdownChip: View {
    let model: RaceChipModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: model.priority == .a || model.isHero ? "flag.checkered" : "flag")
                        .foregroundStyle(Theme.accent)
                    if let code = model.priorityCode {
                        // The letter as text, not colour (polish-training-today D3).
                        Text(verbatim: model.isHero ? "\(code) ★" : code)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, Theme.Spacing.xs + 2)
                            .padding(.vertical, 1)
                            .background(Capsule().strokeBorder(Theme.stroke))
                    }
                    Text(verbatim: model.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                    Text(verbatim: model.countdown)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if let main = model.mainRace {
                    Text(verbatim: main.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .card(padding: Theme.Spacing.sm + 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityHint("Opens the race")
    }
}

// MARK: - Weekly note

struct WeeklyNoteCard: View {
    let model: WeeklyNoteTeaserModel
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    SectionHeader(title: String(localized: "Weekly note", comment: "Today: the weekly AI note card's title."), trailing: model.weekLabel)
                }
                Text(verbatim: model.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full note")
    }
}

struct WeeklyNoteSheet: View {
    let model: WeeklyNoteTeaserModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: model.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
            }
            .navigationTitle(Text(verbatim: model.weekLabel))
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
