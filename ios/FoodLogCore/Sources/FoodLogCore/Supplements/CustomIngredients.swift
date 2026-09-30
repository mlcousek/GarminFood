// CustomIngredients.swift
//
// add-custom-ingredients-and-owner-supplements: an ingredient the user
// creates because neither the evidence-card list nor the known-ingredient
// list (IngredientCatalog.swift) has it -- "I cannot add a custom ingredient
// and it was not in the suggestions" was the owner's report. Before this,
// the product editor's ingredient row was a Picker over
// `IngredientID.builtIn` only, so a label with, say, ashwagandha or a
// tincture in ml could not be entered at all.
//
// A custom ingredient is a name, a unit (mg, µg, g, IU or ml) and optional
// forms ("citrate", "MK-7"...). It is kept in the plan file
// (`SupplementPlan.customIngredients`, SupplementPlanStore) rather than a
// store of its own: it is written atomically with the product that uses
// it, the backup already covers `supplement-plan.json`, and there is no
// second file that could be quarantined separately (design D1).
//
// Its id carries its unit -- "custom:ml:<uuid>" -- so `IngredientID.
// canonicalUnit` (which has no plan to look at) totals it in that unit and
// never converts it to a mass (design D2). Rows that use it also copy the
// name into `IngredientAmount.customName`, so every label line reads right
// even where only the product is at hand.
//
// Depends on: SupplementModels (IngredientID, DoseUnit, SupplementPlan),
// SearchText (folding for duplicate names). Depended on by:
// SupplementPlanStore (upsert), IngredientSearch, the app's ingredient
// picker. Tests: CustomIngredientTests.

import Foundation

public struct CustomIngredient: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: IngredientID
    public var name: String
    /// The unit new rows start in; the same unit the id carries.
    public var unit: DoseUnit
    /// Chemical forms the user typed for it, most recent first.
    public var forms: [String]

    public init(id: IngredientID, name: String, unit: DoseUnit, forms: [String] = []) {
        self.id = id
        self.name = name
        self.unit = unit
        self.forms = forms
    }

    /// A new ingredient with a fresh id in `unit`. `nil` when the name is
    /// blank.
    public static func make(name: String, unit: DoseUnit, form: String? = nil, uuid: UUID = UUID()) -> CustomIngredient? {
        let trimmed = CustomIngredient.clean(name)
        guard !trimmed.isEmpty else { return nil }
        var ingredient = CustomIngredient(id: .custom(unit: unit, uuid: uuid), name: trimmed, unit: unit)
        ingredient.addForm(form)
        return ingredient
    }

    /// Remembers `form` (trimmed, first), without duplicates.
    public mutating func addForm(_ form: String?) {
        let trimmed = CustomIngredient.clean(form ?? "")
        guard !trimmed.isEmpty else { return }
        forms.removeAll { SearchText.fold($0) == SearchText.fold(trimmed) }
        forms.insert(trimmed, at: 0)
    }

    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey { case id, name, unit, forms }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(IngredientID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        unit = try container.decodeIfPresent(DoseUnit.self, forKey: .unit) ?? id.canonicalUnit
        forms = try container.decodeIfPresent([String].self, forKey: .forms) ?? []
    }
}

/// Decodes one `CustomIngredient` or nothing, so a damaged entry is dropped
/// instead of failing the plan file.
struct LossyCustomIngredient: Decodable {
    let value: CustomIngredient?

    init(from decoder: Decoder) throws {
        let ingredient = try? CustomIngredient(from: decoder)
        if let ingredient, !CustomIngredient.clean(ingredient.name).isEmpty, ingredient.id.isCustom {
            value = ingredient
        } else {
            value = nil
        }
    }
}

extension IngredientID {
    static let customPrefix = "custom:"

    /// "custom:<unit>:<uuid>" (design D2).
    public static func custom(unit: DoseUnit, uuid: UUID = UUID()) -> IngredientID {
        IngredientID(customPrefix + unit.rawValue + ":" + uuid.uuidString.lowercased())
    }

    /// Created by the user (`CustomIngredient`).
    public var isCustom: Bool { rawValue.hasPrefix(IngredientID.customPrefix) }

    /// The unit a custom id carries; `nil` for any other id.
    var customUnit: DoseUnit? {
        guard isCustom else { return nil }
        let parts = rawValue.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].isEmpty else { return nil }
        return DoseUnit(String(parts[1]))
    }
}

extension SupplementPlan {
    public var customIngredientList: [CustomIngredient] { customIngredients ?? [] }

    public func customIngredient(id: IngredientID) -> CustomIngredient? {
        customIngredients?.first { $0.id == id }
    }

    /// The saved custom ingredient whose name matches `name` (case and
    /// diacritics ignored), so "Ashwagandha" isn't created twice.
    public func customIngredient(named name: String) -> CustomIngredient? {
        let folded = SearchText.fold(CustomIngredient.clean(name))
        guard !folded.isEmpty else { return nil }
        return customIngredients?.first { SearchText.fold($0.name) == folded }
    }

    /// Adds `ingredient`, or replaces the one with the same id. Returns
    /// whether anything changed.
    @discardableResult
    public mutating func upsertCustomIngredient(_ ingredient: CustomIngredient) -> Bool {
        var list = customIngredients ?? []
        if let index = list.firstIndex(where: { $0.id == ingredient.id }) {
            guard list[index] != ingredient else { return false }
            list[index] = ingredient
        } else {
            list.append(ingredient)
        }
        customIngredients = list
        return true
    }

    /// The name to show for `ingredient`: a built-in or known name, a
    /// custom ingredient's name, a product row's `customName`, else the id.
    public func ingredientName(_ ingredient: IngredientID) -> String {
        if let custom = customIngredient(id: ingredient) { return custom.name }
        if !ingredient.isCustom, let known = IngredientCatalog.knownName(of: ingredient) { return known }
        for product in products {
            if let row = product.ingredients.first(where: { $0.ingredient == ingredient }), let name = row.customName, !name.isEmpty {
                return name
            }
        }
        return EvidenceCatalog.name(of: ingredient)
    }
}
