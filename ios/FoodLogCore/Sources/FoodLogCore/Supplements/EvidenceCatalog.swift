// EvidenceCatalog.swift
//
// Offline evidence cards, one per built-in ingredient (add-supplements D8,
// spec "Evidence cards explain each ingredient offline with cited
// sources"): what it's for, evidence strength, typical dose, timing and
// with-food notes, the default upper limit, sources, and the disclaimer.
// Static and bundled -- no network, ever.
//
// Limits: the values of design D8's table, which were checked against the
// source PDFs on 2026-09-25 (a web summarizer returned WRONG EFSA values
// during research, so never "refresh" these from a summary):
//   vitamin D 100 µg (4000 IU) UL; vitamin C no EU UL (US 2000 mg, shown as
//   US); zinc 25 mg UL; magnesium 250 mg UL, supplemental only; vitamin B6
//   12 mg UL; iron 40 mg "safe level" (not a UL); selenium 255 µg UL;
//   EPA+DHA no UL (<= 5 g/day from supplements raises no concern); creatine
//   no UL (3 g/day unlikely to pose risk); caffeine 400 mg/day, 200 mg
//   single dose.
// Ingredients outside that table (B12, K2, sodium, potassium, beta-alanine)
// have no EU upper limit set, and none is invented here.
//
// `effectiveRange` (the label score's "dose against the evidence", D7) and
// the card texts are written for this app from the cited sources' general
// guidance; no prose is copied. Attribution follows EFSA's reproduction
// terms ("source acknowledged") and credits NIH ODS.
//
// Texts are package strings (`String(localized:bundle: .module)`, en + cs in
// Resources/*.lproj) so they follow the app language like every other
// FoodLogCore string and are checked by tools/check-localizations.mjs.
//
// Depended on by: SupplementLimits (defaults), LabelScore (ranges), the
// evidence card view (wave 3). Tests: EvidenceCatalogTests.

import Foundation

public enum EvidenceStrength: String, Sendable, CaseIterable {
    case strong
    case moderate
    case limited

    public var title: String {
        switch self {
        case .strong: return String(localized: "Strong evidence", bundle: .module, comment: "Supplement evidence card: how strong the research support is.")
        case .moderate: return String(localized: "Moderate evidence", bundle: .module, comment: "Supplement evidence card: how strong the research support is.")
        case .limited: return String(localized: "Limited evidence", bundle: .module, comment: "Supplement evidence card: how strong the research support is.")
        }
    }
}

/// What kind of figure a default limit is (design D8).
public enum LimitKind: String, Sendable, Equatable {
    /// A tolerable upper intake level (EFSA/SCF).
    case upperLimit
    /// A level EFSA considers safe, explicitly not a formal UL (iron,
    /// caffeine).
    case safeLevel
    /// No EU upper limit set; `DefaultLimit.value` is `nil`.
    case noEUUpperLimit
}

/// A cited source.
public struct EvidenceSource: Sendable, Equatable, Hashable {
    /// Proper name of the publication (not translated).
    public let title: String
    public let url: URL

    init(_ title: String, _ url: String) {
        self.title = title
        // Only static, hand-checked literals are passed in.
        self.url = URL(string: url)!
    }
}

/// A default limit, in the ingredient's canonical unit.
public struct DefaultLimit: Sendable, Equatable {
    public let kind: LimitKind
    /// The figure over-limit warnings use by default; `nil` = no warning
    /// unless the user sets their own limit.
    public let value: Double?
    /// A per-dose limit (caffeine 200 mg).
    public let singleDose: Double?
    /// The US figure where the EU has none, always labelled as US (D6).
    public let usFigure: Double?
    /// A reassurance level that is not a limit (EPA+DHA 5 g, creatine 3 g).
    public let noConcernLevel: Double?
    /// Counts supplements only, food intake excluded (magnesium).
    public let supplementalOnly: Bool
    public let source: EvidenceSource

    init(
        kind: LimitKind,
        value: Double? = nil,
        singleDose: Double? = nil,
        usFigure: Double? = nil,
        noConcernLevel: Double? = nil,
        supplementalOnly: Bool = false,
        source: EvidenceSource
    ) {
        self.kind = kind
        self.value = value
        self.singleDose = singleDose
        self.usFigure = usFigure
        self.noConcernLevel = noConcernLevel
        self.supplementalOnly = supplementalOnly
        self.source = source
    }
}

/// One ingredient's card.
public struct EvidenceCard: Sendable, Identifiable {
    public let ingredient: IngredientID
    public let strength: EvidenceStrength
    /// Daily amount range (canonical unit) the evidence usually supports;
    /// `nil` where a range would mislead (iron: only for a documented need;
    /// electrolytes: depends on sweat losses).
    public let effectiveRange: ClosedRange<Double>?
    public let limit: DefaultLimit
    /// Every source, the limit's first.
    public let sources: [EvidenceSource]

    public var id: IngredientID { ingredient }
    public var unit: DoseUnit { ingredient.canonicalUnit }

    public var name: String { EvidenceCatalog.name(of: ingredient) }
    public var purpose: String { EvidenceCatalog.texts(of: ingredient).purpose }
    public var typicalDose: String { EvidenceCatalog.texts(of: ingredient).dose }
    public var timing: String { EvidenceCatalog.texts(of: ingredient).timing }
    /// Extra wording about the limit (supplemental-only, safe level, US
    /// figure...), `nil` when the number says it all.
    public var limitNote: String? { EvidenceCatalog.limitNote(of: ingredient) }
}

public enum EvidenceCatalog {
    // MARK: Sources

    static let efsaULSummary = EvidenceSource(
        "EFSA – Overview on Tolerable Upper Intake Levels (summary tables v11, August 2025)",
        "https://www.efsa.europa.eu/sites/default/files/assets/UL_Summary_tables.pdf"
    )
    static let efsaOmega3 = EvidenceSource(
        "EFSA NDA Panel (2012): Tolerable upper intake level of EPA, DHA and DPA",
        "https://doi.org/10.2903/j.efsa.2012.2815"
    )
    static let efsaCaffeine = EvidenceSource(
        "EFSA NDA Panel (2015): Scientific opinion on the safety of caffeine",
        "https://doi.org/10.2903/j.efsa.2015.4102"
    )
    static let efsaCreatine = EvidenceSource(
        "EFSA AFC Panel (2004): Creatine monohydrate for use in foods for particular nutritional uses",
        "https://doi.org/10.2903/j.efsa.2004.36"
    )
    static let issnCreatine = EvidenceSource(
        "ISSN position stand (2017): creatine supplementation in exercise, sport and medicine",
        "https://doi.org/10.1186/s12970-017-0173-z"
    )
    static let issnBetaAlanine = EvidenceSource(
        "ISSN position stand (2015): beta-alanine",
        "https://doi.org/10.1186/s12970-015-0090-y"
    )
    static let issnCaffeine = EvidenceSource(
        "ISSN position stand (2021): caffeine and exercise performance",
        "https://doi.org/10.1186/s12970-020-00383-4"
    )

    static func ods(_ title: String, _ page: String) -> EvidenceSource {
        EvidenceSource("NIH Office of Dietary Supplements – \(title) fact sheet", "https://ods.od.nih.gov/factsheets/\(page)-HealthProfessional/")
    }

    // MARK: Cards

    /// Every card, in `IngredientID.builtIn` order.
    public static let all: [EvidenceCard] = [
        EvidenceCard(
            ingredient: .creatine, strength: .strong, effectiveRange: 3...5,
            limit: DefaultLimit(kind: .noEUUpperLimit, noConcernLevel: 3, source: efsaCreatine),
            sources: [efsaCreatine, issnCreatine]
        ),
        EvidenceCard(
            ingredient: .magnesium, strength: .limited, effectiveRange: 100...250,
            limit: DefaultLimit(kind: .upperLimit, value: 250, supplementalOnly: true, source: efsaULSummary),
            sources: [efsaULSummary, ods("Magnesium", "Magnesium")]
        ),
        EvidenceCard(
            ingredient: .vitaminD, strength: .moderate, effectiveRange: 10...50,
            limit: DefaultLimit(kind: .upperLimit, value: 100, source: efsaULSummary),
            sources: [efsaULSummary, ods("Vitamin D", "VitaminD")]
        ),
        EvidenceCard(
            ingredient: .vitaminC, strength: .limited, effectiveRange: 100...1000,
            limit: DefaultLimit(kind: .noEUUpperLimit, usFigure: 2000, source: efsaULSummary),
            sources: [efsaULSummary, ods("Vitamin C", "VitaminC")]
        ),
        EvidenceCard(
            ingredient: .zinc, strength: .limited, effectiveRange: 5...25,
            limit: DefaultLimit(kind: .upperLimit, value: 25, source: efsaULSummary),
            sources: [efsaULSummary, ods("Zinc", "Zinc")]
        ),
        EvidenceCard(
            ingredient: .omega3EPA_DHA, strength: .moderate, effectiveRange: 250...2000,
            limit: DefaultLimit(kind: .noEUUpperLimit, noConcernLevel: 5000, source: efsaOmega3),
            sources: [efsaOmega3, ods("Omega-3 fatty acids", "Omega3FattyAcids")]
        ),
        EvidenceCard(
            ingredient: .vitaminB12, strength: .strong, effectiveRange: 4...1000,
            limit: DefaultLimit(kind: .noEUUpperLimit, source: efsaULSummary),
            sources: [efsaULSummary, ods("Vitamin B12", "VitaminB12")]
        ),
        EvidenceCard(
            ingredient: .iron, strength: .strong, effectiveRange: nil,
            limit: DefaultLimit(kind: .safeLevel, value: 40, source: efsaULSummary),
            sources: [efsaULSummary, ods("Iron", "Iron")]
        ),
        EvidenceCard(
            ingredient: .selenium, strength: .limited, effectiveRange: 50...200,
            limit: DefaultLimit(kind: .upperLimit, value: 255, source: efsaULSummary),
            sources: [efsaULSummary, ods("Selenium", "Selenium")]
        ),
        EvidenceCard(
            ingredient: .vitaminB6, strength: .limited, effectiveRange: 1...10,
            limit: DefaultLimit(kind: .upperLimit, value: 12, source: efsaULSummary),
            sources: [efsaULSummary, ods("Vitamin B6", "VitaminB6")]
        ),
        EvidenceCard(
            ingredient: .caffeine, strength: .strong, effectiveRange: 100...400,
            limit: DefaultLimit(kind: .safeLevel, value: 400, singleDose: 200, source: efsaCaffeine),
            sources: [efsaCaffeine, issnCaffeine]
        ),
        EvidenceCard(
            ingredient: .betaAlanine, strength: .moderate, effectiveRange: 3.2...6.4,
            limit: DefaultLimit(kind: .noEUUpperLimit, source: issnBetaAlanine),
            sources: [issnBetaAlanine]
        ),
        EvidenceCard(
            ingredient: .sodium, strength: .moderate, effectiveRange: nil,
            limit: DefaultLimit(kind: .noEUUpperLimit, source: efsaULSummary),
            sources: [efsaULSummary]
        ),
        EvidenceCard(
            ingredient: .potassium, strength: .limited, effectiveRange: nil,
            limit: DefaultLimit(kind: .noEUUpperLimit, source: efsaULSummary),
            sources: [efsaULSummary, ods("Potassium", "Potassium")]
        ),
        EvidenceCard(
            ingredient: .vitaminK2, strength: .limited, effectiveRange: 45...200,
            limit: DefaultLimit(kind: .noEUUpperLimit, source: efsaULSummary),
            sources: [efsaULSummary, ods("Vitamin K", "VitaminK")]
        )
    ]

    public static func card(for ingredient: IngredientID) -> EvidenceCard? {
        all.first { $0.ingredient == ingredient }
    }

    /// Shown on every card and the totals view (design D8, "Safety:
    /// informational + disclaimer").
    public static var disclaimer: String {
        String(localized: "Information only, not medical advice. Talk to a doctor or pharmacist before starting a supplement, especially during pregnancy, when taking medication or with a health condition.", bundle: .module, comment: "Supplement evidence disclaimer shown on every evidence card.")
    }

    /// "No EU upper limit set" (design D6).
    public static var noEUUpperLimitText: String {
        String(localized: "No EU upper limit set", bundle: .module, comment: "Supplement evidence card / limits: the EU has no tolerable upper intake level for this ingredient.")
    }

    // MARK: Texts

    /// Display name of an ingredient; a custom one falls back to its id.
    public static func name(of ingredient: IngredientID) -> String {
        switch ingredient {
        case .creatine: return String(localized: "Creatine", bundle: .module, comment: "Supplement ingredient name.")
        case .magnesium: return String(localized: "Magnesium", bundle: .module, comment: "Nutrient name.")
        case .vitaminD: return String(localized: "Vitamin D", bundle: .module, comment: "Nutrient name.")
        case .vitaminC: return String(localized: "Vitamin C", bundle: .module, comment: "Nutrient name.")
        case .zinc: return String(localized: "Zinc", bundle: .module, comment: "Nutrient name.")
        case .omega3EPA_DHA: return String(localized: "Omega-3 (EPA + DHA)", bundle: .module, comment: "Supplement ingredient name: the omega-3 fatty acids EPA and DHA combined.")
        case .vitaminB12: return String(localized: "Vitamin B12", bundle: .module, comment: "Nutrient name.")
        case .iron: return String(localized: "Iron", bundle: .module, comment: "Nutrient name.")
        case .selenium: return String(localized: "Selenium", bundle: .module, comment: "Nutrient name.")
        case .vitaminB6: return String(localized: "Vitamin B6", bundle: .module, comment: "Nutrient name.")
        case .caffeine: return String(localized: "Caffeine", bundle: .module, comment: "Supplement ingredient name.")
        case .betaAlanine: return String(localized: "Beta-alanine", bundle: .module, comment: "Supplement ingredient name.")
        case .sodium: return String(localized: "Sodium", bundle: .module, comment: "Nutrient name.")
        case .potassium: return String(localized: "Potassium", bundle: .module, comment: "Nutrient name.")
        case .vitaminK2: return String(localized: "Vitamin K2", bundle: .module, comment: "Supplement ingredient name.")
        default: return ingredient.rawValue
        }
    }

    struct Texts {
        let purpose: String
        let dose: String
        let timing: String
    }

    static func texts(of ingredient: IngredientID) -> Texts {
        switch ingredient {
        case .creatine:
            return Texts(
                purpose: String(localized: "Supports repeated short, hard efforts and strength training. One of the best-studied sports supplements.", bundle: .module, comment: "Evidence card, creatine: what it is for."),
                dose: String(localized: "3–5 g a day. Optional loading: about 0.3 g per kg of body weight a day for 5–7 days.", bundle: .module, comment: "Evidence card, creatine: typical dose."),
                timing: String(localized: "Any time of day; taking it every day matters more than when. With a meal is fine.", bundle: .module, comment: "Evidence card, creatine: timing and food.")
            )
        case .magnesium:
            return Texts(
                purpose: String(localized: "Helps muscle and nerve function and energy metabolism. Mainly worth it when your diet falls short.", bundle: .module, comment: "Evidence card, magnesium: what it is for."),
                dose: String(localized: "Typically 100–250 mg a day from supplements. Citrate and bisglycinate are absorbed well, oxide less so.", bundle: .module, comment: "Evidence card, magnesium: typical dose."),
                timing: String(localized: "Often taken in the evening. Large single doses can loosen the stool; splitting them helps.", bundle: .module, comment: "Evidence card, magnesium: timing and food.")
            )
        case .vitaminD:
            return Texts(
                purpose: String(localized: "Supports bones, muscles and the immune system. Matters most in autumn and winter, when the sun in Central Europe is too low.", bundle: .module, comment: "Evidence card, vitamin D: what it is for."),
                dose: String(localized: "Commonly 10–50 µg (400–2000 IU) a day. A blood test shows what you actually need.", bundle: .module, comment: "Evidence card, vitamin D: typical dose."),
                timing: String(localized: "With a meal that contains some fat, which helps absorption.", bundle: .module, comment: "Evidence card, vitamin D: timing and food.")
            )
        case .vitaminC:
            return Texts(
                purpose: String(localized: "An antioxidant needed for collagen and the immune system. A varied diet with fruit and vegetables usually covers it.", bundle: .module, comment: "Evidence card, vitamin C: what it is for."),
                dose: String(localized: "Typically 100–1000 mg a day; most of any excess is excreted.", bundle: .module, comment: "Evidence card, vitamin C: typical dose."),
                timing: String(localized: "Any time. With a meal it helps you absorb iron from plant foods.", bundle: .module, comment: "Evidence card, vitamin C: timing and food.")
            )
        case .zinc:
            return Texts(
                purpose: String(localized: "Needed by the immune system, the skin and many enzymes. Endurance athletes and people who eat little meat may run low.", bundle: .module, comment: "Evidence card, zinc: what it is for."),
                dose: String(localized: "Typically 5–25 mg a day from supplements.", bundle: .module, comment: "Evidence card, zinc: typical dose."),
                timing: String(localized: "Apart from iron and calcium supplements, which compete for absorption. With food if it upsets your stomach.", bundle: .module, comment: "Evidence card, zinc: timing and food.")
            )
        case .omega3EPA_DHA:
            return Texts(
                purpose: String(localized: "Fatty acids from fish or algae that support the heart and brain. Useful if you rarely eat oily fish.", bundle: .module, comment: "Evidence card, omega-3: what it is for."),
                dose: String(localized: "Commonly 250–2000 mg of EPA and DHA combined a day. Count EPA + DHA, not the total amount of oil.", bundle: .module, comment: "Evidence card, omega-3: typical dose."),
                timing: String(localized: "With a meal that contains fat.", bundle: .module, comment: "Evidence card, omega-3 and vitamin K2: timing and food.")
            )
        case .vitaminB12:
            return Texts(
                purpose: String(localized: "Needed for blood formation and the nervous system. Essential for vegans, because plant foods don't provide it.", bundle: .module, comment: "Evidence card, vitamin B12: what it is for."),
                dose: String(localized: "Typically 4–1000 µg a day; only a small share of a large dose is absorbed.", bundle: .module, comment: "Evidence card, vitamin B12: typical dose."),
                timing: String(localized: "Any time of day.", bundle: .module, comment: "Evidence card: the ingredient can be taken at any time.")
            )
        case .iron:
            return Texts(
                purpose: String(localized: "Carries oxygen in the blood. Take it only when a blood test shows low iron: too much is harmful.", bundle: .module, comment: "Evidence card, iron: what it is for."),
                dose: String(localized: "As advised after a blood test.", bundle: .module, comment: "Evidence card, iron: typical dose."),
                timing: String(localized: "Apart from coffee, tea, calcium and zinc. Vitamin C helps absorption.", bundle: .module, comment: "Evidence card, iron: timing and food.")
            )
        case .selenium:
            return Texts(
                purpose: String(localized: "Part of antioxidant enzymes and needed by the thyroid. Central European soils contain little of it.", bundle: .module, comment: "Evidence card, selenium: what it is for."),
                dose: String(localized: "Typically 50–200 µg a day. The gap between enough and too much is small.", bundle: .module, comment: "Evidence card, selenium: typical dose."),
                timing: String(localized: "Any time, with food.", bundle: .module, comment: "Evidence card, selenium: timing and food.")
            )
        case .vitaminB6:
            return Texts(
                purpose: String(localized: "Supports protein metabolism and the nervous system. A normal diet rarely falls short.", bundle: .module, comment: "Evidence card, vitamin B6: what it is for."),
                dose: String(localized: "Typically 1–10 mg a day; high doses over a long time can harm the nerves.", bundle: .module, comment: "Evidence card, vitamin B6: typical dose."),
                timing: String(localized: "Any time of day.", bundle: .module, comment: "Evidence card: the ingredient can be taken at any time.")
            )
        case .caffeine:
            return Texts(
                purpose: String(localized: "Improves alertness and both endurance and strength performance for many people.", bundle: .module, comment: "Evidence card, caffeine: what it is for."),
                dose: String(localized: "About 3–6 mg per kg of body weight before exercise (roughly 100–400 mg); smaller doses help too.", bundle: .module, comment: "Evidence card, caffeine: typical dose."),
                timing: String(localized: "30–60 minutes before exercise. Skip the late afternoon and evening if it disturbs your sleep.", bundle: .module, comment: "Evidence card, caffeine: timing and food.")
            )
        case .betaAlanine:
            return Texts(
                purpose: String(localized: "Buffers acid in the muscles and can help in hard efforts of about 1–4 minutes.", bundle: .module, comment: "Evidence card, beta-alanine: what it is for."),
                dose: String(localized: "3.2–6.4 g a day in split doses, for at least 2–4 weeks.", bundle: .module, comment: "Evidence card, beta-alanine: typical dose."),
                timing: String(localized: "Split into smaller doses with meals to limit the harmless tingling it can cause.", bundle: .module, comment: "Evidence card, beta-alanine: timing and food.")
            )
        case .sodium:
            return Texts(
                purpose: String(localized: "The main electrolyte lost in sweat. Replacing it matters in long or hot sessions.", bundle: .module, comment: "Evidence card, sodium: what it is for."),
                dose: String(localized: "Depends on your sweat losses; often 300–1000 mg per hour of long exercise.", bundle: .module, comment: "Evidence card, sodium: typical dose."),
                timing: String(localized: "During and after long or hot sessions, with fluids.", bundle: .module, comment: "Evidence card, sodium: timing and food.")
            )
        case .potassium:
            return Texts(
                purpose: String(localized: "An electrolyte for muscle and nerve function. Fruit, vegetables and potatoes are the main sources.", bundle: .module, comment: "Evidence card, potassium: what it is for."),
                dose: String(localized: "Small amounts in electrolyte drinks; large doses from supplements only on medical advice.", bundle: .module, comment: "Evidence card, potassium: typical dose."),
                timing: String(localized: "With fluids, during or after exercise.", bundle: .module, comment: "Evidence card, potassium: timing and food.")
            )
        case .vitaminK2:
            return Texts(
                purpose: String(localized: "Supports blood clotting and bone health; often combined with vitamin D. If you take blood thinners, ask your doctor first.", bundle: .module, comment: "Evidence card, vitamin K2: what it is for."),
                dose: String(localized: "Typically 45–200 µg a day.", bundle: .module, comment: "Evidence card, vitamin K2: typical dose."),
                timing: String(localized: "With a meal that contains fat.", bundle: .module, comment: "Evidence card, omega-3 and vitamin K2: timing and food.")
            )
        default:
            return Texts(purpose: "", dose: "", timing: "")
        }
    }

    static func limitNote(of ingredient: IngredientID) -> String? {
        switch ingredient {
        case .creatine:
            return String(localized: "No EU upper limit set. EFSA (2004) considers 3 g a day unlikely to pose a risk; studies commonly use 3–5 g.", bundle: .module, comment: "Evidence card, creatine: note on the limit.")
        case .magnesium:
            return String(localized: "Counts magnesium from supplements only (readily dissociable salts and oxide); magnesium in food is not included.", bundle: .module, comment: "Evidence card, magnesium: the EFSA limit applies to supplemental magnesium only.")
        case .vitaminC:
            return String(localized: "No EU upper limit set. The US figure is 2000 mg a day.", bundle: .module, comment: "Evidence card, vitamin C: no EU limit; the US tolerable upper intake level, labelled as US.")
        case .omega3EPA_DHA:
            return String(localized: "No EU upper limit set. EFSA (2012): up to 5 g a day from supplements raises no safety concern.", bundle: .module, comment: "Evidence card, omega-3: note on the limit.")
        case .iron:
            return String(localized: "EFSA's safe level of intake, not a formal upper limit.", bundle: .module, comment: "Evidence card, iron: the 40 mg figure is a safe level, not an upper limit.")
        case .caffeine:
            return String(localized: "EFSA (2015): up to 400 mg a day, and up to 200 mg at once, raises no safety concern for healthy adults. Coffee counts too, but only what you log here is added up.", bundle: .module, comment: "Evidence card, caffeine: note on the limit.")
        default:
            return nil
        }
    }
}
