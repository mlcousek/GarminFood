// FastingProtocolPickerView.swift
//
// The "start a fast" sheet: the four named protocols plus a custom
// fasting/eating hour pair. Same shape as `ServingPickerSheet.swift` (a
// `NavigationStack`-wrapped sheet with an `onPick` closure the caller uses
// to act, and a Cancel toolbar button) -- one more instance of that same
// small pattern rather than a new one.

import SwiftUI
import FoodLogCore

struct FastingProtocolPickerView: View {
    let onPick: (FastingProtocol) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customFastingHours: Double = 16
    @State private var customEatingHours: Double = 8

    private static let presets: [FastingProtocol] = [.sixteenEight, .eighteenSix, .twentyFour, .omad]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Self.presets, id: \.self) { proto in
                        Button {
                            onPick(proto)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(proto.displayName)
                                        .font(.foodTitle)
                                    Text("\(Int(proto.fastingHours))h fast / \(Int(proto.eatingHours))h eat")
                                        .font(.foodSubtitle)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Stepper("Fast \(Int(customFastingHours))h", value: $customFastingHours, in: 1...48, step: 1)
                    Stepper("Eat \(Int(customEatingHours))h", value: $customEatingHours, in: 1...23, step: 1)
                    Button("Start custom fast") {
                        onPick(.custom(fastingHours: customFastingHours, eatingHours: customEatingHours))
                        dismiss()
                    }
                } header: {
                    Text("Custom")
                }
            }
            .navigationTitle("Choose a fast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    FastingProtocolPickerView(onPick: { _ in })
}
