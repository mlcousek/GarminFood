// LayoutStore.swift
//
// The app's owner of the screen layouts (add-themes-and-layout design.md D8,
// D9): holds the persisted `LayoutConfig` (`layout.v1`, loaded and
// quarantined by AppPreferences+Layout.swift) and applies the layout
// editor's changes. Every change writes through to UserDefaults at once --
// there is no Save button -- and, being `@Observable`, re-renders the screen
// underneath the half-height editor live.
//
// All ordering rules (unknown cards kept, new cards placed, pins, variants,
// presets) are AppearanceKit's `LayoutResolver` / `LayoutPreset` and
// unit-tested there; this class only glues them to SwiftUI and keeps the
// in-session "Undo reset" snapshot (D9).
//
// One instance per process, created in AppEnvironment (like ThemeStore).
// Read by TodayView, LayoutEditorSheet and the Appearance page.

import Foundation
import Observation
import AppearanceKit

@MainActor
@Observable
final class LayoutStore {
    private(set) var config: LayoutConfig
    /// The stored layout was unreadable and got reset (shown once on the
    /// Appearance page).
    private(set) var showsResetNotice: Bool
    /// A screen's layout from before the last Reset, kept for this session
    /// only so the editor can offer "Undo reset". Any other edit drops it.
    private(set) var resetSnapshot: ResetSnapshot?

    struct ResetSnapshot: Equatable {
        let screen: LayoutScreen
        let layout: ScreenLayout?
        let appliedPreset: String?
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        config = AppPreferences.loadLayout(from: defaults)
        showsResetNotice = defaults.bool(forKey: AppPreferences.Key.layoutResetNotice)
    }

    // MARK: Reading

    /// The screen's rows in order, as rendered and as the editor lists them.
    func resolved(_ screen: LayoutScreen) -> [ResolvedPlacement] {
        config.resolved(screen)
    }

    /// Today's preset, or `nil` for "Custom".
    var currentTodayPreset: LayoutPreset? {
        LayoutPreset.current(in: config)
    }

    func canMove(_ id: String, _ direction: LayoutResolver.Direction, on screen: LayoutScreen) -> Bool {
        LayoutResolver.canMove(id, direction, in: config.layout(for: screen), specs: LayoutCatalog.specs(for: screen))
    }

    func canUndoReset(_ screen: LayoutScreen) -> Bool {
        resetSnapshot?.screen == screen
    }

    // MARK: Editing

    /// `List.onMove` on the editor's rows.
    func move(on screen: LayoutScreen, fromOffsets source: IndexSet, toOffset destination: Int) {
        edit(screen) { stored, specs in
            LayoutResolver.move(in: stored, specs: specs, fromOffsets: source, toOffset: destination)
        }
    }

    /// The VoiceOver "Move up" / "Move down" actions.
    func move(_ id: String, _ direction: LayoutResolver.Direction, on screen: LayoutScreen) {
        edit(screen) { stored, specs in
            LayoutResolver.move(id, direction, in: stored, specs: specs)
        }
    }

    func setVisible(_ visible: Bool, for id: String, on screen: LayoutScreen) {
        edit(screen) { stored, specs in
            LayoutResolver.setVisible(visible, for: id, in: stored, specs: specs)
        }
    }

    func setVariant(_ variant: String, for id: String, on screen: LayoutScreen) {
        edit(screen) { stored, specs in
            LayoutResolver.setVariant(variant, for: id, in: stored, specs: specs)
        }
    }

    /// Overwrites Today with a preset (D9).
    func apply(_ preset: LayoutPreset) {
        resetSnapshot = nil
        write { $0.apply(preset) }
    }

    /// Back to the default order and variants; remembers the previous
    /// layout for "Undo reset".
    func reset(_ screen: LayoutScreen) {
        let previous = ResetSnapshot(
            screen: screen,
            layout: config.layout(for: screen),
            appliedPreset: screen == .today ? config.appliedPreset : nil
        )
        guard previous.layout != nil || previous.appliedPreset != nil else { return }
        write { $0.reset(screen) }
        resetSnapshot = previous
    }

    func undoReset(_ screen: LayoutScreen) {
        guard let snapshot = resetSnapshot, snapshot.screen == screen else { return }
        resetSnapshot = nil
        write { config in
            config.setLayout(snapshot.layout, for: screen)
            if screen == .today { config.appliedPreset = snapshot.appliedPreset }
        }
    }

    /// Settings -> Appearance -> "Reset all appearance": every screen back
    /// to its default (design.md Migration Plan). The start tab is part of
    /// the layout, so it resets too.
    func resetAll() {
        resetSnapshot = nil
        write { $0 = .default }
    }

    func dismissResetNotice() {
        showsResetNotice = false
        defaults.removeObject(forKey: AppPreferences.Key.layoutResetNotice)
    }

    // MARK: Private

    private func edit(_ screen: LayoutScreen, _ change: (ScreenLayout?, [CardSpec]) -> ScreenLayout) {
        resetSnapshot = nil
        write { $0.edit(screen, change) }
    }

    private func write(_ change: (inout LayoutConfig) -> Void) {
        var copy = config
        change(&copy)
        guard copy != config else { return }
        config = copy
        AppPreferences.saveLayout(copy, to: defaults)
    }
}
