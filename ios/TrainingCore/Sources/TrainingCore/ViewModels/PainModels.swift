// PainModels.swift
//
// The morning pain step and the pain shown on Today and in Plan
// (add-checkin-pain-score design D5, D6), as pure models:
//
//   - `PainDraft`: the rows the owner is editing -- one per site, a score
//     0-10 in half steps, a short note for "other". It does the rounding,
//     the add/remove rules, the default sites and the `pains` payload, so
//     the app's view only draws it and holds it as state.
//   - `PainStepModel`: the step under the check-in row, non-nil once the
//     day has a chosen light (`CheckInRowModel.pain`). Open while the day's
//     pain is not asked yet; else folded to "Edit pain". Its draft starts
//     from the recorded answer, or from the default sites at 0 -- the
//     Achilles sites of the latest earlier day that scored one, else the
//     left Achilles -- so one tap on Save confirms "0". Save builds the
//     same check-in as the row (date, light, session, option) plus `pains`,
//     which replaces the day's answer (the vault's rule, CheckInOverlay).
//   - `TrainingFormatting.painLine` ("Pain: Achilles (left) 4.5/10 ·
//     Knee (right) 1/10", or "Pain: none") for Today's card, and
//     `painTags` for the Plan day rows.
//
// The phone never computes the pain flags: `pain-rising` / `pain-high`
// come from the vault as week rule notes. Nothing here is about anyone in
// particular: the defaults come from what was recorded.
//
// Depended on by: CheckInModels (the row), TodayTrainingModel (painLine),
// PlanModels (painTags), the app's CheckInRowView. Tests: PainTests.

import Foundation

// MARK: - Draft

public struct PainDraftRow: Equatable, Sendable, Identifiable {
    public var site: PainSite
    /// 0...10, a multiple of 0.5.
    public var score: Double
    /// Only sent for a non-blank note (trimmed, at most 200 UTF-16 units).
    public var note: String

    public var id: PainSite { site }

    public init(site: PainSite, score: Double = 0, note: String = "") {
        self.site = site
        self.score = PainDraft.rounded(score)
        self.note = note
    }
}

public struct PainDraft: Equatable, Sendable {
    /// The order sites are offered in.
    public static let siteOrder: [PainSite] = [.achillesLeft, .achillesRight, .kneeLeft, .kneeRight, .other]
    /// When nothing was scored before (design D5).
    public static let fallbackSites: [PainSite] = [.achillesLeft]

    public private(set) var rows: [PainDraftRow]

    public init(rows: [PainDraftRow] = []) {
        var seen = Set<PainSite>()
        self.rows = rows.filter { seen.insert($0.site).inserted }
    }

    /// A recorded answer: one row per site (the highest score when a site
    /// was recorded twice, as the vault reads it), in the recorded order.
    public init(entries: [PainEntry]) {
        var rows: [PainDraftRow] = []
        for entry in entries {
            if let index = rows.firstIndex(where: { $0.site == entry.site }) {
                if entry.score > rows[index].score { rows[index].score = PainDraft.rounded(entry.score) }
                if rows[index].note.isEmpty, let note = entry.note { rows[index].note = note }
            } else {
                rows.append(PainDraftRow(site: entry.site, score: entry.score, note: entry.note ?? ""))
            }
        }
        self.rows = rows
    }

    /// `sites` at 0.
    public static func zeros(_ sites: [PainSite]) -> PainDraft {
        PainDraft(rows: sites.map { PainDraftRow(site: $0) })
    }

    /// The Achilles sites of the latest day before `date` whose pain had an
    /// Achilles entry, in the offered order; else the left Achilles.
    public static func defaultSites(before date: LocalDate, plan: EffectivePlan?) -> [PainSite] {
        let days = (plan?.weeks ?? []).flatMap(\.days).filter { $0.date < date }.sorted { $0.date > $1.date }
        for day in days {
            let achilles = Set((day.pains ?? []).map(\.site).filter(\.isAchilles))
            if !achilles.isEmpty {
                return siteOrder.filter { achilles.contains($0) }
            }
        }
        return fallbackSites
    }

    /// Nearest half step, clamped to 0...10.
    public static func rounded(_ score: Double) -> Double {
        guard score.isFinite else { return 0 }
        let clamped = min(max(score, PainEntry.scoreRange.lowerBound), PainEntry.scoreRange.upperBound)
        return (clamped * 2).rounded() / 2
    }

    /// Sites not in the draft yet, in the offered order.
    public var addableSites: [PainSite] {
        Self.siteOrder.filter { site in !rows.contains { $0.site == site } }
    }

    public var isEmpty: Bool { rows.isEmpty }

    /// Adds `site` at 0; nothing if it is already there.
    public mutating func add(_ site: PainSite) {
        guard !rows.contains(where: { $0.site == site }) else { return }
        rows.append(PainDraftRow(site: site))
    }

    public mutating func remove(_ site: PainSite) {
        rows.removeAll { $0.site == site }
    }

    public mutating func setScore(_ score: Double, for site: PainSite) {
        guard let index = rows.firstIndex(where: { $0.site == site }) else { return }
        rows[index].score = Self.rounded(score)
    }

    public mutating func setNote(_ note: String, for site: PainSite) {
        guard let index = rows.firstIndex(where: { $0.site == site }) else { return }
        rows[index].note = note
    }

    /// The contract's `pains`: every row, notes trimmed and cut to 200
    /// UTF-16 units, a blank note left out. `[]` when every row was
    /// removed ("asked, nothing hurts").
    public var entries: [PainEntry] {
        rows.map { row in
            PainEntry(site: row.site, score: Self.rounded(row.score), note: Self.cleanNote(row.note))
        }
    }

    static func cleanNote(_ note: String) -> String? {
        var text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.utf16.count > PainEntry.noteMaxLength { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

// MARK: - The step

public struct PainStepModel: Equatable, Sendable {
    public let date: LocalDate
    public let light: MorningLight
    public let sessionID: String?
    /// The day's pain is recorded (the phone's or the vault's answer).
    public let isRecorded: Bool
    /// Open under the lights (not asked yet); else folded to `editTitle`.
    public var opensExpanded: Bool { !isRecorded }
    /// "Saved on phone" / "Sent" / "Received by the vault" for the phone's
    /// own answer.
    public let deliveryLine: String?
    /// Where the editor starts: the recorded answer, else the defaults at 0.
    public let draft: PainDraft

    public let title: String
    public let hint: String
    public let saveTitle: String
    public let notNowTitle: String
    public let editTitle: String
    public let addSiteTitle: String
    public let notePlaceholder: String
    public let nothingHurtsText: String
    /// Every site's label ("Achilles (left)").
    public let siteNames: [PainSite: String]
    /// VoiceOver for each site's remove button ("Remove Achilles (left)").
    public let removeLabels: [PainSite: String]
    /// "0/10" ... "10/10" by half step (index = score x 2).
    public let scoreTexts: [String]
    /// VoiceOver values, "4.5 of 10", by half step.
    public let scoreAccessibilityValues: [String]

    public func siteName(_ site: PainSite) -> String {
        siteNames[site] ?? site.rawValue
    }

    public func scoreText(_ score: Double) -> String {
        Self.lookup(scoreTexts, score)
    }

    public func scoreAccessibilityValue(_ score: Double) -> String {
        Self.lookup(scoreAccessibilityValues, score)
    }

    private static func lookup(_ texts: [String], _ score: Double) -> String {
        let index = Int(PainDraft.rounded(score) * 2)
        return texts.indices.contains(index) ? texts[index] : ""
    }

    /// The check-in Save records: the row's date, light, session and
    /// option, plus the draft's `pains` (replacing the day's answer).
    public func payload(_ draft: PainDraft) -> MorningCheckInPayload {
        MorningCheckInPayload(date: date, light: light, sessionId: sessionID, pains: draft.entries)
    }
}

// MARK: - Text

public extension TrainingFormatting {
    func painSiteName(_ site: PainSite) -> String {
        switch site {
        case .achillesLeft: return text(.painSiteAchillesLeft)
        case .achillesRight: return text(.painSiteAchillesRight)
        case .kneeLeft: return text(.painSiteKneeLeft)
        case .kneeRight: return text(.painSiteKneeRight)
        case .other: return text(.painSiteOther)
        }
    }

    /// "4.5/10" (Czech "4,5/10").
    func painScoreText(_ score: Double) -> String {
        text.format(.painScore, NumberText.decimal(score, language))
    }

    /// "Achilles (left) 4.5/10"; another site with its note in brackets.
    func painTag(_ entry: PainEntry) -> String {
        let site = painSiteName(entry.site)
        let score = NumberText.decimal(entry.score, language)
        if entry.site == .other, let note = entry.note, !note.isEmpty {
            return text.format(.painTagNote, site, score, note)
        }
        return text.format(.painTag, site, score)
    }

    /// One tag per recorded entry; `[]` when not asked or nothing hurts.
    func painTags(_ pains: [PainEntry]?) -> [String] {
        (pains ?? []).map(painTag)
    }

    /// "Pain: Achilles (left) 4.5/10 · Knee (right) 1/10", "Pain: none",
    /// or `nil` when not asked.
    func painLine(_ pains: [PainEntry]?) -> String? {
        guard let pains else { return nil }
        if pains.isEmpty { return text(.painNone) }
        return text.format(.painLine, painTags(pains).joined(separator: " · "))
    }
}

extension TodayTrainingBuilder {
    /// The pain step for the row's day: `nil` without a chosen light.
    func painStep(on date: LocalDate, light: MorningLight?, sessionID: String?, snapshot: TrainingSnapshot) -> PainStepModel? {
        guard let light, let plan = snapshot.plan else { return nil }
        let recorded = plan.day(date)?.pains
        let draft = recorded.map { PainDraft(entries: $0) }
            ?? PainDraft.zeros(PainDraft.defaultSites(before: date, plan: plan))
        let text = format.text
        var names: [PainSite: String] = [:]
        var removes: [PainSite: String] = [:]
        for site in PainSite.allCases {
            let name = format.painSiteName(site)
            names[site] = name
            removes[site] = text.format(.painRemoveSite, name)
        }
        let steps = (0...20).map { Double($0) / 2 }
        return PainStepModel(
            date: date,
            light: light,
            sessionID: sessionID,
            isRecorded: recorded != nil,
            deliveryLine: format.deliveryLine(snapshot.checkIns.pains(on: date)?.delivery),
            draft: draft,
            title: text(.painTitle),
            hint: text(.painHint),
            saveTitle: text(.painSave),
            notNowTitle: text(.painNotNow),
            editTitle: text(.painEdit),
            addSiteTitle: text(.painAddSite),
            notePlaceholder: text(.painNotePlaceholder),
            nothingHurtsText: text(.painNothingHurts),
            siteNames: names,
            removeLabels: removes,
            scoreTexts: steps.map(format.painScoreText),
            scoreAccessibilityValues: steps.map { text.format(.a11yPainValue, NumberText.decimal($0, format.language)) }
        )
    }
}
