// CheckInModels.swift
//
// The view models of what the app records (add-training-checkins design
// D6), built from the same `TrainingSnapshot` as everything else:
//
//   - `CheckInRowModel`: the morning check-in on Today's training card --
//     three buttons G/A/R (green, amber, red) with the letter, the option's
//     meaning and one VoiceOver phrase each, the chosen light (the phone's
//     latest check-in, else the vault's `day.light`) and whether it is only
//     saved on the phone or already sent. Shown when check-ins are allowed,
//     on EVERY day (add-daily-checkin-and-pain-mode): a day of a written
//     week, a day skeleton, and a date the file doesn't cover at all (a
//     stale copy) -- with no plan too. The check is about the morning, not
//     the run.
//   - `SessionRatingModel`: the session detail's RPE (1-10) and note, the
//     phone's latest values with their delivery lines.
//   - add-checkin-pain-score: once the row has a chosen light, its `pain`
//     step (PainModels.swift) -- open while the day's pain is not asked,
//     else "Edit pain". add-daily-checkin-and-pain-mode: that only in pain
//     mode; otherwise the step is one small "Something hurts?" link.
//
// The option cards are untouched: they keep opening the detail, and a
// check-in reaches them as the morning-light highlight that already exists
// (EffectivePlan applies the phone's light to the day).
//
// Depended on by: the app's TrainingDayCard and SessionDetailView. Tests:
// CheckInBuilderTests.

import Foundation

public struct CheckInButtonModel: Equatable, Sendable, Identifiable {
    public let light: MorningLight
    public let code: OptionCode
    /// "G", "A", "R".
    public let letter: String
    /// "Green", "Amber", "Red".
    public let name: String
    /// "Planned session", "Easier", "Alternative".
    public let meaning: String
    public let isSelected: Bool
    public let accessibilityLabel: String

    public var id: String { light.rawValue }
}

public struct CheckInRowModel: Equatable, Sendable {
    public let date: LocalDate
    /// The day's traffic-light session, recorded with the check-in.
    public let sessionID: String?
    public let title: String
    public let buttons: [CheckInButtonModel]
    public let selected: MorningLight?
    /// "Saved on phone" / "Sent" for the phone's own check-in.
    public let deliveryLine: String?
    /// add-checkin-pain-score: the pain step, once a light is chosen.
    public var pain: PainStepModel? = nil
}

public struct SessionRatingModel: Equatable, Sendable {
    public let sessionID: String
    public let date: LocalDate
    public let rpe: Int?
    public let rpeDeliveryLine: String?
    public let note: String?
    public let noteDeliveryLine: String?
}

public extension TrainingFormatting {
    /// "Saved on phone" / "Sent" / "Received by the vault".
    func deliveryLine(_ delivery: EventDelivery?) -> String? {
        switch delivery {
        case .savedOnPhone?: return text(.deliverySaved)
        case .sent?: return text(.deliverySent)
        case .received?: return text(.deliveryReceived)
        case nil: return nil
        }
    }
}

public extension TodayTrainingBuilder {
    /// The check-in row for `date`; `nil` only when check-ins aren't
    /// allowed. add-daily-checkin-and-pain-mode: every day has one -- a
    /// written week's day, a day skeleton, or a date outside the file.
    func checkInRow(on date: LocalDate) -> CheckInRowModel? {
        guard let snapshot = source.snapshot, snapshot.capabilities.canCheckIn else { return nil }
        let text = format.text
        // A light the vault inferred from the executed option is not a
        // check-in: the row shows only a real check-in as chosen. A date
        // the file doesn't have shows the phone's own check-in.
        let selected: MorningLight?
        if let day = snapshot.day(date) {
            selected = day.lightSource?.known == .option ? nil : day.light?.known
        } else {
            selected = snapshot.checkIns.light(on: date)?.value
        }
        let buttons = MorningLight.checkInOrder.map { light -> CheckInButtonModel in
            let code = light.option
            let name = text.lightName(OpenEnum(light)) ?? light.rawValue
            let meaning = text.optionMeaning(OpenEnum(code)) ?? code.rawValue
            return CheckInButtonModel(
                light: light,
                code: code,
                letter: code.rawValue,
                name: name,
                meaning: meaning,
                isSelected: light == selected,
                accessibilityLabel: text.format(.a11yCheckInButton, name, meaning)
            )
        }
        let sessionID = CheckInPlanning.checkInSessionID(on: date, plan: snapshot.plan?.plan)
        var row = CheckInRowModel(
            date: date,
            sessionID: sessionID,
            title: text(.checkInTitle),
            buttons: buttons,
            selected: selected,
            deliveryLine: format.deliveryLine(snapshot.checkIns.light(on: date)?.delivery)
        )
        row.pain = painStep(on: date, light: selected, sessionID: sessionID, snapshot: snapshot)
        return row
    }
}

extension PlanBuilder {
    /// RPE and note for `session`; `nil` when rating isn't allowed.
    func ratingModel(_ session: Session, day: Day, snapshot: TrainingSnapshot) -> SessionRatingModel? {
        guard snapshot.capabilities.canRateSession else { return nil }
        // The phone's latest value, else what the vault folded
        // (`session.feedback`, e.g. from another install).
        let rpe = snapshot.checkIns.rpe(session: session.id)
        let note = snapshot.checkIns.note(session: session.id)
        return SessionRatingModel(
            sessionID: session.id,
            date: day.date,
            rpe: rpe?.value ?? session.feedback?.rpe,
            rpeDeliveryLine: format.deliveryLine(rpe?.delivery),
            note: note?.value ?? session.feedback?.note,
            noteDeliveryLine: format.deliveryLine(note?.delivery)
        )
    }
}
