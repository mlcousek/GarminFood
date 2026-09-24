// ProgressSlotHost.swift
//
// add-gamification-signals D12: one fixed place on the Progress tab where
// every gamification feature's card appears, in a fixed order, so the six
// wave-2 changes and wave 3 each replace only their own slot file and never
// edit `ProgressHomeView` (which hosts this with a single line under the
// level card). Every slot ships as `EmptyView`, so this renders nothing
// until a feature lands; its children flatten into the parent stack, so a
// filled slot gets the same spacing as every other card.
//
// Depends on: the eight slot views in this folder.
// Depended on by: ProgressHomeView.

import SwiftUI

@MainActor
struct ProgressSlotHost: View {
    var body: some View {
        BossSlotView()
        BingoSlotView()
        SeasonalSlotView()
        JourneysSlotView()
        RecordsSlotView()
        CollectionsSlotView()
        SportBodySlotView()
        SecretsSlotView()
    }
}
