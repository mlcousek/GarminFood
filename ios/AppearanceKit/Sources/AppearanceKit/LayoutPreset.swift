// LayoutPreset — the Today presets Full, Minimal and Athlete
// (add-themes-and-layout design.md D9, screen-layout spec "Presets and
// reset"), as pure data so each one is a unit test rather than an on-device
// guess.
//
// Applying a preset overwrites Today's placements and records it in
// `LayoutConfig.appliedPreset`; any later Today edit clears that
// (`LayoutConfig.edit`), and the editor then shows "Custom". Reset is not a
// preset: it removes the stored Today layout, which resolves to the same
// order as Full.
//
// Depended on by: the app's LayoutStore and LayoutEditorSheet (names are
// localized there, in LayoutCardInfo.swift).

import Foundation

public enum LayoutPreset: String, CaseIterable, Sendable {
    /// Today's default: everything shown, ring summary, meals expanded.
    case full
    /// Compact summary, collapsed meals and Log again; everything else
    /// hidden except the pinned cards.
    case minimal
    /// Ring summary, the streak strip, Weight & Water moved up under it,
    /// then everything else.
    case athlete

    /// Today's placements for this preset.
    public var todayLayout: ScreenLayout {
        switch self {
        case .full:
            return ScreenLayout(placements: LayoutResolver.merged(stored: nil, specs: LayoutCatalog.today))
        case .minimal:
            let shown: Set<TodayCardID> = [.daySwitcher, .summary, .meals, .logAgain, .signature]
            return ScreenLayout(placements: TodayCardID.allCases.map { (id: TodayCardID) -> CardPlacement in
                let variant: String?
                switch id {
                case .summary: variant = SummaryVariant.compact.rawValue
                case .meals: variant = MealsVariant.collapsed.rawValue
                case .weightWater: variant = WeightWaterVariant.both.rawValue
                default: variant = nil
                }
                return CardPlacement(id: id.rawValue, isVisible: shown.contains(id), variant: variant)
            })
        case .athlete:
            let order: [TodayCardID] = [
                .daySwitcher, .summary, .progressStrip, .weightWater, .meals,
                .fasting, .logAgain, .logMeal, .banners, .dayNote, .signature,
            ]
            return ScreenLayout(placements: order.map { (id: TodayCardID) -> CardPlacement in
                let variant: String?
                switch id {
                case .summary: variant = SummaryVariant.ring.rawValue
                case .meals: variant = MealsVariant.expanded.rawValue
                case .weightWater: variant = WeightWaterVariant.both.rawValue
                default: variant = nil
                }
                return CardPlacement(id: id.rawValue, isVisible: true, variant: variant)
            })
        }
    }

    /// The preset the Today layout currently is: the applied one, Full when
    /// nothing is stored, else `nil` ("Custom").
    public static func current(in config: LayoutConfig) -> LayoutPreset? {
        if let raw = config.appliedPreset, let preset = LayoutPreset(rawValue: raw) {
            return preset
        }
        return config.today == nil ? .full : nil
    }
}

public extension LayoutConfig {
    /// Overwrites Today with `preset` and records it.
    mutating func apply(_ preset: LayoutPreset) {
        today = preset.todayLayout
        appliedPreset = preset.rawValue
    }
}
