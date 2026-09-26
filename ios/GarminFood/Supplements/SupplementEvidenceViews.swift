// SupplementEvidenceViews.swift
//
// add-supplements task 3.5 (design D7/D8): the evidence cards and the label
// score.
// - `SupplementEvidenceListView`: every ingredient's card; then each
//   product in the stack with its label score.
// - `EvidenceCardView`: what it's for, evidence strength, typical dose,
//   timing, the upper limit (or "No EU upper limit set", with the US
//   figure labelled as US), sources with links, and the disclaimer. The
//   texts are the app's own (FoodLogCore `EvidenceCatalog`, en + cs).
// - `LabelScoreView`: the 0–100 score ALWAYS with its breakdown --
//   transparency 40, dose 40, headroom 20 -- and each finding in words,
//   never a bare number (D7). Then "Verify certification": links to the
//   certifiers' public search pages, and the badge the user sets by hand.
//
// There's no usable free external rating (D7), so the app claims none.
// Certification is per batch, which is why it stays a manual check.
//
// Depends on: SupplementsController, FoodLogCore (EvidenceCatalog,
// LabelScore). Depended on by: SupplementsView, SupplementProductEditorView
// (certifier names).

import SwiftUI
import FoodLogCore

@MainActor
struct SupplementEvidenceListView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let supplements = environment.supplements
        List {
            if !supplements.stack.isEmpty {
                Section {
                    ForEach(supplements.stack) { product in
                        NavigationLink {
                            LabelScoreView(product: product)
                        } label: {
                            HStack {
                                Text(verbatim: product.name)
                                Spacer()
                                Text(verbatim: "\(supplements.labelScore(product).total)/100")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Label score")
                }
            }
            Section {
                ForEach(EvidenceCatalog.all) { card in
                    NavigationLink {
                        EvidenceCardView(card: card)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: card.name)
                            Text(verbatim: card.strength.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Ingredients")
            } footer: {
                Text(verbatim: EvidenceCatalog.disclaimer)
            }
        }
        .navigationTitle("Evidence")
    }
}

struct EvidenceCardView: View {
    let card: EvidenceCard

    var body: some View {
        List {
            Section {
                Text(verbatim: card.purpose)
                LabeledContent(String(localized: "Evidence"), value: card.strength.title)
            }
            Section {
                Text(verbatim: card.typicalDose)
                Text(verbatim: card.timing)
            } header: {
                Text("Dose and timing")
            }
            Section {
                if let value = card.limit.value {
                    LabeledContent(limitTitle, value: SupplementFormat.amount(value, unit: card.unit))
                } else {
                    Text(verbatim: EvidenceCatalog.noEUUpperLimitText)
                }
                if let single = card.limit.singleDose {
                    LabeledContent(String(localized: "Single dose"), value: SupplementFormat.amount(single, unit: card.unit))
                }
                if let us = card.limit.usFigure {
                    LabeledContent(String(localized: "US figure"), value: SupplementFormat.amount(us, unit: card.unit))
                }
                if let note = card.limitNote {
                    Text(verbatim: note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Upper limit")
            }
            Section {
                ForEach(card.sources, id: \.self) { source in
                    Link(destination: source.url) {
                        Label(source.title, systemImage: "link")
                    }
                }
            } header: {
                Text("Sources")
            } footer: {
                Text(verbatim: EvidenceCatalog.disclaimer)
            }
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var limitTitle: String {
        switch card.limit.kind {
        case .upperLimit: return String(localized: "Upper limit (adults)")
        case .safeLevel: return String(localized: "Safe level (not a formal limit)")
        case .noEUUpperLimit: return EvidenceCatalog.noEUUpperLimitText
        }
    }
}

@MainActor
struct LabelScoreView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    let product: SupplementProduct

    var body: some View {
        let score = environment.supplements.labelScore(product)
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "\(score.total)")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                    Text(verbatim: "/ 100")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } footer: {
                Text("A check of the label, not a test of the product: are the amounts stated, is the dose in the range studies use, and does it leave room under your limits?", comment: "Label score: what the number means.")
            }
            partSection(String(localized: "Label transparency"), score.transparency)
            partSection(String(localized: "Dose against the evidence"), score.dose)
            partSection(String(localized: "Room under your limits"), score.headroom)

            Section {
                ForEach(SupplementCertificationLinks.bodies, id: \.self) { body in
                    Button {
                        openURL(SupplementCertificationLinks.searchPage(body))
                    } label: {
                        HStack {
                            Text(verbatim: SupplementCertificationLinks.name(body))
                            Spacer()
                            if product.certifications?.contains(where: { $0.body == body }) == true {
                                Label("You checked it", systemImage: "checkmark.seal.fill")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(Theme.success)
                            }
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Verify certification")
            } footer: {
                Text("Opens the certifier's own search page. Certification is per batch, so look up your product there, then tick it in the product's settings.", comment: "Label score: footer under the certification links.")
            }
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func partSection(_ title: String, _ part: LabelScore.Part) -> some View {
        Section {
            ForEach(Array(part.findings.enumerated()), id: \.offset) { item in
                Text(verbatim: Self.text(item.element))
                    .font(.subheadline)
            }
        } header: {
            HStack {
                Text(verbatim: title)
                Spacer()
                Text(verbatim: "\(part.points)/\(part.maximum)")
                    .monospacedDigit()
            }
        }
    }

    static func text(_ finding: LabelScore.Finding) -> String {
        switch finding {
        case .noIngredients:
            return String(localized: "No ingredients entered yet.", comment: "Label score finding.")
        case .allAmountsStated:
            return String(localized: "Every ingredient has an amount.", comment: "Label score finding.")
        case .amountMissing(let id):
            return String(localized: "\(EvidenceCatalog.name(of: id)): no amount on the label.", comment: "Label score finding. %@ = ingredient.")
        case .formMissing(let id):
            return String(localized: "\(EvidenceCatalog.name(of: id)): the form isn't stated.", comment: "Label score finding (e.g. which magnesium salt). %@ = ingredient.")
        case .proprietaryBlend(let name):
            return String(localized: "Proprietary blend \(name): amounts hidden.", comment: "Label score finding. %@ = blend name.")
        case .withinRange(let id):
            return String(localized: "\(EvidenceCatalog.name(of: id)): in the range studies use.", comment: "Label score finding. %@ = ingredient.")
        case .belowRange(let id):
            return String(localized: "\(EvidenceCatalog.name(of: id)): below the range studies use.", comment: "Label score finding. %@ = ingredient.")
        case .aboveRange(let id):
            return String(localized: "\(EvidenceCatalog.name(of: id)): above the range studies use.", comment: "Label score finding. %@ = ingredient.")
        case .noReferenceRange(let id):
            return String(localized: "\(EvidenceCatalog.name(of: id)): no reference range to compare with.", comment: "Label score finding. %@ = ingredient.")
        case .underLimits:
            return String(localized: "Your planned dose stays under your limits.", comment: "Label score finding.")
        case .overLimit(let id):
            return String(localized: "\(EvidenceCatalog.name(of: id)): your planned total goes over your limit.", comment: "Label score finding. %@ = ingredient.")
        }
    }
}

/// The three certifiers the design names (D7), linked only to their public
/// search pages (no scraping, no API).
enum SupplementCertificationLinks {
    static let bodies: [CertificationBody] = [.nsfCertifiedForSport, .informedSport, .koelnerListe]

    static func name(_ body: CertificationBody) -> String {
        switch body {
        case .nsfCertifiedForSport: return "NSF Certified for Sport"
        case .informedSport: return "Informed Sport"
        case .koelnerListe: return "Kölner Liste"
        default: return body.rawValue
        }
    }

    static func searchPage(_ body: CertificationBody) -> URL {
        switch body {
        case .nsfCertifiedForSport: return URL(string: "https://www.nsfsport.com/certified-products/")!
        case .informedSport: return URL(string: "https://sport.wetestyoutrust.com/")!
        case .koelnerListe: return URL(string: "https://www.koelnerliste.com/en/")!
        default: return URL(string: "https://www.nsfsport.com/")!
        }
    }
}
