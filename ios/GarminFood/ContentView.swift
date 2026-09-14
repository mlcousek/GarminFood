// ContentView.swift
//
// Placeholder UI. Gets replaced by the real food-log flow once
// add-food-log-core lands — this exists only so the app has something to
// show and something for `xcodebuild` to actually compile.

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 48))
            Text("GarminFood")
                .font(.title)
            Text("Build pipeline check — task 6.1")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
