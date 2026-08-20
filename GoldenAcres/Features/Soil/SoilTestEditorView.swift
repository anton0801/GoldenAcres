//
//  SoilTestEditorView.swift
//  GoldenAcres
//
//  Reviewing parsed values and confirming a soil test. A numeric value without
//  a unit can still be saved as a note, but it stays out of comparisons and is
//  labelled as such.
//

import SwiftUI
import SwiftData

struct SoilTestEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var field: FarmField
    var test: SoilTest?
    var parseResult: SoilParseResult?

    @State private var laboratory = ""
    @State private var sampleDate = Date()
    @State private var zone = ""
    @State private var depthText = ""
    @State private var depthUnit: DepthUnit = .centimeter

    @State private var phText = ""
    @State private var omText = ""
    @State private var nText = ""
    @State private var nUnit: ConcentrationUnit?
    @State private var pText = ""
    @State private var pUnit: ConcentrationUnit?
    @State private var kText = ""
    @State private var kUnit: ConcentrationUnit?
    @State private var salinityText = ""
    @State private var salinityUnit: ConcentrationUnit?
    @State private var notes = ""

    @State private var suggestions: [ParsedFieldSuggestion] = []
    @State private var errors: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String?

    private var isEditing: Bool { test != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let saveError {
                        ErrorBanner(title: "Could not save", message: saveError,
                                    onRetry: { save(confirm: false) },
                                    onDismiss: { self.saveError = nil })
                    }

                    if let reason = test?.parseFailedReason {
                        CardShell {
                            Label(reason, systemImage: "doc.questionmark")
                                .font(TypeScale.body(13)).foregroundStyle(Palette.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !suggestions.isEmpty { suggestionsCard }

                    sampleCard
                    resultsCard
                    notesCard

                    if !unitWarnings.isEmpty {
                        CardShell {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Label("Values without a unit", systemImage: "exclamationmark.triangle")
                                    .font(TypeScale.headline(13)).foregroundStyle(Palette.amber)
                                Text("\(unitWarnings.joined(separator: ", ")) — these save fine, but they stay out of numeric comparison until a unit is set.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VStack(spacing: Spacing.s) {
                        AmberButton(title: "Confirm test", systemImage: "checkmark.seal",
                                    isBusy: isSaving) { save(confirm: true) }
                        GhostButton(title: "Save as draft", systemImage: "tray.and.arrow.down") {
                            save(confirm: false)
                        }
                    }

                    Text("Only confirmed tests appear in comparisons and season reviews.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle(isEditing ? "Review soil test" : "Add soil test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Cards

    private var suggestionsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Review parsed values",
                              subtitle: "Each value shows where it came from and how confident the reader was.")
                if let provenance = test?.parseProvenance {
                    ProvenanceBadge(source: provenance.source, lastUpdated: provenance.retrievedAt)
                }
                ForEach(suggestions) { suggestion in
                    HStack(alignment: .top, spacing: Spacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.fieldKey)
                                .font(TypeScale.headline(13)).foregroundStyle(Palette.cream)
                            Text("“\(suggestion.rawText)”")
                                .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                                .lineLimit(2)
                            Text("\(suggestion.sourceLocation ?? "location unknown") · \(Int(suggestion.confidence * 100))% confidence")
                                .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(Fmt.number(suggestion.numericValue, decimals: 2) ?? "—") \(suggestion.unitText ?? "")")
                                .font(TypeScale.mono(13)).foregroundStyle(Palette.gold)
                            ChipButton(title: "Use", systemImage: "arrow.down.circle") {
                                apply(suggestion)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    if suggestion.id != suggestions.last?.id { Divider().overlay(Palette.hairline) }
                }
            }
        }
    }

    private var sampleCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateTextField(label: "Laboratory", placeholder: "Optional", text: $laboratory)
                PlateField(label: "Sample date", isRequired: true) {
                    DatePicker("", selection: $sampleDate, displayedComponents: .date)
                        .labelsHidden().tint(Palette.gold)
                }
                PlateTextField(label: "Zone", placeholder: "Optional — e.g. north half", text: $zone)
                HStack(alignment: .top, spacing: Spacing.m) {
                    PlateTextField(label: "Depth", placeholder: "Optional",
                                   text: $depthText, keyboard: .decimalPad)
                    PlateField(label: "Unit") {
                        Picker("", selection: $depthUnit) {
                            ForEach(DepthUnit.allCases) { Text($0.symbol).tag($0) }
                        }
                        .pickerStyle(.menu).tint(Palette.gold)
                    }
                    .frame(width: 100)
                }
            }
        }
    }

    private var resultsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Results",
                              subtitle: "Leave blank where the report has no value. Blank stays Unknown.")
                HStack(spacing: Spacing.m) {
                    PlateTextField(label: "pH", placeholder: "—", text: $phText,
                                   keyboard: .decimalPad, error: errors["ph"])
                    PlateTextField(label: "Organic matter %", placeholder: "—", text: $omText,
                                   keyboard: .decimalPad)
                }
                NutrientRow(label: "Nitrogen", text: $nText, unit: $nUnit)
                NutrientRow(label: "Phosphorus", text: $pText, unit: $pUnit)
                NutrientRow(label: "Potassium", text: $kText, unit: $kUnit)
                NutrientRow(label: "Salinity", text: $salinityText, unit: $salinityUnit)
            }
        }
    }

    private var notesCard: some View {
        CardShell {
            PlateTextField(label: "Notes", placeholder: "Optional", text: $notes, axis: .vertical)
        }
    }

    private var unitWarnings: [String] {
        var out: [String] = []
        if !nText.isEmpty && nUnit == nil { out.append("Nitrogen") }
        if !pText.isEmpty && pUnit == nil { out.append("Phosphorus") }
        if !kText.isEmpty && kUnit == nil { out.append("Potassium") }
        if !salinityText.isEmpty && salinityUnit == nil { out.append("Salinity") }
        return out
    }

    // MARK: - Logic

    private func load() {
        if let test {
            laboratory = test.laboratory ?? ""
            sampleDate = test.sampleDate
            zone = test.zone ?? ""
            depthText = test.depthValue.map { String($0) } ?? ""
            depthUnit = test.depthUnit
            phText = test.ph.map { String($0) } ?? ""
            omText = test.organicMatterPercent.map { String($0) } ?? ""
            nText = test.nitrogenValue.map { String($0) } ?? ""
            nUnit = test.nitrogenUnit
            pText = test.phosphorusValue.map { String($0) } ?? ""
            pUnit = test.phosphorusUnit
            kText = test.potassiumValue.map { String($0) } ?? ""
            kUnit = test.potassiumUnit
            salinityText = test.salinityValue.map { String($0) } ?? ""
            salinityUnit = test.salinityUnit
            notes = test.notes ?? ""
            suggestions = test.parsedSuggestions
        } else if let parseResult {
            suggestions = parseResult.suggestions
        }
    }

    private func apply(_ suggestion: ParsedFieldSuggestion) {
        let value = suggestion.numericValue.map { String($0) } ?? ""
        let unit = suggestion.unitText.flatMap { text -> ConcentrationUnit? in
            ConcentrationUnit.allCases.first {
                $0.symbol.caseInsensitiveCompare(text) == .orderedSame
            }
        }
        switch suggestion.fieldKey {
        case "pH": phText = value
        case "Organic matter": omText = value
        case "Nitrogen": nText = value; nUnit = unit ?? nUnit
        case "Phosphorus": pText = value; pUnit = unit ?? pUnit
        case "Potassium": kText = value; kUnit = unit ?? kUnit
        case "Salinity": salinityText = value; salinityUnit = unit ?? salinityUnit
        default: break
        }
    }

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func save(confirm: Bool) {
        guard !isSaving else { return }
        errors = [:]
        saveError = nil

        if !phText.isEmpty, let ph = number(phText), ph < 0 || ph > 14 {
            errors["ph"] = "pH is normally between 0 and 14."
        }
        guard errors.isEmpty else { return }

        isSaving = true
        let target = test ?? SoilTest(sampleDate: sampleDate, field: field)
        let isNew = test == nil

        target.laboratory = laboratory.trimmingCharacters(in: .whitespaces).isEmpty ? nil : laboratory
        target.sampleDate = sampleDate
        target.zone = zone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : zone
        target.depthValue = number(depthText)
        target.depthUnit = depthUnit
        target.ph = number(phText)
        target.organicMatterPercent = number(omText)
        target.nitrogenValue = number(nText)
        target.nitrogenUnit = nUnit
        target.phosphorusValue = number(pText)
        target.phosphorusUnit = pUnit
        target.potassiumValue = number(kText)
        target.potassiumUnit = kUnit
        target.salinityValue = number(salinityText)
        target.salinityUnit = salinityUnit
        target.notes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        target.fieldNameSnapshot = field.name
        target.updatedAt = Date()

        if confirm {
            target.status = .confirmed
            target.confirmedAt = Date()
        }

        if isNew {
            target.field = field
            context.insert(target)
            field.soilTests.append(target)
        }

        AuditService.log(action: confirm ? "Confirmed" : (isNew ? "Created" : "Updated"),
                         entityType: "Soil test", entityID: target.id,
                         summary: "\(confirm ? "Confirmed" : "Saved") soil test for \(field.name)",
                         details: "\(target.recordedValueCount) value(s) recorded",
                         context: context)

        do {
            try context.save()
            appState.confirm(confirm ? "Soil test confirmed" : "Draft saved",
                             detail: confirm
                                ? "\(target.recordedValueCount) value(s) now available for comparison"
                                : "Excluded from comparisons until confirmed")
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Nutrient row

struct NutrientRow: View {
    var label: String
    @Binding var text: String
    @Binding var unit: ConcentrationUnit?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            PlateTextField(label: label, placeholder: "—", text: $text, keyboard: .decimalPad)
            PlateField(label: "Unit",
                       error: !text.isEmpty && unit == nil ? "Needed to compare" : nil) {
                Picker("", selection: $unit) {
                    Text("—").tag(ConcentrationUnit?.none)
                    ForEach(ConcentrationUnit.allCases) {
                        Text($0.symbol).tag(ConcentrationUnit?.some($0))
                    }
                }
                .pickerStyle(.menu).tint(Palette.gold)
            }
            .frame(width: 118)
        }
    }
}
