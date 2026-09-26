// TodaySlotHost.swift
//
// add-gamification-signals D12: the Today tab's slot for gamification
// banners (seasonal event, weekly boss), above the meals list. Both ship as
// `EmptyView`; `add-seasonal-events` and `add-weekly-boss-and-streak-
// freezes` replace their own banner file only. `TodayView` hosts this
// as its `banners` layout card (add-themes-and-layout D8, task 3.7):
// above the meals by default, and movable/hideable as one block in the
// layout editor.
//
// add-data-safety D6: also the export reminder (BackupReminderBanner),
// last, so a game banner stays on top.
//
// Depends on: SeasonalBannerSlot, BossBannerSlot, BackupReminderBanner.
// Depended on by: TodayView.

import SwiftUI

@MainActor
struct TodaySlotHost: View {
    var body: some View {
        SeasonalBannerSlot()
        BossBannerSlot()
        BackupReminderBanner()
    }
}
