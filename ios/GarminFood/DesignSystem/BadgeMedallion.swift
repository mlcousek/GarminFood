// BadgeMedallion.swift
//
// "badges with images, tiers" ask: this project cannot add real raster/
// vector image assets responsibly -- no Mac to preview or verify how they
// render, no image-generation pipeline wired into this codebase (see
// CLAUDE.md's "no Mac" constraint). So "images" means a genuinely layered
// badge built entirely from SwiftUI shapes/gradients/materials/SF Symbols:
// a base disc, a rarity-coloured rim, an inner highlight ring, a soft glow
// for the top two rarities, and a locked state that desaturates all of it
// down to a plain grey disc + lock glyph. One shape family only (circle),
// matching every other circular indicator already in this app (StreakDot,
// ProgressRing) so this doesn't read as a second design language.
//
// Deliberately NOT in Shared/Theme.swift: this needs Gamification's
// `AchievementRarity` type, and Gamification is app-only -- not linked into
// the widget extension target, which also compiles Theme.swift (see
// CLAUDE.md's architecture section). Importing Gamification there would
// break the widget build. This file's own small rarity palette lives here
// instead, picked to sit alongside Theme's existing hues without colliding
// with the macro colours (carbs/protein/fat), which already mean something
// else everywhere else in the app.

import SwiftUI
import Gamification

struct BadgeMedallion: View {
    let symbol: String
    let rarity: AchievementRarity
    let isLocked: Bool
    var size: CGFloat = 60

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var showsShine: Bool { !isLocked && rarity >= .epic }

    var body: some View {
        ZStack {
            base
            if showsShine { shine }
            glyph
        }
        .frame(width: size, height: size)
        .onAppear { revealed = true }
    }

    private var base: some View {
        Circle()
            .fill(isLocked ? AnyShapeStyle(Color.primary.opacity(0.07)) : AnyShapeStyle(RarityPalette.fill(rarity)))
            .overlay {
                Circle()
                    .strokeBorder(isLocked ? Color.primary.opacity(0.16) : RarityPalette.rim(rarity), lineWidth: max(1.5, size * 0.045))
            }
            .overlay {
                // A thin inner highlight ring reads as "metal catching
                // light" -- the one cue that most separates a real medallion
                // from a flat filled circle.
                Circle()
                    .strokeBorder(Color.white.opacity(isLocked ? 0 : 0.32), lineWidth: 1)
                    .padding(size * 0.09)
            }
            .shadow(color: isLocked ? .clear : RarityPalette.rim(rarity).opacity(0.35), radius: size * 0.09, y: size * 0.03)
    }

    /// A one-shot diagonal shine that plays in when the badge first appears
    /// unlocked, reserved for `.epic`/`.legendary` so the very best badges
    /// visibly stand out from the rest of the grid. Respects Reduce Motion
    /// by simply not animating -- the shine still ends up in its final,
    /// static position either way (same pattern as `ProgressRing`/
    /// `MacroBar`: `.animation(reduceMotion ? nil : ..., value:)`).
    private var shine: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.5), .white.opacity(0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .mask { Circle() }
            .rotationEffect(.degrees(revealed ? 0 : -30))
            .opacity(revealed ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.55).delay(0.1), value: revealed)
            .allowsHitTesting(false)
    }

    private var glyph: some View {
        Image(systemName: isLocked ? "lock.fill" : symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(isLocked ? Color.secondary : .white)
    }
}

/// `BadgeMedallion`'s colour ramp for `AchievementRarity` -- see this
/// file's header for why it isn't in `Shared/Theme.swift`.
private enum RarityPalette {
    static func fill(_ rarity: AchievementRarity) -> LinearGradient {
        let (top, bottom) = colors(rarity)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static func rim(_ rarity: AchievementRarity) -> Color {
        colors(rarity).1
    }

    /// (top, bottom) stops -- bottom doubles as the rim colour so the rim
    /// always reads as "the deep end of the same metal", not an unrelated
    /// outline colour.
    private static func colors(_ rarity: AchievementRarity) -> (Color, Color) {
        switch rarity {
        case .common:
            // Brushed pewter.
            return (Color(red: 0.70, green: 0.72, blue: 0.76), Color(red: 0.47, green: 0.49, blue: 0.53))
        case .uncommon:
            // Patinated bronze-green.
            return (Color(red: 0.42, green: 0.71, blue: 0.54), Color(red: 0.19, green: 0.49, blue: 0.35))
        case .rare:
            // Polished steel-blue.
            return (Color(red: 0.40, green: 0.62, blue: 0.94), Color(red: 0.18, green: 0.38, blue: 0.75))
        case .epic:
            // Amethyst.
            return (Color(red: 0.66, green: 0.46, blue: 0.93), Color(red: 0.44, green: 0.24, blue: 0.73))
        case .legendary:
            // Warm gold, deliberately close in hue to Theme's own ember/
            // accent so a legendary badge still feels like it belongs to
            // this app's palette rather than a bolted-on rainbow tier.
            return (Color(red: 0.99, green: 0.80, blue: 0.30), Color(red: 0.92, green: 0.50, blue: 0.15))
        }
    }
}

#Preview("BadgeMedallion -- unlocked, all rarities") {
    HStack(spacing: 16) {
        ForEach(AchievementRarity.allCases, id: \.self) { rarity in
            VStack(spacing: 6) {
                BadgeMedallion(symbol: "flame.fill", rarity: rarity, isLocked: false, size: 60)
                Text(rarity.displayName).font(.caption2)
            }
        }
    }
    .padding()
}

#Preview("BadgeMedallion -- locked vs unlocked") {
    HStack(spacing: 24) {
        BadgeMedallion(symbol: "crown.fill", rarity: .legendary, isLocked: true, size: 80)
        BadgeMedallion(symbol: "crown.fill", rarity: .legendary, isLocked: false, size: 80)
    }
    .padding()
}
