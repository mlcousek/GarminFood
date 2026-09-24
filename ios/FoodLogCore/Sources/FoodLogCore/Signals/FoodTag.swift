// FoodTag.swift
//
// A real-world category a logged food belongs to ("fish", "colour.red",
// "cuisine.italian", "czechBrand", ...), assigned by `FoodTagger` from the
// food's name/brand/barcode. The whole gamification redesign
// (add-gamification-signals and the wave-2 features built on it: bingo,
// seasonal events, collections, secrets, boss) reads these instead of
// counting days, so "eat fish twice this week" becomes expressible.
//
// Deliberately an OPEN struct, not an enum (design D1): an enum would make
// every wave-2 change edit this one file to add its tags. Instead each
// change declares its own constants in its own `FoodTag+<Feature>.swift`
// extension, and persisted tags round-trip by raw value -- an unknown raw
// value decodes fine. Only tags used by more than one later change live
// here.
//
// Namespacing convention: plain words for food groups, `colour.<name>` for
// produce colours, `cuisine.<name>` for cuisines -- `DayPredicate.
// distinctTagsAtLeast(prefix:)` counts by that prefix.

import Foundation

public struct FoodTag: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: FoodTag, rhs: FoodTag) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { rawValue }

    /// Whether this tag's raw value starts with `prefix` ("colour.", "cuisine.").
    public func hasPrefix(_ prefix: String) -> Bool {
        rawValue.hasPrefix(prefix)
    }
}

// MARK: - Core tags (design D1)

extension FoodTag {
    // Food groups
    public static let fruit = FoodTag("fruit")
    public static let vegetable = FoodTag("vegetable")
    public static let fish = FoodTag("fish")
    public static let seafood = FoodTag("seafood")
    public static let meat = FoodTag("meat")
    public static let redMeat = FoodTag("redMeat")
    public static let poultry = FoodTag("poultry")
    public static let egg = FoodTag("egg")
    public static let dairy = FoodTag("dairy")
    public static let cheese = FoodTag("cheese")
    public static let fermented = FoodTag("fermented")
    public static let legume = FoodTag("legume")
    public static let nuts = FoodTag("nuts")
    public static let wholeGrain = FoodTag("wholeGrain")
    public static let soup = FoodTag("soup")
    public static let coffee = FoodTag("coffee")
    public static let tea = FoodTag("tea")
    public static let sugaryDrink = FoodTag("sugaryDrink")
    public static let alcohol = FoodTag("alcohol")
    public static let beer = FoodTag("beer")
    public static let sweets = FoodTag("sweets")
    public static let pastry = FoodTag("pastry")
    public static let pizza = FoodTag("pizza")
    public static let pie = FoodTag("pie")
    public static let potato = FoodTag("potato")
    public static let knedlik = FoodTag("knedlik")

    // Colours (produce)
    public static let colourPrefix = "colour."
    public static let colourRed = FoodTag("colour.red")
    public static let colourOrange = FoodTag("colour.orange")
    public static let colourYellow = FoodTag("colour.yellow")
    public static let colourGreen = FoodTag("colour.green")
    public static let colourPurple = FoodTag("colour.purple")
    public static let colourWhite = FoodTag("colour.white")

    /// The six rainbow colours, in display order.
    public static let allColours: [FoodTag] = [
        .colourRed, .colourOrange, .colourYellow, .colourGreen, .colourPurple, .colourWhite
    ]

    // Cuisines
    public static let cuisinePrefix = "cuisine."
    public static let cuisineCzech = FoodTag("cuisine.czech")
    public static let cuisineItalian = FoodTag("cuisine.italian")
    public static let cuisineJapanese = FoodTag("cuisine.japanese")
    public static let cuisineChinese = FoodTag("cuisine.chinese")
    public static let cuisineIndian = FoodTag("cuisine.indian")
    public static let cuisineMexican = FoodTag("cuisine.mexican")
    public static let cuisineThai = FoodTag("cuisine.thai")
    public static let cuisineVietnamese = FoodTag("cuisine.vietnamese")
    public static let cuisineGreek = FoodTag("cuisine.greek")
    public static let cuisineTurkish = FoodTag("cuisine.turkish")
    public static let cuisineSpanish = FoodTag("cuisine.spanish")
    public static let cuisineFrench = FoodTag("cuisine.french")
    public static let cuisineAmerican = FoodTag("cuisine.american")
    public static let cuisineKorean = FoodTag("cuisine.korean")
    public static let cuisineMiddleEastern = FoodTag("cuisine.middleEastern")

    /// Brand on `CzechBrands.all`, or (brand unknown) an EAN-13 with the
    /// GS1 Czech prefix 859.
    public static let czechBrand = FoodTag("czechBrand")
}
