// TodaySlotHost.swift
//
// add-gamification-signals D12: the Today tab's slot for gamification
// banners (seasonal event, weekly boss), above the meals list. Both ship as
// `EmptyView`; `add-seasonal-events` and `add-weekly-boss-and-streak-
// freezes` replace their own banner file only. `TodayView` hosts this
// with a single line.
//
// Depends on: SeasonalBannerSlot, BossBannerSlot.
// Depended on by: TodayView.

import SwiftUI

@MainActor
struct TodaySlotHost: View {
    var body: some View {
        SeasonalBannerSlot()
        BossBannerSlot()
    }
}
