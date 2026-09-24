// RecordsView.swift
//
// add-journeys-and-records design D9: the Garmin-style personal-records
// list -- per record its value, the day it was set, the previous best, and
// a trophy on a PR from the last 7 days -- followed by the last PRs
// announced. Records without data are hidden (never shown as zero).
//
// Thin: everything comes from `PersonalRecordsFeature` (Gamification,
// unit-tested); record names arrive already localized, hence
// `Text(verbatim:)` for them. Days are `yyyy-MM-dd` keys, formatted here
// for display only.
//
// Depends on: AppEnvironment, PersonalRecordsFeature, PersonalRecordFormat,
// SectionHeader, Theme.
// Depended on by: RecordsSlotView.

import SwiftUI
import Gamification

@MainActor
struct RecordsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var records: [PersonalRecordStatus] = []
    @State private var recent: [PersonalRecordEvent] = []

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }
    private var visible: [PersonalRecordStatus] { records.filter(\.isVisible) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                if visible.isEmpty {
                    Text("No records yet. Keep logging and they will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .card()
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(visible) { record in
                            RecordRow(record: record)
                        }
                    }
                    .card()
                }

                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(title: String(localized: "Recent PRs"))
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            ForEach(recent) { event in
                                RecentPRRow(event: event)
                            }
                        }
                        .card()
                    }
                }

                Text("A new PR is announced once a record has 7 days of data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle(Text("Personal records"))
        .task(id: featureHost?.summaries[PersonalRecordsFeature.id]) {
            await reload()
        }
    }

    private func reload() async {
        guard let feature = featureHost?.feature(PersonalRecordsFeature.self) else { return }
        records = await feature.records()
        recent = await feature.recentRecords()
    }
}

/// "24 Sep 2026" for a `yyyy-MM-dd` key (the key itself if unparsable).
func recordDayText(_ day: String?) -> String {
    guard let day else { return "" }
    let parser = DateFormatter()
    parser.calendar = Calendar(identifier: .gregorian)
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: day) else { return day }
    return date.formatted(.dateTime.day().month(.abbreviated).year())
}

private struct RecordRow: View {
    let record: PersonalRecordStatus

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: record.definition.symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: record.definition.name)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: recordDayText(record.day))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let previous = record.previousValueText {
                    Text("Previous best: \(previous) (\(recordDayText(record.previousDay)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            HStack(spacing: Theme.Spacing.xs) {
                if record.isRecentPR {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(Theme.warning)
                        .accessibilityLabel(Text("Recent PR"))
                }
                Text(verbatim: record.valueText ?? "")
                    .font(.headline.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecentPRRow: View {
    let event: PersonalRecordEvent

    private var definition: PersonalRecordDefinition? {
        event.recordId.flatMap(PersonalRecordId.init(rawValue:)).map(PersonalRecordCatalog.definition)
    }

    var body: some View {
        if let definition, let value = event.value {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: definition.name)
                        .font(.subheadline)
                    Text(verbatim: recordDayText(event.day))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Spacing.xs)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: PersonalRecordFormat.value(value, unit: definition.unit))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    if let previous = event.previousValue {
                        Text("was \(PersonalRecordFormat.value(previous, unit: definition.unit))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
