// MorningCheckInIntents.swift
//
// The lock-screen check-in Controls' action (add-training-checkins design
// D7; the architecture note's section 6.3: "three static Controls ... Each
// opens the app and commits checkin.morning").
//
// Same shape as the quick-pick Controls (QuickPickLoggingIntents.swift;
// read its header for the full reasoning): there is no App Group on this
// free account, so the widget extension can't reach the app's files, and
// the intent sets `openAppWhenRun = true` so `perform()` runs in the APP's
// process. `authenticationPolicy = .alwaysAllowed` for the same one-tap
// reason, with the same unconfirmed caveat (whether iOS still asks for Face
// ID when the app must come forward; tasks 6.2 checks it on the device).
//
// DUAL TARGET MEMBERSHIP: this file is in Shared/, compiled into the app
// AND the widget extension (the extension needs the intent type to declare
// the Controls). The widget never links VaultKit or TrainingCore, so this
// file can't call them. Instead the app installs
// `MorningCheckInControlAction.handler` in `GarminFoodApp.init()` -- before
// any scene, so a cold launch by the Control finds it -- pointing at
// `TrainingEventsService.handleControlCheckIn`, which records the event
// with the app's own files. In the widget process the handler is never set
// and `perform()` never runs there anyway.
//
// A failure throws a localized error, so the Control shows it instead of a
// success it hasn't earned (the connection is off, never tested, or the
// app couldn't record). Strings live in BOTH catalogs (the checker's rule
// for Shared/).

import AppIntents

/// The light as the Controls and Shortcuts name it; raw values are the
/// event contract's words (TrainingCore's `MorningLight`).
enum CheckInLightOption: String, AppEnum {
    // Case names avoid colour words (the design-token lint forbids `.red`
    // and friends); the raw values are the contract's words.
    case greenLight = "green"
    case amberLight = "amber"
    case redLight = "red"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Traffic Light"
    static var caseDisplayRepresentations: [CheckInLightOption: DisplayRepresentation] = [
        .greenLight: DisplayRepresentation(title: "Green"),
        .amberLight: DisplayRepresentation(title: "Amber"),
        .redLight: DisplayRepresentation(title: "Red")
    ]
}

enum MorningCheckInControlAction {
    /// Installed by the app (see this file's header). Takes the raw light
    /// ("green", "amber", "red"); throws `ActionError` or the app's error.
    static var handler: (@MainActor (String) async throws -> Void)?

    enum ActionError: Error, CustomLocalizedStringResourceConvertible {
        case vaultOff
        case notTested
        case notAvailable

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .vaultOff:
                return "Nothing recorded: turn on the vault connection in Jirka's Arc first."
            case .notTested:
                return "Nothing recorded: test the vault connection in Jirka's Arc first."
            case .notAvailable:
                return "Nothing recorded: open Jirka's Arc once, then try again."
            }
        }
    }
}

struct MorningCheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Morning Check-in"
    static var description = IntentDescription("Records this morning's check-in in Jirka's Arc.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Traffic Light")
    var light: CheckInLightOption

    init() {
        self.light = .greenLight
    }

    init(light: CheckInLightOption) {
        self.light = light
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let handler = MorningCheckInControlAction.handler else {
            throw MorningCheckInControlAction.ActionError.notAvailable
        }
        try await handler(light.rawValue)
        return .result()
    }
}
