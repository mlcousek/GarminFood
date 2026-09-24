// FoodTagRuleRegistry.swift
//
// The one list of rule sets `FoodTagger` evaluates by default (design D2).
// Every planned set is already registered here -- core plus one empty stub
// per wave-2 change that needs its own tags -- so those changes fill their
// own `FoodTagRules+<Feature>.swift` file and never edit this one.
//
// Depended on by: FoodTagger (default argument), FoodTaggerTests.

import Foundation

public enum FoodTagRuleRegistry {
    public static let all: [FoodTagRuleSet] = [
        .core,
        .seasonal,
        .collections,
        .sport
    ]
}
