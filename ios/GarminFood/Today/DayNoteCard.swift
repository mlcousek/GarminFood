// DayNoteCard.swift
//
// The "Note" card at the bottom of the Today screen (add-day-notes): free
// text plus quick tags (🏃 Race, 🎉 Celebration, 🤒 Sick, ...) for the day
// currently selected with the day switcher -- so a past day can be
// annotated after the fact ("why did Saturday look like that? -- race").
// Tagged days then get a marker on the Trends charts
// (`Trends/DayNoteChartMarkers.swift`).
//
// WHY it saves as you type instead of having a Save button: the owner asked
// for zero ceremony, and a forgotten Save would silently lose the note.
// Edits are debounced (~600 ms) into `DayNoteStore` (FoodLogCore,
// local-only -- Garmin has no notes route), and anything still pending is
// flushed when the card disappears, when the app leaves the foreground, and
// before switching to another day. Writes are chained so they land in the
// order they were made, and switching days waits for the previous day's
// write before reading the new one -- otherwise flipping away and straight
// back could show the note as it was before the last keystrokes.
//
// `DayNoteStore.save` is idempotent (saving unchanged content is a no-op)
// and deletes an empty note, so flushing is always safe and "clear the text,
// untick every tag" leaves nothing stored (spec scenario "Clearing a note").
//
// Depends on: `DayNoteStore`/`DayNoteTag` (FoodLogCore), `DiagnosticsLog`
// (GarminKit) for a failed write, `Haptics`, `Theme`/`SectionHeader`/
// `.card()` from the design system. Placed by `TodayView`, which passes
// `environment.dayLog.dateString` -- the same `NutritionDate` key the rest
// of the app uses for the selected day.

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct DayNoteCard: View {
    /// `yyyy-MM-dd` of the day shown (`DayLogLoader.dateString`).
    let day: String
    let store: DayNoteStore

    @Environment(\.scenePhase) private var scenePhase

    @State private var text = ""
    @State private var tags: Set<DayNoteTag> = []
    /// Which day `text`/`tags` currently hold. `nil` while a day is being
    /// loaded -- editing is disabled then, so a keystroke can never be
    /// attributed to the wrong day.
    @State private var loadedDay: String?
    /// The latest unsaved edit, captured with ITS day so a flush after the
    /// day has changed still writes to the right record.
    @State private var pending: PendingNote?
    @State private var debounce: Task<Void, Never>?
    @State private var lastWrite: Task<Void, Never>?
    @State private var status: SaveStatus = .idle
    @FocusState private var isEditing: Bool

    private static let debounceNanoseconds: UInt64 = 600_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Note", comment: "Section header of Today's day note card."), trailing: status.label)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                TextField("What made this day different?", text: textBinding, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($isEditing)
                    .accessibilityLabel("Note for this day")

                DayNoteTagFlowLayout(spacing: Theme.Spacing.sm) {
                    ForEach(DayNoteTag.allCases) { tag in
                        DayNoteTagChip(tag: tag, isSelected: tags.contains(tag)) {
                            toggle(tag)
                        }
                    }
                }
            }
            .card()
            .disabled(loadedDay != day)
        }
        .task(id: day) { await load(day) }
        .onDisappear { flush() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flush() }
        }
        .toolbar {
            // Return inserts a newline in a multi-line field, so this is
            // the way to put the keyboard away (same pattern as
            // `LogEntryConfirmView`).
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }
            }
        }
    }

    // MARK: - Editing

    private var textBinding: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                guard newValue != text else { return }
                text = newValue
                scheduleSave()
            }
        )
    }

    /// A tag tap is a complete edit on its own, so it's written straight
    /// away rather than waiting out the typing debounce.
    private func toggle(_ tag: DayNoteTag) {
        if tags.contains(tag) {
            tags.remove(tag)
        } else {
            tags.insert(tag)
        }
        Haptics.selection()
        scheduleSave()
        flush()
    }

    private func scheduleSave() {
        guard let loadedDay else { return }
        pending = PendingNote(day: loadedDay, text: text, tags: Array(tags))
        status = .idle
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Writes the pending edit, if any, and returns the write so a caller
    /// can wait for it. Chained after the previous write so two writes can
    /// never land out of order.
    @discardableResult
    private func flush() -> Task<Void, Never>? {
        debounce?.cancel()
        debounce = nil
        guard let note = pending else { return lastWrite }
        pending = nil

        let store = store
        let previous = lastWrite
        let write = Task {
            await previous?.value
            do {
                try await store.save(day: note.day, text: note.text, tags: note.tags)
                if pending == nil { status = .saved }
            } catch {
                DiagnosticsLog.log(.error, category: "DayNoteCard", "couldn't save the note for \(note.day): \(error)")
                // Keep it so the next flush (disappear/background/next
                // edit) tries again, unless a newer edit already replaced it.
                if pending == nil { pending = note }
                status = .failed
            }
        }
        lastWrite = write
        return write
    }

    // MARK: - Loading

    private func load(_ day: String) async {
        // Anything pending belongs to the previous day: write it, and wait
        // for it, before reading -- see the header.
        let write = flush()
        loadedDay = nil
        await write?.value

        let note = await store.note(for: day)
        guard !Task.isCancelled else { return }
        text = note?.text ?? ""
        tags = Set(note?.tags ?? [])
        status = .idle
        loadedDay = day
    }
}

private struct PendingNote {
    let day: String
    let text: String
    let tags: [DayNoteTag]
}

private enum SaveStatus {
    case idle
    case saved
    case failed

    var label: String? {
        switch self {
        case .idle: return nil
        case .saved: return String(localized: "Saved", comment: "Day note card status after the note was saved.")
        case .failed: return String(localized: "Couldn't save", comment: "Day note card status when saving the note failed.")
        }
    }
}

// MARK: - Tag chip

/// One toggleable tag. VoiceOver reads it as "Race, selected, button" (or
/// "not selected") -- the emoji is decoration, so it's replaced by the
/// explicit label rather than read out as "person running".
struct DayNoteTagChip: View {
    let tag: DayNoteTag
    let isSelected: Bool
    var action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let action {
            Button(action: action) { chip }
                .buttonStyle(.plain)
                .accessibilityLabel(tag.title)
                .accessibilityValue(isSelected ? "selected" : "not selected")
                .accessibilityHint("Double-tap to toggle this tag")
        } else {
            chip
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tag.title)
        }
    }

    private var chip: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(tag.emoji)
            Text(tag.title)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, Theme.Spacing.sm + 4)
        .padding(.vertical, Theme.Spacing.xs + 3)
        .background(isSelected ? Theme.accent.opacity(0.2) : Color(.tertiarySystemFill), in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 1.5))
        .contentShape(Capsule())
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
    }
}

// MARK: - Flow layout

/// Lays chips out left to right, wrapping onto new rows -- all seven tags
/// stay visible without a horizontal scroll, at any Dynamic Type size.
struct DayNoteTagFlowLayout: Layout {
    var spacing: CGFloat = Theme.Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(maxWidth: bounds.width, subviews: subviews)
        for index in subviews.indices {
            let frame = arrangement.frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        let widthProposal: CGFloat? = maxWidth.isFinite ? maxWidth : nil

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: widthProposal, height: nil))
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            widest = max(widest, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, CGSize(width: widest, height: y + rowHeight))
    }
}

#Preview("DayNoteCard") {
    ScrollView {
        DayNoteCard(day: "2026-09-19", store: DayNoteStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-day-notes.json")))
            .padding()
    }
}
