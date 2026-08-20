//
//  ApplicationEditorView.swift
//  GoldenAcres
//
//  Screen 8. Saving deducts the selected lot and writes an immutable record.
//  The app never proposes a dose and never states that a product is legally
//  permitted for a use — that stays with the official label and the user.
//

import SwiftUI
import SwiftData

struct ApplicationEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @Query private var lots: [InventoryLot]

    var season: CropSeason?
    var field: FarmField?

    @State private var productName = ""
    @State private var category: InputCategory = .fertilizer
    @State private var registrationNote = ""
    @State private var selectedLot: InventoryLot?
    @State private var quantityText = ""
    @State private var unit: QuantityUnit = .liter
    @State private var areaText = ""
    @State private var areaUnit: AreaUnit = .hectare
    @State private var date = Date()
    @State private var operatorName = ""
    @State private var purpose = ""
    @State private var weatherSnapshot: WeatherSnapshot?
    @State private var isFetchingWeather = false

    @State private var errors: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String?

    private var availableLots: [InventoryLot] {
        lots.filter { !$0.isArchived && $0.availableQuantity > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let saveError {
                        ErrorBanner(title: "Could not record", message: saveError,
                                    onRetry: { save() }, onDismiss: { self.saveError = nil })
                    }

                    disclaimerCard
                    productCard
                    quantityCard
                    contextCard
                    weatherCard

                    AmberButton(title: "Save record", systemImage: "checkmark", isBusy: isSaving) {
                        save()
                    }

                    Text("Saving deducts the selected lot and creates a record that cannot be edited. A correction voids the original and writes a new one, so history stays intact.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Record application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear {
                if let field, let area = field.areaValue {
                    areaText = String(area)
                    areaUnit = field.areaUnit
                }
            }
        }
    }

    // MARK: - Cards

    private var disclaimerCard: some View {
        CardShell {
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(Palette.amber)
                Text("You are responsible for confirming the product is permitted for this use and for following its label, rates and safety intervals. This app records what you did; it does not advise or approve.")
                    .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var productCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateField(label: "Stock lot", isRequired: true, error: errors["lot"]) {
                    Picker("", selection: $selectedLot) {
                        Text("Select a lot").tag(InventoryLot?.none)
                        ForEach(availableLots) { lot in
                            Text("\(lot.displayLabel) — \(Fmt.quantity(lot.availableQuantity, lot.unit.symbol) ?? "")")
                                .tag(InventoryLot?.some(lot))
                        }
                    }
                    .pickerStyle(.menu).tint(Palette.gold)
                }

                if availableLots.isEmpty {
                    Label("No lots with available stock. Add stock in Inventory first.",
                          systemImage: "shippingbox")
                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                }

                if let selectedLot {
                    ValueRow(label: "Available",
                             value: Fmt.number(selectedLot.availableQuantity, decimals: 2),
                             unit: selectedLot.unit.symbol)
                    ValueRow(label: "On hand",
                             value: Fmt.number(selectedLot.onHandQuantity, decimals: 2),
                             unit: selectedLot.unit.symbol)
                    if selectedLot.isExpired {
                        Label("This lot is past its recorded expiry date.",
                              systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(Palette.burgundy)
                    }
                }

                PlateTextField(label: "Product name", placeholder: "As written on the label",
                               text: $productName, isRequired: true, error: errors["product"])
                PlateField(label: "Category") {
                    Picker("", selection: $category) {
                        ForEach(InputCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu).tint(Palette.gold)
                }
                PlateTextField(label: "Registration / reference note",
                               placeholder: "Optional — e.g. label reference you checked",
                               text: $registrationNote,
                               helper: "Free text. The app does not verify registration status.")
            }
        }
    }

    private var quantityCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top, spacing: Spacing.m) {
                    PlateTextField(label: "Quantity used", placeholder: "0",
                                   text: $quantityText, isRequired: true,
                                   keyboard: .decimalPad, error: errors["quantity"])
                    PlateField(label: "Unit", isRequired: true) {
                        Picker("", selection: $unit) {
                            ForEach(QuantityUnit.allCases) { Text($0.symbol).tag($0) }
                        }
                        .pickerStyle(.menu).tint(Palette.gold)
                    }
                    .frame(width: 108)
                }

                HStack(alignment: .top, spacing: Spacing.m) {
                    PlateTextField(label: "Area treated", placeholder: "Optional",
                                   text: $areaText, keyboard: .decimalPad)
                    PlateField(label: "Unit") {
                        Picker("", selection: $areaUnit) {
                            ForEach(AreaUnit.allCases) { Text($0.symbol).tag($0) }
                        }
                        .pickerStyle(.menu).tint(Palette.gold)
                    }
                    .frame(width: 108)
                }

                if let rate = computedRate {
                    ValueRow(label: "Resulting rate", value: Fmt.number(rate, decimals: 2),
                             unit: "\(unit.symbol)/ha", tone: Palette.gold)
                    Text("Calculated from what you entered. It is not checked against any label.")
                        .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private var computedRate: Double? {
        guard let quantity = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let area = Double(areaText.replacingOccurrences(of: ",", with: ".")),
              area > 0 else { return nil }
        let hectares = area * areaUnit.inSquareMeters / AreaUnit.hectare.inSquareMeters
        guard hectares > 0 else { return nil }
        return quantity / hectares
    }

    private var contextCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateField(label: "Date", isRequired: true) {
                    DatePicker("", selection: $date).labelsHidden().tint(Palette.gold)
                }
                PlateTextField(label: "Operator", placeholder: "Who applied it", text: $operatorName)
                PlateTextField(label: "Purpose", placeholder: "Optional", text: $purpose, axis: .vertical)
                ValueRow(label: "Field", value: field?.name ?? season?.field?.name)
                ValueRow(label: "Season", value: season?.displayTitle)
            }
        }
    }

    private var weatherCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Weather snapshot",
                              subtitle: "Optional record of conditions at application.")
                if let weatherSnapshot {
                    HStack(spacing: Spacing.l) {
                        ValueColumn(label: "Temp",
                                    value: Fmt.number(weatherSnapshot.temperatureC, decimals: 1),
                                    unit: "°C")
                        ValueColumn(label: "Wind",
                                    value: Fmt.number(weatherSnapshot.windSpeedKMH, decimals: 0),
                                    unit: "km/h")
                        ValueColumn(label: "Humidity",
                                    value: Fmt.number(weatherSnapshot.humidityPercent, decimals: 0),
                                    unit: "%")
                    }
                    ProvenanceBadge(source: weatherSnapshot.provenance.source,
                                    lastUpdated: weatherSnapshot.provenance.retrievedAt,
                                    isStale: weatherSnapshot.provenance.isCachedSnapshot)
                    Button("Remove snapshot") { self.weatherSnapshot = nil }
                        .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                } else {
                    let source = field ?? season?.field
                    if let snapshot = source?.cachedForecast {
                        ChipButton(title: isFetchingWeather ? "Adding…" : "Add from stored forecast",
                                   systemImage: "cloud.sun") {
                            attachWeather(from: snapshot)
                        }
                        Text("Uses the nearest hour in the forecast downloaded \(RelativeTime.string(from: snapshot.provenance.retrievedAt)).")
                            .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No forecast is stored for this field, so no snapshot can be attached. Nothing will be invented.")
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func attachWeather(from snapshot: ForecastSnapshot) {
        let nearest = snapshot.hours.min {
            abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date))
        }
        guard let nearest else { return }
        var provenance = snapshot.provenance
        provenance.sourceDetail = "Nearest forecast hour to \(Fmt.dateTime(nearest.time) ?? "")"
        weatherSnapshot = WeatherSnapshot(
            capturedAt: nearest.time,
            temperatureC: nearest.temperatureC,
            windSpeedKMH: nearest.windSpeedKMH,
            humidityPercent: nearest.humidityPercent,
            precipitationMM: nearest.precipitationMM,
            provenance: provenance
        )
    }

    private func save() {
        guard !isSaving else { return }
        errors = [:]
        saveError = nil

        if selectedLot == nil { errors["lot"] = "Choose the lot you actually used." }
        if productName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors["product"] = "Enter the product name."
        }
        let normalized = quantityText.replacingOccurrences(of: ",", with: ".")
        guard let quantity = Double(normalized) else {
            errors["quantity"] = quantityText.isEmpty ? "Enter the quantity used." : "Enter a valid number."
            return
        }
        if quantity <= 0 { errors["quantity"] = "Quantity must be greater than zero." }

        guard errors.isEmpty, let lot = selectedLot else { return }

        isSaving = true

        let application = InputApplication(
            productName: productName.trimmingCharacters(in: .whitespaces),
            quantity: quantity, unit: unit, date: date
        )
        application.category = category
        application.registrationNote = registrationNote.isEmpty ? nil : registrationNote
        application.lotID = lot.id
        application.lotLabelSnapshot = lot.displayLabel
        application.areaTreatedValue = Double(areaText.replacingOccurrences(of: ",", with: "."))
        application.areaUnit = areaUnit
        application.operatorName = operatorName.isEmpty ? nil : operatorName
        application.purpose = purpose.isEmpty ? nil : purpose
        application.weatherSnapshot = weatherSnapshot
        application.fieldID = (field ?? season?.field)?.id
        application.fieldNameSnapshot = (field ?? season?.field)?.name ?? ""
        application.season = season

        // Deduct the lot first: if stock is insufficient, nothing is written.
        do {
            try InventoryService.consume(
                lot: lot, quantity: quantity, unit: unit,
                applicationID: application.id,
                applicationLabel: application.productName,
                context: context
            )
        } catch {
            isSaving = false
            saveError = error.localizedDescription
            return
        }

        context.insert(application)
        season?.applications.append(application)

        AuditService.log(action: "Recorded", entityType: "Input application",
                         entityID: application.id,
                         summary: "Applied \(Fmt.quantity(quantity, unit.symbol) ?? "") of \(application.productName)",
                         details: "Lot \(lot.displayLabel) deducted",
                         context: context)

        do {
            try context.save()
            appState.confirm("Application recorded",
                             detail: "\(Fmt.quantity(quantity, unit.symbol) ?? "") deducted from \(lot.displayLabel)")
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Detail

struct ApplicationDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    var application: InputApplication

    @State private var showVoid = false
    @State private var voidReason = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if application.isVoided {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Label("Voided \(Fmt.dateTime(application.voidedAt) ?? "")",
                                  systemImage: "xmark.seal")
                                .font(TypeScale.headline(14)).foregroundStyle(Palette.burgundy)
                            Text(application.voidReason ?? "No reason recorded.")
                                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                            Text("The original figures are kept exactly as recorded.")
                                .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }

                CardShell {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "Application record")
                        ValueRow(label: "Product", value: application.productName)
                        ValueRow(label: "Category", value: application.category.rawValue)
                        ValueRow(label: "Quantity",
                                 value: Fmt.number(application.quantity, decimals: 2),
                                 unit: application.quantityUnit.symbol)
                        ValueRow(label: "Lot used", value: application.lotLabelSnapshot,
                                 unknownHint: "Not recorded")
                        ValueRow(label: "Area treated",
                                 value: Fmt.number(application.areaTreatedValue, decimals: 2),
                                 unit: application.areaUnit.symbol)
                        ValueRow(label: "Rate",
                                 value: Fmt.number(application.ratePerHectare, decimals: 2),
                                 unit: "\(application.quantityUnit.symbol)/ha",
                                 unknownHint: "Area unknown")
                        ValueRow(label: "Date", value: Fmt.dateTime(application.date))
                        ValueRow(label: "Operator", value: application.operatorName)
                        ValueRow(label: "Field", value: application.fieldNameSnapshot.isEmpty
                                 ? nil : application.fieldNameSnapshot)
                        ValueRow(label: "Purpose", value: application.purpose)
                        ValueRow(label: "Reference note", value: application.registrationNote)
                    }
                }

                if let weather = application.weatherSnapshot {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionHeader(title: "Weather at application")
                            HStack(spacing: Spacing.l) {
                                ValueColumn(label: "Temp",
                                            value: Fmt.number(weather.temperatureC, decimals: 1), unit: "°C")
                                ValueColumn(label: "Wind",
                                            value: Fmt.number(weather.windSpeedKMH, decimals: 0), unit: "km/h")
                                ValueColumn(label: "Humidity",
                                            value: Fmt.number(weather.humidityPercent, decimals: 0), unit: "%")
                                ValueColumn(label: "Rain",
                                            value: Fmt.number(weather.precipitationMM, decimals: 1), unit: "mm")
                            }
                            ProvenanceBadge(source: weather.provenance.source,
                                            lastUpdated: weather.provenance.retrievedAt,
                                            isStale: weather.provenance.isCachedSnapshot)
                        }
                    }
                }

                CardShell {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Label("This record cannot be edited", systemImage: "lock")
                            .font(TypeScale.headline(13)).foregroundStyle(Palette.gold)
                        Text("Application records are kept as written. If it is wrong, void it with a reason and record a corrected one — both stay in the history.")
                            .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Spacing.l)
        }
        .farmBackground()
        .navigationTitle("Application")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !application.isVoided {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Void…") { showVoid = true }.foregroundStyle(Palette.burgundy)
                }
            }
        }
        .alert("Void this record?", isPresented: $showVoid) {
            TextField("Reason", text: $voidReason)
            Button("Cancel", role: .cancel) { }
            Button("Void record", role: .destructive) { voidRecord() }
        } message: {
            Text("The record stays visible and marked as voided. Stock already deducted is not returned automatically — adjust the lot separately if needed.")
        }
    }

    private func voidRecord() {
        application.voidedAt = Date()
        application.voidReason = voidReason.isEmpty ? "No reason given" : voidReason
        AuditService.log(action: "Voided", entityType: "Input application",
                         entityID: application.id,
                         summary: "Application of \(application.productName) voided",
                         details: application.voidReason, context: context)
        try? context.save()
        voidReason = ""
        appState.confirm("Record voided", detail: "It stays in the history, marked as voided.")
    }
}
