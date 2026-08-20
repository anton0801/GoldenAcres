//
//  ObservationEditorView.swift
//  GoldenAcres
//
//  Screen 4. Notes or a photo are enough to save. Image analysis produces a
//  *suggested* category with a confidence figure; the user confirms it. The
//  app never names a disease or proposes a treatment.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ObservationEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var farm: Farm
    var field: FarmField?
    var observation: FieldObservation?

    @State private var selectedField: FarmField?
    @State private var date = Date()
    @State private var type: ObservationType = .generalNote
    @State private var severity: Severity?
    @State private var notes = ""
    @State private var affectedAreaText = ""
    @State private var affectedAreaUnit: AreaUnit = .hectare
    @State private var cropStage = ""
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var reviewRequested = false
    @State private var confirmedCategory: String?

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var savedFilenames: [String] = []

    @State private var suggestion: ImageSuggestion?
    @State private var isAnalyzing = false

    @State private var errors: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String?

    private var isEditing: Bool { observation != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let saveError {
                        ErrorBanner(title: "Could not save", message: saveError,
                                    onRetry: { save() }, onDismiss: { self.saveError = nil })
                    }

                    contextCard
                    photosCard
                    if suggestion != nil || isAnalyzing { suggestionCard }
                    detailCard

                    AmberButton(title: isEditing ? "Save observation" : "Save observation",
                                systemImage: "checkmark", isBusy: isSaving) { save() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle(isEditing ? "Edit observation" : "Add observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear(perform: load)
            .onChange(of: pickerItems) { _, items in loadPickedImages(items) }
        }
    }

    // MARK: - Cards

    private var contextCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateField(label: "Field", isRequired: true, error: errors["field"]) {
                    Picker("", selection: $selectedField) {
                        Text("Select a field").tag(FarmField?.none)
                        ForEach(farm.activeFields) { f in Text(f.name).tag(FarmField?.some(f)) }
                    }
                    .pickerStyle(.menu).tint(Palette.gold)
                }

                PlateField(label: "Date & time", isRequired: true) {
                    DatePicker("", selection: $date).labelsHidden().tint(Palette.gold)
                }

                PlateField(label: "Observation type", isRequired: true) {
                    Picker("", selection: $type) {
                        ForEach(ObservationType.allCases) {
                            Label($0.rawValue, systemImage: $0.icon).tag($0)
                        }
                    }
                    .pickerStyle(.menu).tint(Palette.gold)
                }

                PlateField(label: "Severity",
                           helper: "Leave unset if you did not assess it — it will not be treated as low.") {
                    Picker("", selection: $severity) {
                        Text("Not rated").tag(Severity?.none)
                        ForEach(Severity.allCases) { Text($0.rawValue).tag(Severity?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var photosCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Photos",
                              subtitle: "Originals are stored unchanged. Analysis never replaces them.")

                if !images.isEmpty || !savedFilenames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s) {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
                                    .resizable().scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            images.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, Palette.burgundy)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(3)
                                    }
                            }
                            ForEach(savedFilenames, id: \.self) { name in
                                if let image = PhotoStore.load(name) {
                                    Image(uiImage: image)
                                        .resizable().scaledToFill()
                                        .frame(width: 84, height: 84)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                                }
                            }
                        }
                    }
                }

                HStack(spacing: Spacing.s) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                        HStack(spacing: 4) {
                            Image(systemName: "camera").font(.system(size: 11, weight: .bold))
                            Text("Add photo").font(TypeScale.stamp(11)).tracking(0.6)
                        }
                        .foregroundStyle(Palette.gold)
                        .padding(.vertical, 7).padding(.horizontal, Spacing.m)
                        .background(Capsule().fill(Palette.gold.opacity(0.12))
                            .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.35), lineWidth: 1)))
                    }

                    if !images.isEmpty {
                        ChipButton(title: isAnalyzing ? "Analysing…" : "Suggest category",
                                   systemImage: "wand.and.stars") {
                            analyze()
                        }
                    }
                }
            }
        }
    }

    private var suggestionCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Image suggestion")
                if isAnalyzing {
                    LoadingBlock(lines: 2)
                } else if let suggestion {
                    if let category = suggestion.suggestedCategory, suggestion.isReliable {
                        HStack {
                            Text(category)
                                .font(TypeScale.headline(15)).foregroundStyle(Palette.cream)
                            Spacer()
                            StatusPill(text: "\(Int((suggestion.confidence ?? 0) * 100))% confidence",
                                       tone: .warning)
                        }
                        Text(suggestion.message ?? "")
                            .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Spacing.s) {
                            ChipButton(title: "Use as category", systemImage: "checkmark") {
                                confirmedCategory = category
                            }
                            if confirmedCategory != nil {
                                ChipButton(title: "Clear", systemImage: "xmark",
                                           tint: Palette.textSecondary) {
                                    confirmedCategory = nil
                                }
                            }
                        }
                    } else {
                        Label(suggestion.message ?? "Unable to identify reliably.",
                              systemImage: "questionmark.circle")
                            .font(TypeScale.body(13)).foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ProvenanceBadge(source: suggestion.provenance.source,
                                    lastUpdated: suggestion.provenance.retrievedAt)

                    Text("This is a generic image label. It is not a diagnosis and carries no treatment advice.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var detailCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateTextField(label: "Notes", placeholder: "What did you see?",
                               text: $notes, error: errors["content"], axis: .vertical)

                if let confirmedCategory {
                    ValueRow(label: "Confirmed category", value: confirmedCategory,
                             tone: Palette.positive)
                }

                HStack(alignment: .top, spacing: Spacing.m) {
                    PlateTextField(label: "Affected area", placeholder: "Optional",
                                   text: $affectedAreaText, keyboard: .decimalPad,
                                   error: errors["area"])
                    PlateField(label: "Unit") {
                        Picker("", selection: $affectedAreaUnit) {
                            ForEach(AreaUnit.allCases) { Text($0.symbol).tag($0) }
                        }
                        .pickerStyle(.menu).tint(Palette.gold)
                    }
                    .frame(width: 108)
                }

                PlateTextField(label: "Related crop stage", placeholder: "Optional, e.g. tillering",
                               text: $cropStage)

                HStack(spacing: Spacing.m) {
                    PlateTextField(label: "Latitude", placeholder: "Optional",
                                   text: $latitudeText, keyboard: .numbersAndPunctuation)
                    PlateTextField(label: "Longitude", placeholder: "Optional",
                                   text: $longitudeText, keyboard: .numbersAndPunctuation)
                }

                Toggle(isOn: $reviewRequested) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Request review").font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                        Text("Flags this for a second look. It does not send anything anywhere.")
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                }
                .tint(Palette.amber)
            }
        }
    }

    // MARK: - Logic

    private func load() {
        selectedField = observation?.field ?? field
        guard let observation else { return }
        date = observation.date
        type = observation.observationType
        severity = observation.severity
        notes = observation.notes ?? ""
        affectedAreaText = observation.affectedAreaValue.map { String($0) } ?? ""
        affectedAreaUnit = observation.affectedAreaUnit
        cropStage = observation.relatedCropStage ?? ""
        latitudeText = observation.latitude.map { String($0) } ?? ""
        longitudeText = observation.longitude.map { String($0) } ?? ""
        reviewRequested = observation.reviewRequested
        confirmedCategory = observation.confirmedCategory
        savedFilenames = observation.photoFilenames
        suggestion = observation.imageSuggestion
    }

    private func loadPickedImages(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            await MainActor.run {
                images.append(contentsOf: loaded)
                pickerItems = []
            }
        }
    }

    private func analyze() {
        guard let first = images.first else { return }
        isAnalyzing = true
        Task {
            let result = await ImageSuggestionService.classify(image: first)
            await MainActor.run {
                suggestion = result
                isAnalyzing = false
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        errors = [:]
        saveError = nil

        if selectedField == nil { errors["field"] = "Choose the field." }

        let hasNotes = !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhotos = !images.isEmpty || !savedFilenames.isEmpty
        if !hasNotes && !hasPhotos {
            errors["content"] = "Add a note or at least one photo."
        }

        if !affectedAreaText.isEmpty {
            let normalized = affectedAreaText.replacingOccurrences(of: ",", with: ".")
            if Double(normalized) == nil {
                errors["area"] = "Enter a valid number, or leave blank."
            }
        }

        guard errors.isEmpty, let selectedField else { return }

        isSaving = true

        // Persist any newly picked photos before writing the record.
        var filenames = savedFilenames
        for image in images {
            if let name = PhotoStore.save(image) { filenames.append(name) }
        }

        let target = observation ?? FieldObservation()
        let isNew = observation == nil

        target.date = date
        target.observationType = type
        target.severity = severity
        target.notes = hasNotes ? notes.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        target.photoFilenames = filenames
        target.affectedAreaValue = Double(affectedAreaText.replacingOccurrences(of: ",", with: "."))
        target.affectedAreaUnit = affectedAreaUnit
        target.relatedCropStage = cropStage.trimmingCharacters(in: .whitespaces).isEmpty ? nil : cropStage
        target.latitude = Double(latitudeText.replacingOccurrences(of: ",", with: "."))
        target.longitude = Double(longitudeText.replacingOccurrences(of: ",", with: "."))
        target.reviewRequested = reviewRequested
        target.imageSuggestion = suggestion
        target.confirmedCategory = confirmedCategory
        target.seasonID = selectedField.currentSeason?.id
        target.fieldNameSnapshot = selectedField.name
        target.updatedAt = Date()

        if isNew {
            target.field = selectedField
            context.insert(target)
            selectedField.observations.append(target)
        }

        AuditService.log(action: isNew ? "Created" : "Updated", entityType: "Observation",
                         entityID: target.id,
                         summary: "\(isNew ? "Recorded" : "Updated") observation on \(selectedField.name)",
                         details: target.confirmedCategory ?? target.observationType.rawValue,
                         context: context)

        do {
            try context.save()
            appState.confirm(isNew ? "Observation recorded" : "Observation saved",
                             detail: "\(selectedField.name) · \(filenames.count) photo(s)")
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}
