// LayoutEditorSheet.swift
//
// "Edit layout" (add-themes-and-layout design.md D9, screen-layout spec
// "Layout editor with live preview"): one editor for any `LayoutScreen`,
// opened from Today's toolbar menu and from Settings -> Appearance -> Layout.
//
// - A `List` in permanent edit mode with `onMove`: native drag handles and
//   haptics. Pinned rows (`CardSpec.pin`) have no handle and show a lock.
// - Each row: an eye button to show/hide, the card's icon and title, a
//   caption when the card can't show right now (greyed out when it is
//   unavailable, e.g. fasting off -- its visibility setting is kept), and a
//   variant menu for cards that have variants.
// - VoiceOver: explicit "Move up" / "Move down" actions on every movable
//   row (pinned neighbors stop them), so reordering never needs a drag.
// - Presets (Today), Reset with a confirmation, "Undo reset" for the rest of
//   the session, and Done. There's no Save: every change writes through
//   `LayoutStore` at once.
// - Half height with background interaction, so the real screen underneath
//   stays visible, scrollable and updates live -- the preview is the screen
//   itself, no mock renderer. Changes animate unless Reduce Motion is on.
//
// Thin by design: every rule (moves, pins, unknown cards, presets) is
// AppearanceKit's LayoutResolver / LayoutPreset, tested there.
//
// Depends on LayoutStore (via AppEnvironment), LayoutCardInfo (titles,
// availability). Presented by TodayView and AppearanceSettingsView.

import SwiftUI
import AppearanceKit

@MainActor
struct LayoutEditorSheet: View {
    let screen: LayoutScreen
    /// Whether each card (by id) has something to show right now; supplied
    /// by the presenter, which knows the screen's state.
    let availability: (String) -> CardAvailability

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmsReset = false

    private var store: LayoutStore { environment.layoutStore }

    var body: some View {
        NavigationStack {
            List {
                if screen == .today {
                    Section {
                        LabeledContent("Layout", value: presetName)
                    }
                }

                Section {
                    ForEach(store.resolved(screen)) { row in
                        LayoutEditorRow(
                            row: row,
                            title: LayoutCardInfo.title(row.id, on: screen),
                            systemImage: LayoutCardInfo.systemImage(row.id, on: screen),
                            availability: availability(row.id),
                            canMoveUp: store.canMove(row.id, .up, on: screen),
                            canMoveDown: store.canMove(row.id, .down, on: screen),
                            onVisibility: { visible in
                                animate { store.setVisible(visible, for: row.id, on: screen) }
                            },
                            onVariant: { variant in
                                animate { store.setVariant(variant, for: row.id, on: screen) }
                            },
                            onMove: { direction in
                                animate { store.move(row.id, direction, on: screen) }
                            }
                        )
                        .moveDisabled(!row.spec.isMovable)
                    }
                    .onMove { source, destination in
                        animate { store.move(on: screen, fromOffsets: source, toOffset: destination) }
                    }
                } footer: {
                    Text("Drag to reorder. Changes show right away.")
                }

                Section {
                    if store.canUndoReset(screen) {
                        Button("Undo reset") {
                            animate { store.undoReset(screen) }
                        }
                    }
                    Button("Reset to default", role: .destructive) {
                        confirmsReset = true
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if screen == .today {
                    ToolbarItem(placement: .topBarLeading) {
                        presetsMenu
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset this layout?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    animate { store.reset(screen) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Cards go back to their default order and style.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationContentInteraction(.scrolls)
    }

    // MARK: Presets (Today)

    private var presetName: String {
        store.currentTodayPreset?.displayName ?? String(localized: "Custom")
    }

    private var presetsMenu: some View {
        Menu("Presets") {
            ForEach(LayoutPreset.allCases, id: \.self) { preset in
                Button {
                    animate { store.apply(preset) }
                } label: {
                    if store.currentTodayPreset == preset {
                        Label(preset.displayName, systemImage: "checkmark")
                    } else {
                        Text(preset.displayName)
                    }
                }
            }
        }
    }

    /// Animates the change (the screen underneath moves its cards too),
    /// or applies it instantly under Reduce Motion.
    private func animate(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.default) { change() }
        }
    }
}

/// One card in the editor.
private struct LayoutEditorRow: View {
    let row: ResolvedPlacement
    let title: String
    let systemImage: String
    let availability: CardAvailability
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onVisibility: (Bool) -> Void
    let onVariant: (String) -> Void
    let onMove: (LayoutResolver.Direction) -> Void

    @ScaledMetric(relativeTo: .body) private var controlWidth: CGFloat = 28

    private var isDimmed: Bool {
        availability.isUnavailable || !row.isVisible
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            visibilityControl
                .frame(width: controlWidth)

            Image(systemName: systemImage)
                .foregroundStyle(isDimmed ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Theme.accent))
                .frame(width: controlWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                if let caption = availability.caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(row.isVisible ? Text("Shown") : Text("Hidden"))
            .accessibilityActions {
                if canMoveUp {
                    Button("Move up") { onMove(.up) }
                }
                if canMoveDown {
                    Button("Move down") { onMove(.down) }
                }
            }

            Spacer(minLength: Theme.Spacing.xs)

            if !row.spec.variants.isEmpty {
                variantMenu
            }

            if !row.spec.isMovable {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Fixed position")
            }
        }
    }

    @ViewBuilder
    private var visibilityControl: some View {
        if row.spec.hideable {
            Button {
                onVisibility(!row.isVisible)
            } label: {
                Image(systemName: row.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(row.isVisible ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.secondary))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(row.isVisible
                ? String(localized: "Hide \(title)", comment: "Layout editor: VoiceOver label of the eye button on a shown card. %@ is the card's name.")
                : String(localized: "Show \(title)", comment: "Layout editor: VoiceOver label of the eye button on a hidden card. %@ is the card's name."))
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }

    private var variantMenu: some View {
        Menu {
            Picker("Style", selection: Binding(
                get: { row.variant ?? "" },
                set: { onVariant($0) }
            )) {
                ForEach(row.spec.variants, id: \.self) { variant in
                    Text(LayoutCardInfo.variantName(variant)).tag(variant)
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(LayoutCardInfo.variantName(row.variant ?? ""))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(String(localized: "Style of \(title)", comment: "Layout editor: VoiceOver label of a card's variant menu. %@ is the card's name."))
        .accessibilityValue(LayoutCardInfo.variantName(row.variant ?? ""))
    }
}
