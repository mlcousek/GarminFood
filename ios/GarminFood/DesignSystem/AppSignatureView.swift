// AppSignatureView.swift
//
// The app's small in-app signature: Jirka's Arc's arc mark (`ArcMark`, the
// app icon's glyph) in the flame-gradient token over a "by Jirka" credit
// line, so the footer and the Home Screen icon read as one identity
// (rebrand-to-jirkas-arc design.md D4; it replaced the "GF" monogram). A
// quiet footer, not a splash screen: pinned to the bottom of Today
// (`TodayCardID.signature`, not hideable) and shown on Profile.
//
// Theme tokens only, so it redraws on a theme switch; the mark's height
// follows Dynamic Type with the caption under it. VoiceOver reads it as one
// element, "Jirka's Arc, by Jirka".
//
// Depends on: ArcMark, Theme. Depended on by: TodayView, ProfileView.

import SwiftUI

struct AppSignatureView: View {
    /// About the old 15 pt "GF" cap height, scaled with the caption.
    @ScaledMetric(relativeTo: .caption2) private var markHeight: CGFloat = 12

    var body: some View {
        VStack(spacing: Theme.Spacing.xs / 2) {
            ArcMark()
                .fill(Theme.flameGradient)
                .frame(width: markHeight * ArcMark.aspectRatio, height: markHeight)
            Text("by Jirka")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jirka's Arc, by Jirka")
    }
}

#Preview {
    AppSignatureView()
        .padding()
}
