//
//  SeasonEditorView.swift
//  GoldenAcres
//
//  Screen 3. Crop, field and intended area are required. Overlapping active
//  seasons on the same field require an explicit intercropping confirmation.
//  Activating a season creates an empty plan — never invented work.
//

import SwiftUI
import SwiftData

struct SeasonEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var farm: Farm
    var field: FarmField?
    var season: CropSeason?

    @State private var selectedField: FarmField?
    @State private var cropName = ""
    @State private var variety = ""
    @State private var intendedUse: IntendedUse?
    @State private var plantingStart: Date?
    @State private var plantingEnd: Date?
    @State private var actualPlanting: Date?
    @State private var harvestStart: Date?
    @State private var harvestEnd: Date?
    @State private var targetAreaText = ""
    @State private var targetAreaUnit: AreaUnit = .hectare
    @State private var seedLotID: UUID?
    @State private var notes = ""
    @State private var allowsIntercropping = false

    @State private var errors: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showIntercropPrompt = false
    @State private var showLotPicker = false
    @State private var pendingActivate = false

    @Query private var lots: [InventoryLot]

    private var isEditing: Bool { season != nil }

    private var seedLots: [InventoryLot] {
        lots.filter { !$0.isArchived && $0.category == .seeds }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let saveError {
                        ErrorBanner(title: "Could not save", message: saveError,
                                    onRetry: { save(activate: pendingActivate) },
                                    onDismiss: { self.saveError = nil })
                    }

                    cropCard
                    timingCard
                    seedCard
                    notesCard

                    VStack(spacing: Spacing.s) {
                        AmberButton(title: isEditing ? "Save season" : "Activate season",
                                    systemImage: "checkmark", isBusy: isSaving) {
                            attemptSave(activate: true)
                        }
                        GhostButton(title: "Save as draft", systemImage: "tray.and.arrow.down") {
                            attemptSave(activate: false)
                        }
                    }

                    Text("A draft season keeps your entries without linking work to it. Activating creates an empty task plan — no tasks are generated for you.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle(isEditing ? "Edit season" : "Start crop season")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear(perform: load)
            .alert("Overlapping active season", isPresented: $showIntercropPrompt) {
                Button("Cancel", role: .cancel) { }
                Button("Confirm intercropping") {
                    allowsIntercropping = true
                    save(activate: pendingActivate)
                }
            } message: {
                Text("\(selectedField?.name ?? "This field") already has an active season whose dates overlap. Continue only if you are genuinely intercropping.")
            }
            .sheet(isPresented: $showLotPicker) {
                SeedLotPicker(lots: seedLots, selected: $seedLotID)
            }
        }
    }

    // MARK: - Cards

    private var cropCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateField(label: "Field", isRequired: true, error: errors["field"]) {
                    Picker("", selection: $selectedField) {
                        Text("Select a field").tag(FarmField?.none)
                        ForEach(farm.activeFields) { f in
                            Text(f.name).tag(FarmField?.some(f))
                        }
                    }
                    .pickerStyle(.menu).tint(Palette.gold)
                }

                PlateTextField(label: "Crop", placeholder: "e.g. Winter wheat",
                               text: $cropName, isRequired: true, error: errors["crop"])

                PlateTextField(label: "Variety", placeholder: "Optional — type any name",
                               text: $variety,
                               helper: "Not restricted to a list. Unknown varieties are entered by hand.")

                PlateField(label: "Intended use") {
                    Picker("", selection: $intendedUse) {
                        Text("Not specified").tag(IntendedUse?.none)
                        ForEach(IntendedUse.allCases) { Text($0.rawValue).tag(IntendedUse?.some($0)) }
                    }
                    .pickerStyle(.menu).tint(Palette.gold)
                }

                HStack(alignment: .top, spacing: Spacing.m) {
                    PlateTextField(label: "Target area", placeholder: "0.00",
                                   text: $targetAreaText, isRequired: true,
                                   keyboard: .decimalPad, error: errors["area"])
                    PlateField(label: "Unit", isRequired: true) {
                        Picker("", selection: $targetAreaUnit) {
                            ForEach(AreaUnit.allCases) { Text($0.symbol).tag($0) }
                        }
                        .pickerStyle(.menu).tint(Palette.gold)
                    }
                    .frame(width: 108)
                }

                if let selectedField, let fieldArea = selectedField.areaValue {
                    let converted = fieldArea * selectedField.areaUnit.inSquareMeters
                    let target = Double(targetAreaText.replacingOccurrences(of: ",", with: "."))
                    if let target, target * targetAreaUnit.inSquareMeters > converted * 1.001 {
                        Label("Target area is larger than the field area on record (\(selectedField.areaDisplay ?? "")).",
                              systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(Palette.amber)
                    }
                } else if selectedField != nil {
                    Label("This field has no recorded area, so the target cannot be checked against it.",
                          systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private var timingCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Timing", subtitle: "All dates optional — leave blank if not decided.")
                OptionalDateRow(label: "Planting window start", date: $plantingStart)
                OptionalDateRow(label: "Planting window end", date: $plantingEnd)
                OptionalDateRow(label: "Actual planting date", date: $actualPlanting)
                Divider().overlay(Palette.hairline)
                OptionalDateRow(label: "Expected harvest start", date: $harvestStart)
                OptionalDateRow(label: "Expected harvest end", date: $harvestEnd)

                if let error = errors["dates"] {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(Palette.burgundy)
                }
            }
        }
    }

    private var seedCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Seed lot",
                              subtitle: "Links harvest back to the seed it came from.")
                if let seedLotID, let lot = lots.first(where: { $0.id == seedLotID }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lot.displayLabel)
                                .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                            Text("\(Fmt.quantity(lot.availableQuantity, lot.unit.symbol) ?? "") available")
                                .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Button("Change") { showLotPicker = true }
                            .font(TypeScale.body(13)).foregroundStyle(Palette.gold)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("No seed lot linked — traceability will show a gap.")
                            .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        ChipButton(title: seedLots.isEmpty ? "No seed lots in inventory" : "Choose seed lot",
                                   systemImage: "leaf") {
                            if !seedLots.isEmpty { showLotPicker = true }
                        }
                    }
                }
            }
        }
    }

    private var notesCard: some View {
        CardShell {
            PlateTextField(label: "Notes", placeholder: "Optional", text: $notes, axis: .vertical)
        }
    }

    // MARK: - Logic

    private func load() {
        selectedField = season?.field ?? field
        guard let season else { return }
        cropName = season.cropName
        variety = season.variety ?? ""
        intendedUse = season.intendedUse
        plantingStart = season.plantingWindowStart
        plantingEnd = season.plantingWindowEnd
        actualPlanting = season.actualPlantingDate
        harvestStart = season.expectedHarvestStart
        harvestEnd = season.expectedHarvestEnd
        targetAreaText = season.targetAreaValue.map { String($0) } ?? ""
        targetAreaUnit = season.targetAreaUnit
        seedLotID = season.seedLotID
        notes = season.notes ?? ""
        allowsIntercropping = season.allowsIntercropping
    }

    private func attemptSave(activate: Bool) {
        pendingActivate = activate
        guard validate() else { return }

        if activate, !allowsIntercropping, let selectedField {
            let overlapping = selectedField.seasons.filter { other in
                other.id != season?.id && other.status == .active
            }
            if !overlapping.isEmpty {
                showIntercropPrompt = true
                return
            }
        }
        save(activate: activate)
    }

    private func validate() -> Bool {
        errors = [:]
        if selectedField == nil { errors["field"] = "Choose the field this season runs on." }
        if cropName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors["crop"] = "Enter the crop."
        }
        let normalized = targetAreaText.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized) {
            if value <= 0 { errors["area"] = "Target area must be greater than zero." }
        } else {
            errors["area"] = targetAreaText.isEmpty ? "Enter the intended area." : "Enter a valid number."
        }
        if let start = plantingStart, let end = plantingEnd, end < start {
            errors["dates"] = "Planting window ends before it starts."
        }
        if let start = harvestStart, let end = harvestEnd, end < start {
            errors["dates"] = "Harvest window ends before it starts."
        }
        return errors.isEmpty
    }

    private func save(activate: Bool) {
        guard !isSaving, let selectedField else { return }
        isSaving = true
        saveError = nil

        let target = season ?? CropSeason()
        let isNew = season == nil

        target.cropName = cropName.trimmingCharacters(in: .whitespaces)
        target.variety = variety.trimmingCharacters(in: .whitespaces).isEmpty ? nil : variety
        target.intendedUse = intendedUse
        target.plantingWindowStart = plantingStart
        target.plantingWindowEnd = plantingEnd
        target.actualPlantingDate = actualPlanting
        target.expectedHarvestStart = harvestStart
        target.expectedHarvestEnd = harvestEnd
        target.targetAreaValue = Double(targetAreaText.replacingOccurrences(of: ",", with: "."))
        target.targetAreaUnit = targetAreaUnit
        target.seedLotID = seedLotID
        target.seedLotLabel = seedLotID.flatMap { id in
            lots.first(where: { $0.id == id })?.displayLabel
        }
        target.notes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        target.allowsIntercropping = allowsIntercropping
        target.updatedAt = Date()

        if activate && target.status != .closed {
            if target.status != .active {
                target.status = .active
                target.activatedAt = Date()
            }
        } else if !activate && target.status == .draft {
            target.status = .draft
        }

        if isNew {
            target.field = selectedField
            context.insert(target)
            selectedField.seasons.append(target)
        }

        AuditService.log(
            action: isNew ? "Created" : "Updated",
            entityType: "Crop season", entityID: target.id,
            summary: "\(isNew ? "Started" : "Updated") \(target.displayTitle) on \(selectedField.name)",
            details: "Status \(target.status.label)",
            context: context
        )

        do {
            try context.save()
            appState.confirm(
                isNew ? (activate ? "Season activated" : "Draft saved") : "Season saved",
                detail: "\(target.displayTitle) · \(selectedField.name)\(activate ? " · empty task plan created" : "")"
            )
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Optional date row

struct OptionalDateRow: View {
    var label: String
    @Binding var date: Date?

    var body: some View {
        HStack {
            Text(label)
                .font(TypeScale.body(13))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            if let bound = date {
                DatePicker("", selection: Binding(
                    get: { bound },
                    set: { date = $0 }
                ), displayedComponents: .date)
                .labelsHidden()
                .tint(Palette.gold)
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textTertiary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    date = Date()
                } label: {
                    HStack(spacing: 3) {
                        Text("Not set").font(TypeScale.body(13))
                        Image(systemName: "plus.circle.fill").font(.system(size: 11))
                    }
                    .foregroundStyle(Palette.amber)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Seed lot picker

struct SeedLotPicker: View {
    @Environment(\.dismiss) private var dismiss
    var lots: [InventoryLot]
    @Binding var selected: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    if lots.isEmpty {
                        HonestEmptyState(icon: "leaf",
                                         title: "No seed lots",
                                         message: "Add a lot in the Seeds category first, then link it here.")
                    } else {
                        ForEach(lots) { lot in
                            Button {
                                selected = lot.id
                                dismiss()
                            } label: {
                                CardShell {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(lot.displayLabel)
                                                .font(TypeScale.headline(14))
                                                .foregroundStyle(Palette.cream)
                                            Text("\(Fmt.quantity(lot.availableQuantity, lot.unit.symbol) ?? "") available · \(lot.supplier ?? "supplier not recorded")")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Palette.textSecondary)
                                        }
                                        Spacer()
                                        if selected == lot.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Palette.positive)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Button("Clear selection") { selected = nil; dismiss() }
                            .font(TypeScale.body(13)).foregroundStyle(Palette.gold)
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Choose seed lot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
}
