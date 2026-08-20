//
//  FarmSetupView.swift
//  GoldenAcres
//
//  Screen 2 (farm half). Creating or editing the farm record.
//

import SwiftUI
import SwiftData

struct FarmSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Query private var farms: [Farm]

    var existingFarm: Farm?

    @State private var name = ""
    @State private var country = ""
    @State private var timeZoneID = TimeZone.current.identifier
    @State private var unitSystem: UnitSystem = .metric
    @State private var currency = "USD"
    @State private var errors: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String?

    private var isEditing: Bool { existingFarm != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let saveError {
                        ErrorBanner(title: "Could not save", message: saveError,
                                    onRetry: { save() },
                                    onDismiss: { self.saveError = nil })
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            PlateTextField(label: "Farm name", placeholder: "e.g. Hillside Holding",
                                           text: $name, isRequired: true, error: errors["name"])
                            PlateTextField(label: "Country", placeholder: "Optional",
                                           text: $country,
                                           helper: "Used only as a label on reports.")
                            PlateField(label: "Time zone",
                                       helper: "Task windows and forecasts are shown in this zone.") {
                                Picker("", selection: $timeZoneID) {
                                    ForEach(TimeZone.knownTimeZoneIdentifiers.prefix(200), id: \.self) { id in
                                        Text(id).tag(id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Palette.gold)
                            }
                            PlateField(label: "Default units",
                                       helper: "A default for new records. Existing values keep the unit they were entered with.") {
                                Picker("", selection: $unitSystem) {
                                    ForEach(UnitSystem.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                            PlateTextField(label: "Currency code", placeholder: "USD",
                                           text: $currency,
                                           error: errors["currency"],
                                           helper: "Three-letter code, e.g. USD, EUR, GBP.")
                        }
                    }

                    AmberButton(title: isEditing ? "Save changes" : "Create farm",
                                systemImage: "checkmark", isBusy: isSaving) { save() }

                    if isEditing {
                        Text("Deleting a farm is handled in Settings, where its linked records are listed first.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle(isEditing ? "Edit farm" : "Create farm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let farm = existingFarm else { return }
        name = farm.name
        country = farm.country
        timeZoneID = farm.timeZoneIdentifier
        unitSystem = farm.unitSystem
        currency = farm.currencyCode
    }

    private func save() {
        guard !isSaving else { return }
        errors = [:]
        saveError = nil

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { errors["name"] = "Enter a farm name." }
        let code = currency.trimmingCharacters(in: .whitespaces).uppercased()
        if code.count != 3 { errors["currency"] = "Use a three-letter currency code." }
        guard errors.isEmpty else { return }

        isSaving = true
        let farm = existingFarm ?? Farm()
        let isNew = existingFarm == nil

        farm.name = trimmed
        farm.country = country.trimmingCharacters(in: .whitespaces)
        farm.timeZoneIdentifier = timeZoneID
        farm.unitSystem = unitSystem
        farm.currencyCode = code
        farm.updatedAt = Date()

        if isNew { context.insert(farm) }

        AuditService.log(action: isNew ? "Created" : "Updated", entityType: "Farm",
                         entityID: farm.id,
                         summary: "\(isNew ? "Created" : "Updated") farm “\(farm.name)”",
                         context: context)

        do {
            try context.save()
            appState.confirm(isNew ? "Farm created" : "Farm updated",
                             detail: "\(farm.name) · \(farm.unitSystem.label) · \(farm.currencyCode)")
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}
