import SwiftUI

/// The app's small in-app wordmark: a "GF" flame-gradient monogram plus a
/// "by Jirka" credit line, reusing the same tokens as the App Icon
/// (`Theme.flameGradient`) so the two marks read as one identity. Placed as
/// a quiet footer on `HomeView`, not a splash screen -- it's a signature,
/// not a loading gate.
struct AppSignatureView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.xs / 2) {
            Text(verbatim: "GF")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.flameGradient)
            Text("by Jirka")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("GarminFood, by Jirka")
    }
}

#Preview {
    AppSignatureView()
        .padding()
}
