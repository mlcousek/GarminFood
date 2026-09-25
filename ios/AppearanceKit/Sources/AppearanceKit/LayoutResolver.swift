// LayoutResolver — turns a stored `ScreenLayout` (or none) plus a screen's
// `CardSpec` catalog into the order a screen renders, and applies the layout
// editor's changes back to storage (add-themes-and-layout design.md D8, D9).
//
// The D8 rules, each covered by LayoutResolverTests:
//   1. Walk the stored placements in order; the first occurrence of an id
//      wins, duplicates are dropped.
//   2. Ids unknown to this build stay in storage but are not rendered, so a
//      card missing from one build (or one data mode) keeps its position
//      for when it comes back.
//   3. A spec id missing from storage goes right after the nearest card that
//      precedes it in the default order and is present (first if none is),
//      with its default visibility.
//   4. An unknown or invalid variant resolves to the default variant.
//   5. Pinned cards are forced to their edge; a card that can't be hidden is
//      always visible.
//   6. With nothing stored, the result is exactly the default order.
//
// Editing works on the resolved rows the editor lists (known cards only)
// and writes back the full storage form, so an unknown card keeps its
// place next to the known card it followed.
//
// Depended on by: LayoutPreset, LayoutConfig's editing helpers (this file),
// the app's LayoutStore / LayoutEditorSheet / TodayView.

import Foundation

/// One card as a screen renders it (known to this build, rules applied).
/// Availability is the screen's business, not the resolver's.
public struct ResolvedPlacement: Identifiable, Hashable, Sendable {
    public let spec: CardSpec
    public let isVisible: Bool
    /// A valid variant of `spec`, or `nil` for a card without variants.
    public let variant: String?

    public var id: String { spec.id }

    public init(spec: CardSpec, isVisible: Bool, variant: String?) {
        self.spec = spec
        self.isVisible = isVisible
        self.variant = variant
    }
}

public enum LayoutResolver {
    /// The full storage form: rules 1, 3 and 5 applied, unknown ids kept in
    /// place, variants kept verbatim.
    public static func merged(stored: ScreenLayout?, specs: [CardSpec]) -> [CardPlacement] {
        // Rule 6.
        guard let stored else {
            return specs.map { CardPlacement(id: $0.id, isVisible: $0.defaultVisible, variant: $0.defaultVariant) }
        }

        // Rule 1.
        var seen = Set<String>()
        var list: [CardPlacement] = []
        for placement in stored.placements where seen.insert(placement.id).inserted {
            list.append(placement)
        }

        // Rule 3, in default order, so a run of new cards keeps its order.
        for (index, spec) in specs.enumerated() where !seen.contains(spec.id) {
            var insertAt = 0
            for predecessor in specs[..<index].reversed() {
                if let position = list.firstIndex(where: { $0.id == predecessor.id }) {
                    insertAt = position + 1
                    break
                }
            }
            list.insert(CardPlacement(id: spec.id, isVisible: spec.defaultVisible, variant: spec.defaultVariant), at: insertAt)
            seen.insert(spec.id)
        }

        // Rule 5.
        let specByID = specIndex(specs)
        var top: [CardPlacement] = []
        var middle: [CardPlacement] = []
        var bottom: [CardPlacement] = []
        for var placement in list {
            guard let spec = specByID[placement.id] else {
                middle.append(placement)
                continue
            }
            if !spec.hideable { placement.isVisible = true }
            switch spec.pin {
            case .top: top.append(placement)
            case .bottom: bottom.append(placement)
            case nil: middle.append(placement)
            }
        }
        return top + middle + bottom
    }

    /// What the screen renders (and the editor lists): known cards only
    /// (rule 2), with valid variants (rule 4).
    public static func resolve(stored: ScreenLayout?, specs: [CardSpec]) -> [ResolvedPlacement] {
        let specByID = specIndex(specs)
        return merged(stored: stored, specs: specs).compactMap { placement -> ResolvedPlacement? in
            guard let spec = specByID[placement.id] else { return nil }
            return ResolvedPlacement(
                spec: spec,
                isVisible: spec.hideable ? placement.isVisible : true,
                variant: spec.validVariant(placement.variant)
            )
        }
    }

    // MARK: Editing

    public enum Direction: Sendable {
        case up
        case down
    }

    /// `List.onMove` semantics: `source` and `destination` are offsets in
    /// the resolved rows (`resolve`), `destination` counted before the move.
    public static func move(
        in stored: ScreenLayout?,
        specs: [CardSpec],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> ScreenLayout {
        var order = resolve(stored: stored, specs: specs).map(\.id)
        order.moveElements(fromOffsets: source, toOffset: destination)
        return reordered(stored: stored, specs: specs, knownOrder: order)
    }

    /// Whether the VoiceOver "Move up"/"Move down" action applies: the card
    /// is movable and its neighbor that way is too (pinned cards hold their
    /// edge).
    public static func canMove(_ id: String, _ direction: Direction, in stored: ScreenLayout?, specs: [CardSpec]) -> Bool {
        neighborSwap(id, direction, in: resolve(stored: stored, specs: specs)) != nil
    }

    /// One step up or down among the resolved rows; unchanged storage form
    /// when the move isn't possible.
    public static func move(_ id: String, _ direction: Direction, in stored: ScreenLayout?, specs: [CardSpec]) -> ScreenLayout {
        let rows = resolve(stored: stored, specs: specs)
        var order = rows.map(\.id)
        if let swap = neighborSwap(id, direction, in: rows) {
            order.swapAt(swap.from, swap.to)
        }
        return reordered(stored: stored, specs: specs, knownOrder: order)
    }

    /// Shows or hides a card in place. A card that can't be hidden stays
    /// visible.
    public static func setVisible(_ visible: Bool, for id: String, in stored: ScreenLayout?, specs: [CardSpec]) -> ScreenLayout {
        let specByID = specIndex(specs)
        let placements = merged(stored: stored, specs: specs).map { placement -> CardPlacement in
            guard placement.id == id, let spec = specByID[id], spec.hideable else { return placement }
            var changed = placement
            changed.isVisible = visible
            return changed
        }
        return ScreenLayout(placements: placements)
    }

    /// Picks one of a card's variants; anything else is ignored.
    public static func setVariant(_ variant: String, for id: String, in stored: ScreenLayout?, specs: [CardSpec]) -> ScreenLayout {
        let specByID = specIndex(specs)
        let placements = merged(stored: stored, specs: specs).map { placement -> CardPlacement in
            guard placement.id == id, let spec = specByID[id], spec.variants.contains(variant) else { return placement }
            var changed = placement
            changed.variant = variant
            return changed
        }
        return ScreenLayout(placements: placements)
    }

    /// The storage form with the known cards in `knownOrder`. Each unknown
    /// card stays right after the known card it followed (or first, if it
    /// led the list); pins are re-applied.
    static func reordered(stored: ScreenLayout?, specs: [CardSpec], knownOrder: [String]) -> ScreenLayout {
        let full = merged(stored: stored, specs: specs)
        let known = Set(specs.map(\.id))
        var leading: [CardPlacement] = []
        var trailing: [String: [CardPlacement]] = [:]
        var byID: [String: CardPlacement] = [:]
        var lastKnown: String?
        for placement in full {
            if known.contains(placement.id) {
                byID[placement.id] = placement
                lastKnown = placement.id
            } else if let lastKnown {
                trailing[lastKnown, default: []].append(placement)
            } else {
                leading.append(placement)
            }
        }

        var result = leading
        var placed = Set<String>()
        let fallbackOrder = full.map(\.id).filter { known.contains($0) }
        for id in knownOrder + fallbackOrder where placed.insert(id).inserted {
            guard let placement = byID[id] else { continue }
            result.append(placement)
            result.append(contentsOf: trailing[id] ?? [])
        }
        return ScreenLayout(placements: merged(stored: ScreenLayout(placements: result), specs: specs))
    }

    /// The (from, to) indices of a one-step move, or `nil` if the card or
    /// its neighbor is pinned, or it is already at the end.
    private static func neighborSwap(_ id: String, _ direction: Direction, in rows: [ResolvedPlacement]) -> (from: Int, to: Int)? {
        guard let from = rows.firstIndex(where: { $0.id == id }), rows[from].spec.isMovable else { return nil }
        let to = direction == .up ? from - 1 : from + 1
        guard rows.indices.contains(to), rows[to].spec.isMovable else { return nil }
        return (from, to)
    }

    private static func specIndex(_ specs: [CardSpec]) -> [String: CardSpec] {
        Dictionary(specs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Config-level editing

public extension LayoutConfig {
    /// A screen's rows as rendered (and listed in the editor).
    func resolved(_ screen: LayoutScreen) -> [ResolvedPlacement] {
        LayoutResolver.resolve(stored: layout(for: screen), specs: LayoutCatalog.specs(for: screen))
    }

    /// Applies one editor change to `screen`. Any Today edit clears the
    /// applied preset, so the editor shows "Custom" (D9).
    mutating func edit(_ screen: LayoutScreen, _ change: (ScreenLayout?, [CardSpec]) -> ScreenLayout) {
        let specs = LayoutCatalog.specs(for: screen)
        setLayout(change(layout(for: screen), specs), for: screen)
        if screen == .today { appliedPreset = nil }
    }

    /// Back to the default order and variants (nothing stored).
    mutating func reset(_ screen: LayoutScreen) {
        setLayout(nil, for: screen)
        if screen == .today { appliedPreset = nil }
    }
}

// MARK: - Helpers

extension Array {
    /// `List.onMove` semantics without SwiftUI: `destination` is an offset
    /// in the array before the move. Out-of-range offsets are ignored.
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { self[$0] }
        let before = valid.filter { $0 < destination }.count
        for index in valid.sorted(by: >) {
            remove(at: index)
        }
        let target = Swift.max(0, Swift.min(destination - before, count))
        insert(contentsOf: moving, at: target)
    }
}
