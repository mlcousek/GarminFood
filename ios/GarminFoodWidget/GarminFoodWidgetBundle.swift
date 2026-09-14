// GarminFoodWidgetBundle.swift
//
// The widget extension's entry point. Just the one throwaway spike widget
// for now — task 6.4's Keychain-sharing test. Real widgets (the calorie
// ring, Controls) land with add-glanceable-surfaces, as their own targets
// or additions to this bundle at that point.

import WidgetKit
import SwiftUI

@main
struct GarminFoodWidgetBundle: WidgetBundle {
    var body: some Widget {
        KeychainCheckWidget()
    }
}
