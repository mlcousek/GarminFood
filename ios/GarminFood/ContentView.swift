// ContentView.swift
//
// Placeholder UI. Gets replaced by the real food-log flow once
// add-food-log-core lands — this exists only so the app has something to
// show and something for `xcodebuild` to actually compile.
//
// Also carries task 6.4's write half of the Keychain-sharing spike: on
// appear, it writes a fresh timestamped value to the shared Keychain group.
// The widget extension (GarminFoodWidget/KeychainCheckWidget.swift) tries to
// read it back — add that widget to the Home Screen to see the result.

import SwiftUI

struct ContentView: View {
    @State private var writeStatus: String = "…"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 48))
            Text("GarminFood")
                .font(.title)
            Text("Build pipeline check — task 6.1")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Divider()
            Text("Keychain write (task 6.4): \(writeStatus)")
                .font(.caption)
                .multilineTextAlignment(.center)
            Text("Add the Keychain Spike widget to your Home Screen to see whether the extension can read it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .onAppear {
            let value = "written-by-app-\(Int(Date().timeIntervalSince1970))"
            let status = KeychainSpike.write(value)
            writeStatus = status == errSecSuccess ? "OK (\(value))" : "FAILED (status \(status))"
        }
    }
}

#Preview {
    ContentView()
}
