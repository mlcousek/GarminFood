// SeasonalBannerSlot.swift
//
// STUB (add-gamification-signals D12): the Today-tab slot for the seasonal event banner.
// Ships empty; `add-seasonal-events` replaces this file's contents (and adds its
// own screens) without touching the host or any shared view. To reach its
// feature's own async API: `environment.gamificationEngine.featureHost?
// .feature(<FeatureType>.self)`; the generic hub-card data is
// `featureHost?.summaries[<featureId>]`.
//
// Depended on by: TodaySlotHost.

import SwiftUI

@MainActor
struct SeasonalBannerSlot: View {
    var body: some View {
        EmptyView()
    }
}
