//
//  LotEditorView.swift
//  GoldenAcres
//
//  Adding or editing a stock lot. A label scan fills a draft the user must
//  confirm — the app never asserts a product is approved for a use.
//

import SwiftUI
import SwiftData
import PhotosUI

struct LotEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var farm: Farm
    var lot: InventoryLot?

    @State private var itemName = ""
    @State private var category: InventoryCategory = .other
    @State private var lotCode = ""
    @State private var quantityText = ""
    @State private var unit: QuantityUnit = .kilogram
    @State private var storage = ""
    @State private var receivedDate: Date? = Date()
    @State private var expiryDate: Date?
    @State private var costText = ""
    @State private var supplier = ""

    @State private var scanItem: PhotosPickerItem?
    @State private var scanProvenance: Provenance?
    @State private var scannedLines: [String] = []
    @State private var isScanning = false

    @State private var errors: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String?

    private var isEditing: Bool { lot != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let saveError {
                        ErrorBanner(title: "Could not save", message: saveError,
                                    onRetry: { save() }, onDismiss: { self.saveError = nil })
                    }

                    if !isEditing { scanCard }
                    detailsCard
                    quantityCard
                    commercialCard

                    AmberButton(title: isEditing ? "Save lot" : "Add stock",
                                systemImage: "checkmark", isBusy: isSaving) { save() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle(isEditing ? "Edit lot" : "Add stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear(perform: load)
            .onChange(of: scanItem) { _, item in scanLabel(item) }
        }
    }

    // MARK: - Cards

    private var scanCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Scan label",
                              subtitle: "Reads text from a photo to prefill the form.")
                PhotosPicker(selection: $scanItem, matching: .images) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.viewfinder").font(.system(size: 11, weight: .bold))
                        Text(isScanning ? "Reading…" : "Scan a label")
                            .font(TypeScale.stamp(11)).tracking(0.6)
                    }
                    .foregroundStyle(Palette.gold)
                    .padding(.vertical, 7).padding(.horizontal, Spacing.m)
                    .background(Capsule().fill(Palette.gold.opacity(0.12))
                        .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.35), lineWidth: 1)))
                }

                if isScanning { LoadingBlock(lines: 2) }

                if !scannedLines.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Text read from the label").stampLabel(Palette.textSecondary)
                        ForEach(scannedLines.prefix(6), id: \.self) { line in
                            Button {
                                if itemName.isEmpty { itemName = line }
                                else if lotCode.isEmpty { lotCode = line }
                            } label: {
                                HStack {
                                    Text(line).font(.system(size: 11))
                                        .foregroundStyle(Palette.cream).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.up.left.circle")
                                        .font(.system(size: 11)).foregroundStyle(Palette.gold)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let scanProvenance {
                        ProvenanceBadge(source: scanProvenance.source,
                                        lastUpdated: scanProvenance.retrievedAt)
                    }
                    Text("Tap a line to use it. Nothing is filled in automatically, and the app makes no claim about what this product is approved for — check the official label.")
                        .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var detailsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateTextField(label: "Item", placeholder: "e.g. Urea 46%",
                               text: $itemName, isRequired: true, error: errors["item"])
                PlateField(label: "Category", isRequired: true) {
                    Picker("", selection: $category) {
                        ForEach(InventoryCategory.allCases) {
                            Label($0.rawValue, systemImage: $0.icon).tag($0)
                        }
                    }
                    .pickerStyle(.menu).tint(Palette.gold)
                }
                PlateTextField(label: "Lot code", placeholder: "Supplier batch or your own code",
                               text: $lotCode,
                               helper: "Used to spot duplicates and to trace applications back.")
                PlateTextField(label: "Storage location", placeholder: "Optional", text: $storage)
            }
        }
    }

    private var quantityCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top, spacing: Spacing.m) {
                    PlateTextField(label: isEditing ? "On-hand quantity" : "Quantity received",
                                   placeholder: "0", text: $quantityText,
                                   isRequired: true, keyboard: .decimalPad, error: errors["quantity"])
                    PlateField(label: "Unit", isRequired: true) {
                        Picker("", selection: $unit) {
                            ForEach(QuantityUnit.allCases) { Text($0.symbol).tag($0) }
                        }
                        .pickerStyle(.menu).tint(Palette.gold)
                    }
                    .frame(width: 110)
                }
                if isEditing {
                    Text("Editing here renames and re-units the lot. To correct the amount, use “Adjust quantity”, which records a reason in the ledger.")
                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                OptionalDateRow(label: "Received date", date: $receivedDate)
                OptionalDateRow(label: "Expiry date", date: $expiryDate)
                if let error = errors["dates"] {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(Palette.burgundy)
                }
            }
        }
    }

    private var commercialCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateTextField(label: "Unit cost (\(farm.currencyCode))",
                               placeholder: "Optional",
                               text: $costText, keyboard: .decimalPad,
                               helper: "Without a cost, this lot is left out of cost totals rather than counted as free.")
                PlateTextField(label: "Supplier", placeholder: "Optional", text: $supplier)
            }
        }
    }

    // MARK: - Logic

    private func load() {
        guard let lot else { return }
        itemName = lot.itemName
        category = lot.category
        lotCode = lot.lotCode
        quantityText = String(lot.onHandQuantity)
        unit = lot.unit
        storage = lot.storageLocation ?? ""
        receivedDate = lot.receivedDate
        expiryDate = lot.expiryDate
        costText = lot.unitCost.map { String($0) } ?? ""
        supplier = lot.supplier ?? ""
        scanProvenance = lot.labelScanProvenance
    }

    private func scanLabel(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isScanning = true
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run { isScanning = false }
                return
            }
            let result = await SoilReportParser.parse(image: image)
            await MainActor.run {
                scannedLines = result.rawText
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.count > 2 }
                scanProvenance = result.provenance
                isScanning = false
                scanItem = nil
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        errors = [:]
        saveError = nil

        if itemName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors["item"] = "Enter the item name."
        }
        let normalized = quantityText.replacingOccurrences(of: ",", with: ".")
        guard let quantity = Double(normalized) else {
            errors["quantity"] = quantityText.isEmpty ? "Enter a quantity." : "Enter a valid number."
            return
        }
        if quantity < 0 { errors["quantity"] = "Quantity cannot be negative." }
        if let received = receivedDate, let expiry = expiryDate, expiry < received {
            errors["dates"] = "Expiry is before the received date."
        }
        guard errors.isEmpty else { return }

        isSaving = true

        if let existing = lot {
            existing.itemName = itemName.trimmingCharacters(in: .whitespaces)
            existing.category = category
            existing.lotCode = lotCode.trimmingCharacters(in: .whitespaces)
            existing.unit = unit
            existing.storageLocation = storage.isEmpty ? nil : storage
            existing.receivedDate = receivedDate
            existing.expiryDate = expiryDate
            existing.unitCost = Double(costText.replacingOccurrences(of: ",", with: "."))
            existing.supplier = supplier.isEmpty ? nil : supplier
            existing.updatedAt = Date()

            // A quantity change from this form is still a ledger event.
            if abs(existing.onHandQuantity - quantity) > 0.0001 {
                do {
                    try InventoryService.adjust(lot: existing, newOnHand: quantity,
                                                reason: "Edited on the lot form", context: context)
                } catch {
                    isSaving = false
                    saveError = error.localizedDescription
                    return
                }
            }

            AuditService.log(action: "Updated", entityType: "Inventory lot", entityID: existing.id,
                             summary: "Lot \(existing.displayLabel) updated", context: context)
        } else {
            let newLot = InventoryLot(itemName: itemName.trimmingCharacters(in: .whitespaces),
                                      lotCode: lotCode.trimmingCharacters(in: .whitespaces),
                                      quantity: 0, unit: unit)
            newLot.category = category
            newLot.storageLocation = storage.isEmpty ? nil : storage
            newLot.receivedDate = receivedDate
            newLot.expiryDate = expiryDate
            newLot.unitCost = Double(costText.replacingOccurrences(of: ",", with: "."))
            newLot.supplier = supplier.isEmpty ? nil : supplier
            newLot.labelScanProvenance = scanProvenance
            newLot.farm = farm
            context.insert(newLot)
            farm.inventoryLots.append(newLot)

            if quantity > 0 {
                do {
                    try InventoryService.receive(lot: newLot, quantity: quantity, unit: unit,
                                                 reason: "Initial stock received", context: context)
                } catch {
                    isSaving = false
                    saveError = error.localizedDescription
                    return
                }
            }
        }

        do {
            try context.save()
            appState.confirm(isEditing ? "Lot saved" : "Stock added",
                             detail: "\(itemName) · \(Fmt.quantity(quantity, unit.symbol) ?? "")")
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}
