// PainModeState.swift
//
// add-daily-checkin-and-pain-mode (design D3): whether the pain features
// show. The owner's rule (30 Sep): "pain features are annoying when I'm
// healthy -- show them when pain started and until it's gone."
//
// Two sources, and nothing persisted for it:
//   - the vault: `athlete.painMode.active` in the projection. The vault
//     runs the rules (on at a score above 0 or an amber/red check-in light,
//     off after a run of scored mornings at 0); the phone only reads the
//     answer;
//   - the phone, optimistically: this phone recorded a pain answer with a
//     score above 0 that the vault has not read yet (not acknowledged, and
//     not the answer the file itself shows for that day). It bridges the
//     hours until the next projection; once the vault has read the answer,
//     the vault's `painMode` alone decides -- so the mode can never stay on
//     against the vault's word, and never nags after the pain is gone.
//
// An amber or red light alone does NOT turn the phone's half on: whether a
// light starts pain mode is the vault's configuration, not the app's.
//
// While active: the pain step follows the light in the morning check-in,
// Today shows the pain line and Plan the pain tags, the morning reminder
// asks for the score. While inactive: the check-in is the light only, with
// a small "Something hurts?" link that opens the pain step.
//
// Depended on by: TrainingSnapshot (`painMode`), PainModels, CheckInModels,
// TodayTrainingModel, PlanModels, TrainingReminderPlanner. Tests:
// DailyCheckInTests.

import Foundation

public struct PainModeState: Equatable, Sendable {
    public enum Origin: String, Equatable, Sendable {
        /// The projection says so.
        case vault
        /// This phone's own pain answer, not read by the vault yet.
        case phone
    }

    /// Who turned it on; `nil` when pain mode is off.
    public let origin: Origin?
    /// What the vault said (inactive when the file has no `painMode`).
    public let vault: PainMode

    public var isActive: Bool { origin != nil }

    public static let inactive = PainModeState(origin: nil, vault: .inactive)

    public init(origin: Origin?, vault: PainMode = .inactive) {
        self.origin = origin
        self.vault = vault
    }

    /// `vault` is `athlete.painMode`; `vaultPains` the file's own
    /// `day.pains` by date (before the phone's answers are laid over).
    public static func resolve(vault: PainMode?, checkIns: CheckInOverlay, vaultPains: [LocalDate: [PainEntry]]) -> PainModeState {
        let said = vault ?? .inactive
        if said.active {
            return PainModeState(origin: .vault, vault: said)
        }
        if !checkIns.unconfirmedPainDates(vaultPains: vaultPains).isEmpty {
            return PainModeState(origin: .phone, vault: said)
        }
        return PainModeState(origin: nil, vault: said)
    }
}
