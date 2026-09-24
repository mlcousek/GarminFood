// GradientHeaderBackground.swift
//
// The optional Today gradient header (add-themes-and-layout D6, task 2.6;
// off by default): the screen background plus a headerGradientStart -> End
// wash at 22% opacity behind the day switcher and summary card, fading into
// the background. Under Reduce Transparency it becomes a flat 12% tint.
// Text on it stays `.primary`; AppearanceKit's GradientHeaderContrastTests
// checks `.primary` against both stops blended at 22% and 12% for every
// theme.
//
// With the option off it is exactly the plain `Theme.groupedBackground`
// Today had before. Used by TodayView's `.background`.

import SwiftUI
import AppearanceKit

struct GradientHeaderBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .top) {
            Theme.groupedBackground
            if Theme.style.gradientHeader {
                if reduceTransparency {
                    Theme.headerGradientStart.opacity(0.12)
                        .frame(height: 320)
                } else {
                    LinearGradient(
                        colors: [
                            Theme.headerGradientStart.opacity(0.22),
                            Theme.headerGradientEnd.opacity(0.22),
                            Theme.headerGradientEnd.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 360)
                }
            }
        }
        .ignoresSafeArea()
    }
}
