// PlanNames.swift
//
// Display names for the contract's enumerations (sport, session type,
// status, slot, week status, outline kind, option meaning, morning light)
// and the SF Symbol name for each sport. An unknown value (a new session
// type such as "hike") has no name here: the screens then show the
// session's own title with a neutral type, never a raw id (spec "A new
// session type").
//
// Symbol names are plain strings so the package stays free of SwiftUI;
// the app puts them in `Image(systemName:)`.
//
// Depended on by: the builders. Tests: FormattingTests.

import Foundation

public extension TrainingText {
    func sportName(_ sport: OpenEnum<Sport>?) -> String? {
        switch sport?.known {
        case .run?: return self(.sportRun)
        case .ride?: return self(.sportRide)
        case .walk?: return self(.sportWalk)
        case .swim?: return self(.sportSwim)
        case .strength?: return self(.sportStrength)
        case .mobility?: return self(.sportMobility)
        case .winter?: return self(.sportWinter)
        case .other?: return self(.sportOther)
        case nil: return nil
        }
    }

    /// `nil` for an unknown type: the screens stay neutral.
    func typeName(_ type: OpenEnum<SessionType>?) -> String? {
        switch type?.known {
        case .easy?: return self(.typeEasy)
        case .long?: return self(.typeLong)
        case .tempo?: return self(.typeTempo)
        case .threshold?: return self(.typeThreshold)
        case .intervals?: return self(.typeIntervals)
        case .vo2max?: return self(.typeVO2max)
        case .recovery?: return self(.recovery)
        case .cross?: return self(.typeCross)
        case .strength?: return self(.sportStrength)
        case .mobility?: return self(.sportMobility)
        case .test?: return self(.badgeTest)
        case .race?: return self(.race)
        case .other?: return self(.typeOther)
        case nil: return nil
        }
    }

    func statusName(_ status: OpenEnum<SessionStatus>?) -> String? {
        switch status?.known {
        case .planned?: return self(.statusPlanned)
        case .done?: return self(.statusDone)
        case .missed?: return self(.statusMissed)
        case .skipped?: return self(.statusSkipped)
        case nil: return nil
        }
    }

    func slotName(_ slot: OpenEnum<SessionSlot>?) -> String? {
        switch slot?.known {
        case .am?: return self(.slotAM)
        case .pm?: return self(.slotPM)
        case nil: return nil
        }
    }

    func weekStatusName(_ status: OpenEnum<WeekStatus>?) -> String? {
        switch status?.known {
        case .proposed?: return self(.weekProposed)
        case .approved?: return self(.weekApproved)
        case .closed?: return self(.weekClosed)
        case nil: return nil
        }
    }

    func outlineKindName(_ kind: OpenEnum<OutlineKind>?) -> String? {
        switch kind?.known {
        case .build?: return self(.kindBuild)
        case .deload?: return self(.kindDeload)
        case .taper?: return self(.kindTaper)
        case .race?: return self(.race)
        case .transition?: return self(.kindTransition)
        case .recovery?: return self(.recovery)
        case nil: return nil
        }
    }

    /// What G, A and R mean, spoken with the letter (design D9).
    func optionMeaning(_ code: OpenEnum<OptionCode>) -> String? {
        switch code.known {
        case .g?: return self(.optionPlanned)
        case .a?: return self(.optionEasier)
        case .r?: return self(.optionAlternative)
        case nil: return nil
        }
    }

    func lightName(_ light: OpenEnum<MorningLight>?) -> String? {
        switch light?.known {
        case .greenLight?: return self(.lightGreen)
        case .amberLight?: return self(.lightAmber)
        case .redLight?: return self(.lightRed)
        case nil: return nil
        }
    }

    func habitStateName(_ state: OpenEnum<HabitState>?) -> String? {
        switch state?.known {
        case .active?: return self(.habitActive)
        case .next?: return self(.habitNext)
        case .later?: return self(.habitLater)
        case nil: return nil
        }
    }
}

public enum SportSymbol {
    /// The SF Symbol for a sport; a neutral one for unknown sports.
    public static func name(_ sport: OpenEnum<Sport>?) -> String {
        switch sport?.known {
        case .run?: return "figure.run"
        case .ride?: return "figure.outdoor.cycle"
        case .walk?: return "figure.walk"
        case .swim?: return "figure.pool.swim"
        case .strength?: return "dumbbell"
        case .mobility?: return "figure.flexibility"
        case .winter?: return "figure.skiing.crosscountry"
        case .other?, nil: return "figure.mixed.cardio"
        }
    }
}
