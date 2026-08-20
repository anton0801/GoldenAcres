//
//  TaskEditorView.swift
//  GoldenAcres
//
//  Task creation, detail and lifecycle. Reserving an input lowers availability
//  without touching physical stock; completing is guarded by an idempotency
//  key so a double tap cannot record the work twice.
//

import SwiftUI
import SwiftData

struct TaskEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Farm.createdAt) private var farms: [Farm]
    @Query private var lots: [InventoryLot]
    @Query private var allTasks: [FarmTask]

    var season: CropSeason?
    var task: FarmTask?

    @State private var title = ""
    @State private var detail = ""
    @State private var selectedSeason: CropSeason?
    @State private var dueStart: Date?
    @State private var dueEnd: Date?
    @State private var durationText = ""
    @State private var priority: TaskPriority = .normal
    @State private var assignee = ""
    @State private var equipment = ""
    @State private var requiredInputs: [RequiredInput] = []
    @State private var dependencyIDs: [UUID] = []

    @State private var errors: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showInputPicker = false
    @State private var showDependencyPicker = false

    private var isEditing: Bool { task != nil }
    private var farm: Farm? { farms.first(where: { !$0.isArchived }) }

    private var availableSeasons: [CropSeason] {
        (farm?.fields ?? []).flatMap(\.seasons).filter { $0.status == .active || $0.status == .draft }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let saveError {
                        ErrorBanner(title: "Could not save", message: saveError,
                                    onRetry: { save() }, onDismiss: { self.saveError = nil })
                    }

                    basicsCard
                    schedulingCard
                    resourcesCard
                    dependenciesCard

                    if !conflicts.isEmpty {
                        CardShell {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Label("Conflicts to be aware of", systemImage: "exclamationmark.triangle")
                                    .font(TypeScale.headline(13)).foregroundStyle(Palette.amber)
                                ForEach(conflicts, id: \.self) { conflict in
                                    Text("— \(conflict)").font(.system(size: 11))
                                        .foregroundStyle(Palette.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text("These do not block saving. You decide.")
                                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }

                    AmberButton(title: isEditing ? "Save task" : "Add task",
                                systemImage: "checkmark", isBusy: isSaving) { save() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle(isEditing ? "Edit task" : "Add task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showInputPicker) {
                RequiredInputPicker(lots: lots.filter { !$0.isArchived },
                                    inputs: $requiredInputs)
            }
            .sheet(isPresented: $showDependencyPicker) {
                DependencyPicker(tasks: allTasks.filter { $0.id != task?.id },
                                 selected: $dependencyIDs)
            }
        }
    }

    // MARK: - Cards

    private var basicsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateTextField(label: "Task", placeholder: "e.g. Side-dress nitrogen",
                               text: $title, isRequired: true, error: errors["title"])
                PlateTextField(label: "Detail", placeholder: "Optional", text: $detail, axis: .vertical)
                PlateField(label: "Season") {
                    Picker("", selection: $selectedSeason) {
                        Text("No season").tag(CropSeason?.none)
                        ForEach(availableSeasons) { s in
                            Text("\(s.displayTitle) — \(s.field?.name ?? "")").tag(CropSeason?.some(s))
                        }
                    }
                    .pickerStyle(.menu).tint(Palette.gold)
                }
            }
        }
    }

    private var schedulingCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Scheduling")
                OptionalDateRow(label: "Due window start", date: $dueStart)
                OptionalDateRow(label: "Due window end", date: $dueEnd)
                if let error = errors["dates"] {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(Palette.burgundy)
                }
                PlateTextField(label: "Estimated duration (minutes)", placeholder: "Optional",
                               text: $durationText, keyboard: .numberPad)
                PlateField(label: "Priority") {
                    Picker("", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var resourcesCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Resources")
                PlateTextField(label: "Assignee", placeholder: "Optional", text: $assignee)
                PlateTextField(label: "Equipment", placeholder: "Optional", text: $equipment)

                Divider().overlay(Palette.hairline)

                HStack {
                    Text("Required inputs").stampLabel(Palette.textSecondary)
                    Spacer()
                    ChipButton(title: "Add", systemImage: "plus") { showInputPicker = true }
                }

                if requiredInputs.isEmpty {
                    Text("None. Adding an input reserves it from a lot — availability drops, physical stock does not.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(requiredInputs) { input in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(input.itemName)
                                    .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                                if let lotID = input.lotID,
                                   let lot = lots.first(where: { $0.id == lotID }) {
                                    Text("Lot \(lot.lotCode) · \(Fmt.quantity(lot.availableQuantity, lot.unit.symbol) ?? "") available")
                                        .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                                }
                            }
                            Spacer()
                            Text(Fmt.quantity(input.quantity, input.unit?.symbol) ?? "qty not set")
                                .font(TypeScale.mono(12)).foregroundStyle(Palette.gold)
                            Button {
                                requiredInputs.removeAll { $0.id == input.id }
                            } label: {
                                Image(systemName: "minus.circle").foregroundStyle(Palette.burgundy)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var dependenciesCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    Text("Depends on").stampLabel(Palette.textSecondary)
                    Spacer()
                    ChipButton(title: "Set", systemImage: "arrow.triangle.branch") {
                        showDependencyPicker = true
                    }
                }
                if dependencyIDs.isEmpty {
                    Text("No dependencies.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                } else {
                    ForEach(dependencyIDs, id: \.self) { id in
                        if let dependency = allTasks.first(where: { $0.id == id }) {
                            HStack {
                                Text(dependency.title)
                                    .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                                Spacer()
                                StatusPill(text: dependency.status.rawValue, tone: dependency.status.tone)
                            }
                        }
                    }
                }
            }
        }
    }

    private var conflicts: [String] {
        var out: [String] = []

        // Reservations that exceed what is available.
        for input in requiredInputs {
            guard let lotID = input.lotID,
                  let lot = lots.first(where: { $0.id == lotID }),
                  let quantity = input.quantity,
                  let unit = input.unit else { continue }
            guard let converted = unit.convert(quantity, to: lot.unit) else {
                out.append("\(input.itemName): \(unit.symbol) cannot be converted to the lot's \(lot.unit.symbol).")
                continue
            }
            if converted > lot.availableQuantity {
                out.append("\(input.itemName): needs \(Fmt.number(converted, decimals: 2) ?? "") \(lot.unit.symbol) but only \(Fmt.number(lot.availableQuantity, decimals: 2) ?? "") is available.")
            }
        }

        // Same assignee already booked in an overlapping window.
        if !assignee.isEmpty, let start = dueStart, let end = dueEnd {
            let clashes = allTasks.filter { other in
                other.id != task?.id
                    && other.assignee?.caseInsensitiveCompare(assignee) == .orderedSame
                    && other.status.isOpen
                    && (other.dueStart ?? .distantFuture) < end
                    && (other.dueEnd ?? .distantPast) > start
            }
            if !clashes.isEmpty {
                out.append("\(assignee) already has \(clashes.count) task(s) overlapping this window.")
            }
        }

        // Dependencies that finish after this task is due to start.
        for id in dependencyIDs {
            guard let dependency = allTasks.first(where: { $0.id == id }) else { continue }
            if let depEnd = dependency.dueEnd, let start = dueStart, depEnd > start {
                out.append("“\(dependency.title)” is not due to finish until \(Fmt.date(depEnd) ?? "") — after this task starts.")
            }
        }
        return out
    }

    // MARK: - Logic

    private func load() {
        selectedSeason = task?.season ?? season
        guard let task else { return }
        title = task.title
        detail = task.detail ?? ""
        dueStart = task.dueStart
        dueEnd = task.dueEnd
        durationText = task.estimatedDurationMinutes.map { String(Int($0)) } ?? ""
        priority = task.priority
        assignee = task.assignee ?? ""
        equipment = task.equipment ?? ""
        requiredInputs = task.requiredInputs
        dependencyIDs = task.dependencyIDs
    }

    private func save() {
        guard !isSaving else { return }
        errors = [:]
        saveError = nil

        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            errors["title"] = "Enter what needs doing."
        }
        if let start = dueStart, let end = dueEnd, end < start {
            errors["dates"] = "The due window ends before it starts."
        }
        guard errors.isEmpty else { return }

        isSaving = true
        let target = task ?? FarmTask()
        let isNew = task == nil
        let previousInputs = target.requiredInputs

        target.title = title.trimmingCharacters(in: .whitespaces)
        target.detail = detail.trimmingCharacters(in: .whitespaces).isEmpty ? nil : detail
        target.dueStart = dueStart
        target.dueEnd = dueEnd
        target.estimatedDurationMinutes = Double(durationText)
        target.priority = priority
        target.assignee = assignee.trimmingCharacters(in: .whitespaces).isEmpty ? nil : assignee
        target.equipment = equipment.trimmingCharacters(in: .whitespaces).isEmpty ? nil : equipment
        target.dependencyIDs = dependencyIDs
        target.fieldID = selectedSeason?.field?.id
        target.fieldNameSnapshot = selectedSeason?.field?.name ?? ""
        target.updatedAt = Date()

        if isNew {
            target.season = selectedSeason
            context.insert(target)
            selectedSeason?.tasks.append(target)
        } else if target.season !== selectedSeason {
            target.season?.tasks.removeAll { $0.id == target.id }
            target.season = selectedSeason
            selectedSeason?.tasks.append(target)
        }

        // Reconcile reservations: release what was removed, reserve what is new.
        var reservationErrors: [String] = []
        for old in previousInputs where !requiredInputs.contains(where: { $0.id == old.id }) {
            if let lotID = old.lotID, let lot = lots.first(where: { $0.id == lotID }),
               let quantity = old.quantity, let unit = old.unit,
               let converted = unit.convert(quantity, to: lot.unit) {
                InventoryService.releaseReservation(lot: lot, quantity: converted,
                                                    forTask: target.id, taskLabel: target.title,
                                                    context: context)
            }
        }

        var finalInputs: [RequiredInput] = []
        for var input in requiredInputs {
            let alreadyReserved = previousInputs.contains { $0.id == input.id && $0.reservationID != nil }
            if !alreadyReserved, let lotID = input.lotID,
               let lot = lots.first(where: { $0.id == lotID }),
               let quantity = input.quantity, let unit = input.unit {
                do {
                    let movement = try InventoryService.reserve(
                        lot: lot, quantity: quantity, unit: unit,
                        forTask: target.id, taskLabel: target.title, context: context)
                    input.reservationID = movement.id
                } catch {
                    reservationErrors.append("\(input.itemName): \(error.localizedDescription)")
                }
            }
            finalInputs.append(input)
        }
        target.requiredInputs = finalInputs

        AuditService.log(action: isNew ? "Created" : "Updated", entityType: "Task",
                         entityID: target.id,
                         summary: "\(isNew ? "Added" : "Updated") task “\(target.title)”",
                         context: context)

        do {
            try context.save()
            let reservedCount = finalInputs.filter { $0.reservationID != nil }.count
            var detailText = reservedCount > 0 ? "\(reservedCount) input(s) reserved" : nil
            if !reservationErrors.isEmpty {
                detailText = "Saved, but \(reservationErrors.count) reservation(s) failed"
            }
            appState.confirm(isNew ? "Task added" : "Task saved", detail: detailText)
            isSaving = false
            if reservationErrors.isEmpty {
                dismiss()
            } else {
                saveError = reservationErrors.joined(separator: "\n")
            }
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Required input picker

struct RequiredInputPicker: View {
    @Environment(\.dismiss) private var dismiss
    var lots: [InventoryLot]
    @Binding var inputs: [RequiredInput]

    @State private var selectedLot: InventoryLot?
    @State private var quantityText = ""
    @State private var freeTextName = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SectionHeader(title: "From a stock lot")
                            if lots.isEmpty {
                                Text("No lots in inventory yet.")
                                    .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                            } else {
                                PlateField(label: "Lot") {
                                    Picker("", selection: $selectedLot) {
                                        Text("Select").tag(InventoryLot?.none)
                                        ForEach(lots) { lot in
                                            Text(lot.displayLabel).tag(InventoryLot?.some(lot))
                                        }
                                    }
                                    .pickerStyle(.menu).tint(Palette.gold)
                                }
                                if let selectedLot {
                                    ValueRow(label: "Available",
                                             value: Fmt.number(selectedLot.availableQuantity, decimals: 2),
                                             unit: selectedLot.unit.symbol)
                                    PlateTextField(label: "Quantity to reserve",
                                                   placeholder: "0",
                                                   text: $quantityText, keyboard: .decimalPad,
                                                   error: error,
                                                   helper: "Reserving lowers availability only. Stock is deducted when an application is confirmed.")
                                }
                            }
                        }
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SectionHeader(title: "Or note an item not in stock")
                            PlateTextField(label: "Item name", placeholder: "e.g. twine",
                                           text: $freeTextName)
                            Text("Recorded as a requirement only — nothing is reserved.")
                                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        }
                    }

                    AmberButton(title: "Add requirement", systemImage: "plus") { add() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Required input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private func add() {
        error = nil
        if let lot = selectedLot {
            guard let quantity = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
                  quantity > 0 else {
                error = "Enter a quantity greater than zero."
                return
            }
            guard quantity <= lot.availableQuantity else {
                error = "Only \(Fmt.number(lot.availableQuantity, decimals: 2) ?? "0") \(lot.unit.symbol) is available."
                return
            }
            inputs.append(RequiredInput(itemName: lot.itemName, quantity: quantity,
                                        unit: lot.unit, lotID: lot.id))
            dismiss()
        } else if !freeTextName.trimmingCharacters(in: .whitespaces).isEmpty {
            inputs.append(RequiredInput(itemName: freeTextName.trimmingCharacters(in: .whitespaces)))
            dismiss()
        } else {
            error = "Choose a lot or enter an item name."
        }
    }
}

// MARK: - Dependency picker

struct DependencyPicker: View {
    @Environment(\.dismiss) private var dismiss
    var tasks: [FarmTask]
    @Binding var selected: [UUID]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.s) {
                    if tasks.isEmpty {
                        HonestEmptyState(icon: "arrow.triangle.branch", title: "No other tasks",
                                         message: "Create another task first to depend on it.")
                    } else {
                        ForEach(tasks) { task in
                            Button {
                                if selected.contains(task.id) {
                                    selected.removeAll { $0 == task.id }
                                } else {
                                    selected.append(task.id)
                                }
                            } label: {
                                CardShell {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title)
                                                .font(TypeScale.headline(14))
                                                .foregroundStyle(Palette.cream)
                                            Text("\(task.status.rawValue) · \(task.dueDisplay ?? "no due date")")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Palette.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: selected.contains(task.id)
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(task.id)
                                                             ? Palette.positive : Palette.textTertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Dependencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.gold)
                }
            }
        }
    }
}
