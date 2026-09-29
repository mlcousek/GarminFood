// ArcMark.swift
//
// Jirka's Arc's mark as a SwiftUI `Shape` (rebrand-to-jirkas-arc design.md
// D3, D4): a thick arc with round caps rising from the lower left to a
// shoulder right of centre, and a "you are here" dot just past its peak, set
// off from the arc by a knocked-out ring. It is the app icon's glyph
// (tools/generate-app-icons.py draws the same geometry into every icon PNG),
// so the in-app signature and the Home Screen icon read as one identity.
//
// Why a Shape and not an image: it is filled with theme tokens
// (`Theme.flameGradient` in the signature, `Theme.accent` in onboarding), so
// it redraws with every theme and in both color schemes, and stays sharp at
// any Dynamic Type size. No literal colors: the design-token lint passes
// without an allowlist entry.
//
// The constants are the icon generator's ARC_* / DOT_* values in 1024 px
// icon space; change both together. The path is fitted, centered and
// aspect-preserving, into whatever rect it gets (`aspectRatio` sizes a
// frame that wastes no space).
//
// Depended on by: AppSignatureView (Today's and Profile's footer) and
// OnboardingView (the welcome page).

import SwiftUI

struct ArcMark: Shape {
    // Icon-space geometry (y down; angles counter-clockwise from +x, as in
    // the generator, so 90 is the top of the arc).
    private static let center = CGPoint(x: 545, y: 700)
    private static let radius: CGFloat = 380
    private static let stroke: CGFloat = 84
    private static let startAngle: Double = 165
    private static let endAngle: Double = 25
    private static let dotAngle: Double = 65
    private static let dotRadius: CGFloat = 62
    private static let dotGap: CGFloat = 96

    /// The mark's bounding box in icon space: the arc with its round caps
    /// (left cap to right cap, arc top to left cap bottom).
    static let bounds = CGRect(x: 135.95, y: 278, width: 795.45, height: 365.65)

    /// Width / height of the mark.
    static let aspectRatio: CGFloat = bounds.width / bounds.height

    func path(in rect: CGRect) -> Path {
        let box = Self.bounds
        let scale = min(rect.width / box.width, rect.height / box.height)
        guard scale > 0 else { return Path() }
        let origin = CGPoint(x: rect.midX - box.width * scale / 2, y: rect.midY - box.height * scale / 2)

        func mapped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + (point.x - box.minX) * scale, y: origin.y + (point.y - box.minY) * scale)
        }
        func onArc(_ degrees: Double) -> CGPoint {
            let radians = degrees * .pi / 180
            return CGPoint(
                x: Self.center.x + Self.radius * CGFloat(cos(radians)),
                y: Self.center.y - Self.radius * CGFloat(sin(radians))
            )
        }
        func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }

        // The arc's centre line as a polyline (explicit points: no
        // clockwise/flipped-coordinate ambiguity), stroked with round caps.
        var line = Path()
        let steps = 96
        for step in 0...steps {
            let angle = Self.startAngle + (Self.endAngle - Self.startAngle) * Double(step) / Double(steps)
            let point = mapped(onArc(angle))
            if step == 0 {
                line.move(to: point)
            } else {
                line.addLine(to: point)
            }
        }
        let arc = line.strokedPath(StrokeStyle(lineWidth: Self.stroke * scale, lineCap: .round, lineJoin: .round))

        let dotCenter = mapped(onArc(Self.dotAngle))
        return arc
            .subtracting(circle(dotCenter, Self.dotGap * scale))
            .union(circle(dotCenter, Self.dotRadius * scale))
    }
}

#Preview {
    VStack(spacing: 24) {
        ArcMark()
            .fill(Theme.flameGradient)
            .frame(width: 24 * ArcMark.aspectRatio, height: 24)
        ArcMark()
            .fill(Theme.accent)
            .frame(width: 200, height: 200)
            .border(.secondary)
    }
    .padding()
}
