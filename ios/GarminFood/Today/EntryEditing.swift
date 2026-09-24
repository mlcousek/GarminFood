// EntryEditing.swift
//
// add-log-entry-editing, the UI half (tasks 3.1-3.4): what a logged entry
// row can do besides being looked at -- Edit (amount + meal), Move to
// another meal, Duplicate, Delete -- plus "Copy from…", which re-logs a
// past day's meal. Shared by `TodayView`'s meal cards and `MealDetailView`
// so the two screens can't drift apart.
//
// Why an `@Observable` `EntryEditor` object rather than per-view `@State`:
// the rows that start an action (`entryActions`) and the sheets/dialogs
// that finish it (`entryEditing`) sit at different levels of the view tree,
// and both screens need the same set. The host view owns one editor and
// applies `entryEditing(_:)` once; every row gets `entryActions(_:editor:)`.
//
// Swipe actions only exist inside a `List` (`MealDetailView`); the Today
// cards are a plain stack, so there the same actions come from a tap
// (edit) and the long-press context menu. VoiceOver gets them all as
// custom actions on both screens (task 3.4).
//
// Everything here commits locally through `AppEnvironment` ->
// `LogEntryCoordinator` and returns at once; Garmin delivery happens in
// the background (design D1/D3). The only network wait is
// `CopyMealSheet` reading the source day, which is a preview, not a
// confirm path.
//
// Depends on: AppEnvironment (editEntry/duplicateEntry/delete/
// copyMealPlan/copyMeal), FoodLogCore (MealEntry, CopyMealPlan,
// LogEntryEditError), GarminKit's MealType.

import SwiftUI
import FoodLogCore
import GarminKit

// MARK: - Editor state

/// A meal "Copy from…" copies INTO; `Identifiable` for `.sheet(item:)`.
struct CopyMealTarget: Identifiable, Equatable {
    let mealType: MealType
    var id: String { mealType.rawValue }
}

@MainActor
@Observable
final class EntryEditor {
    var editTarget: MealEntry?
    var pendingDelete: MealEntry?
    var copyTarget: CopyMealTarget?
    /// The row an action is running for, dimmed until it finishes.
    var busyEntryId: String?
    var errorMessage: String?
}

extension View {
    /// Row side: swipe (inside a List), context menu and VoiceOver actions.
    func entryActions(_ entry: MealEntry, editor: EntryEditor) -> some View {
        modifier(EntryActionsModifier(entry: entry, editor: editor))
    }

    /// Host side: the sheets, delete confirmation and error alert. Apply
    /// once per screen, on a view that outlives the rows.
    func entryEditing(_ editor: EntryEditor) -> some View {
        modifier(EntryEditingPresenter(editor: editor))
    }
}

// MARK: - Row actions

@MainActor
private struct EntryActionsModifier: ViewModifier {
    let entry: MealEntry
    let editor: EntryEditor

    @Environment(AppEnvironment.self) private var environment

    func body(content: Content) -> some View {
        content
            .opacity(editor.busyEntryId == entry.id ? 0.4 : 1)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    editor.pendingDelete = entry
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                if entry.canRelog {
                    Button {
                        editor.editTarget = entry
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                    .tint(Theme.accent)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if entry.canRelog {
                    Button {
                        duplicate()
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(Theme.success)
                }
            }
            .contextMenu {
                if entry.canRelog {
                    Button {
                        editor.editTarget = entry
                    } label: {
                        Label("Edit amount", systemImage: "slider.horizontal.3")
                    }
                    Menu {
                        ForEach(otherMeals, id: \.self) { meal in
                            Button {
                                move(to: meal)
                            } label: {
                                Label(meal.displayName, systemImage: meal.symbolName)
                            }
                        }
                    } label: {
                        Label("Move to", systemImage: "arrow.right.square")
                    }
                    Button {
                        duplicate()
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                }
                Button(role: .destructive) {
                    editor.pendingDelete = entry
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .accessibilityActions {
                if entry.canRelog {
                    Button("Edit") { editor.editTarget = entry }
                    ForEach(otherMeals, id: \.self) { meal in
                        Button("Move to \(meal.displayName)") { move(to: meal) }
                    }
                    Button("Duplicate") { duplicate() }
                }
                Button("Delete") { editor.pendingDelete = entry }
            }
    }

    private var otherMeals: [MealType] {
        MealType.dashboardOrder.filter { $0 != entry.mealType }
    }

    private func duplicate() {
        run { try await environment.duplicateEntry(entry) }
    }

    private func move(to meal: MealType) {
        run { try await environment.editEntry(entry, newQuantity: entry.servingQty, newMeal: meal) }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard editor.busyEntryId == nil else { return }
        editor.busyEntryId = entry.id
        Task { @MainActor in
            defer { editor.busyEntryId = nil }
            do {
                try await action()
                Haptics.success()
            } catch {
                editor.errorMessage = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}

// MARK: - Host: sheets and dialogs

@MainActor
private struct EntryEditingPresenter: ViewModifier {
    @Bindable var editor: EntryEditor

    @Environment(AppEnvironment.self) private var environment

    func body(content: Content) -> some View {
        content
            .sheet(item: $editor.editTarget) { entry in
                EditEntrySheet(entry: entry)
            }
            .sheet(item: $editor.copyTarget) { target in
                CopyMealSheet(mealType: target.mealType)
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: Binding(
                    get: { editor.pendingDelete != nil },
                    set: { if !$0 { editor.pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: editor.pendingDelete
            ) { entry in
                Button("Delete \(entry.name)", role: .destructive) {
                    delete(entry)
                }
            } message: { entry in
                Text(entry.isSynced
                     ? "It will also be removed from Garmin Connect."
                     : "It hasn't reached Garmin yet, so it's only removed from this phone.")
            }
            .alert(
                "Couldn't change this entry",
                isPresented: Binding(
                    get: { editor.errorMessage != nil },
                    set: { if !$0 { editor.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(editor.errorMessage ?? "")
            }
    }

    private func delete(_ entry: MealEntry) {
        editor.busyEntryId = entry.id
        Task { @MainActor in
            defer { editor.busyEntryId = nil }
            do {
                try await environment.delete(entry)
                Haptics.success()
            } catch {
                editor.errorMessage = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}

// MARK: - Edit sheet

/// Amount and meal, the two fields the owner asked to be editable (serving
/// and day stay as logged). Saving a synced entry queues a replace: Garmin
/// gets the corrected entry, then the old one is deleted (design D1).
@MainActor
struct EditEntrySheet: View {
    let entry: MealEntry

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    /// The multiplier of the logged serving (`servingQty`); `nil` while the
    /// typed text isn't valid. Typed in grams when the serving states its
    /// size (`ServingQuantityField`, amount-in-grams).
    @State private var quantity: Double?
    @State private var meal: MealType
    @FocusState private var isAmountFieldFocused: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(entry: MealEntry) {
        self.entry = entry
        _quantity = State(initialValue: entry.servingQty)
        _meal = State(initialValue: entry.mealType ?? .breakfast)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.headline)
                        if let serving = entry.servingDescription {
                            Text("Serving: \(serving)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Amount") {
                    // Same field as the confirm screen: grams for a serving
                    // with a known size, servings otherwise; shows its own
                    // out-of-range message.
                    ServingQuantityField(
                        serving: entry.serving,
                        quantity: $quantity,
                        isFocused: $isAmountFieldFocused,
                        fallbackServingLabel: entry.servingDescription,
                        showsStepper: true
                    )
                    if let quantity, let calories = entry.calories(forQuantity: quantity) {
                        LabeledContent("Calories", value: "\(calories.wholeNumberText) kcal")
                            .monospacedDigit()
                    }
                }

                Section("Meal") {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.dashboardOrder, id: \.self) { type in
                            Label(type.displayName, systemImage: type.symbolName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if entry.isSynced {
                    Section {
                        Text("Garmin Connect gets the corrected entry first, then the old one is removed. Until then it may briefly show both.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isAmountFieldFocused = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var hasChanged: Bool {
        guard let quantity else { return true }
        return abs(quantity - entry.servingQty) > 0.0001 || meal != entry.mealType
    }

    private var canSave: Bool {
        !isSaving && hasChanged && (quantity.map(LogQuantity.isValid) ?? false)
    }

    private func save() {
        guard let quantity else { return }
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await environment.editEntry(entry, newQuantity: quantity, newMeal: meal)
                Haptics.success()
                dismiss()
            } catch LogEntryEditError.noChange {
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}

// MARK: - Copy from…

/// Re-logs items from a past day's meal into `mealType` on the day being
/// viewed (design D4). Yesterday by default; any past day and any of its
/// meals can be picked. Quick adds (calories only) are listed but can't be
/// copied -- they have no food to log again.
@MainActor
struct CopyMealSheet: View {
    let mealType: MealType

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var sourceDate: Date
    @State private var sourceMeal: MealType
    @State private var plan: CopyMealPlan?
    @State private var selected: Set<String> = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isSaving = false
    @State private var saveError: String?

    init(mealType: MealType) {
        self.mealType = mealType
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        _sourceDate = State(initialValue: yesterday)
        _sourceMeal = State(initialValue: mealType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Copy from") {
                    DatePicker("Day", selection: $sourceDate, in: ...Date(), displayedComponents: .date)
                    Picker("Meal", selection: $sourceMeal) {
                        ForEach(MealType.dashboardOrder, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section("Items") {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Reading that day from Garmin…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let loadError {
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    } else if let plan {
                        if plan.isEmpty {
                            Text("Nothing logged in \(sourceMeal.displayName.lowercased()) that day.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(plan.copyable) { item in
                            copyableRow(item)
                        }
                        ForEach(plan.notCopyable) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .foregroundStyle(.secondary)
                                Text(item.reason)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
            .navigationTitle("Copy to \(mealType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Copy" : "Copy \(selected.count)") { copy() }
                        .disabled(selected.isEmpty || isSaving)
                }
            }
            .task(id: loadKey) {
                await load()
            }
        }
    }

    private func copyableRow(_ item: CopyableMealItem) -> some View {
        let isOn = selected.contains(item.id)
        return Button {
            if isOn {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
            Haptics.selection()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .lineLimit(2)
                    Text(detail(item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                if let calories = item.calories {
                    Text("\(calories.wholeNumberText) kcal")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func detail(_ item: CopyableMealItem) -> String {
        let quantity = item.servingQty.formattedQuantity
        guard let serving = item.servingDescription else { return "\(quantity) ×" }
        return "\(quantity) × \(serving)"
    }

    private var loadKey: String {
        "\(NutritionDate.string(from: sourceDate))|\(sourceMeal.rawValue)"
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let result = try await environment.copyMealPlan(from: sourceDate, mealType: sourceMeal)
            if Task.isCancelled { return }
            plan = result
            selected = Set(result.copyable.map(\.id))
        } catch {
            if Task.isCancelled { return }
            plan = nil
            selected = []
            loadError = "Couldn't read that day from Garmin. \(error.localizedDescription)"
        }
    }

    private func copy() {
        guard let plan else { return }
        let items = plan.copyable.filter { selected.contains($0.id) }
        isSaving = true
        saveError = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await environment.copyMeal(items, to: mealType)
                Haptics.success()
                dismiss()
            } catch {
                saveError = "Some items may already be logged -- check the sync queue. \(error.localizedDescription)"
                Haptics.warning()
            }
        }
    }
}

