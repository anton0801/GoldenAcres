//
//  InventoryView.swift
//  GoldenAcres
//
//  Screen 10. On-hand, reserved and available are shown as three distinct
//  numbers. Every movement is in the ledger, and a zeroed lot is archived
//  rather than erased.
//

import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Farm.createdAt) private var farms: [Farm]
    @Query(sort: \InventoryLot.itemName) private var lots: [InventoryLot]

    @State private var showEditor = false
    @State private var category: InventoryCategory?
    @State private var showArchived = false

    private var farm: Farm? { farms.first(where: { !$0.isArchived }) }

    private var visibleLots: [InventoryLot] {
        lots.filter { lot in
            (showArchived || !lot.isArchived) && (category == nil || lot.category == category)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if farm == nil {
                    HonestEmptyState(icon: "shippingbox", title: "No farm yet",
                                     message: "Inventory belongs to a farm. Create one first.")
                        .padding(.top, Spacing.xxl)
                } else if lots.isEmpty {
                    HonestEmptyState(
                        icon: "shippingbox",
                        title: "No stock recorded",
                        message: "Add a lot to reserve it for tasks and deduct it when an application is confirmed. Nothing is pre-filled.",
                        actionTitle: "Add stock",
                        action: { showEditor = true }
                    )
                    .padding(.top, Spacing.xl)
                } else {
                    summaryCard
                    categoryFilter
                    if visibleLots.isEmpty {
                        CardShell {
                            Text("No lots match this filter.")
                                .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        }
                    } else {
                        ForEach(visibleLots) { lot in
                            NavigationLink { LotDetailView(lot: lot) } label: {
                                LotCard(lot: lot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if lots.contains(where: \.isArchived) {
                        Button(showArchived ? "Hide archived lots" : "Show archived lots") {
                            withAnimation { showArchived.toggle() }
                        }
                        .font(TypeScale.body(13)).foregroundStyle(Palette.gold)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Inventory")
        .toolbar {
            if farm != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditor = true } label: {
                        Image(systemName: "plus").foregroundStyle(Palette.gold)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let farm { LotEditorView(farm: farm, lot: nil) }
        }
    }

    private var summaryCard: some View {
        let active = lots.filter { !$0.isArchived }
        let reserved = active.filter { $0.reservedQuantity > 0 }
        let valued = active.compactMap(\.totalValue)
        return GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.xl) {
                    KeyStat(value: "\(active.count)", unit: nil, label: "Active lots")
                    KeyStat(value: "\(reserved.count)", unit: nil, label: "With reservations")
                    Spacer()
                }
                Divider().overlay(Palette.hairline)
                if valued.isEmpty {
                    Text("No unit costs recorded, so no stock value is shown. It is not treated as zero.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack {
                        KeyStat(value: Fmt.currency(valued.reduce(0, +),
                                                    code: farm?.currencyCode ?? "USD"),
                                unit: nil, label: "Value of costed lots")
                        Spacer()
                    }
                    if valued.count < active.count {
                        Text("Covers \(valued.count) of \(active.count) lots — the rest have no unit cost.")
                            .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            .padding(Spacing.l)
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                FilterChip(title: "All", isOn: category == nil) { category = nil }
                ForEach(InventoryCategory.allCases) { item in
                    if lots.contains(where: { $0.category == item }) {
                        FilterChip(title: item.rawValue, isOn: category == item) {
                            category = category == item ? nil : item
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Lot card

struct LotCard: View {
    var lot: InventoryLot

    var body: some View {
        GoldPlate(accent: lot.isExpired ? Palette.burgundy : Palette.gold) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lot.itemName)
                            .font(TypeScale.headline(15)).foregroundStyle(Palette.cream)
                        Text("Lot \(lot.lotCode.isEmpty ? "not coded" : lot.lotCode) · \(lot.category.rawValue)")
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    if lot.isArchived {
                        StatusPill(text: "archived", tone: .neutral)
                    } else if lot.isExpired {
                        StatusPill(text: "expired", tone: .risk)
                    } else if lot.expiresSoon {
                        StatusPill(text: "expiring", tone: .warning)
                    }
                }

                Divider().overlay(Palette.hairline)

                HStack(spacing: Spacing.l) {
                    ValueColumn(label: "On hand",
                                value: Fmt.number(lot.onHandQuantity, decimals: 2),
                                unit: lot.unit.symbol)
                    ValueColumn(label: "Reserved",
                                value: Fmt.number(lot.reservedQuantity, decimals: 2),
                                unit: lot.unit.symbol)
                    ValueColumn(label: "Available",
                                value: Fmt.number(lot.availableQuantity, decimals: 2),
                                unit: lot.unit.symbol)
                    Spacer()
                }

                if lot.reservedQuantity > lot.onHandQuantity {
                    Label("More is reserved than is on hand.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(Palette.burgundy)
                }
            }
            .padding(Spacing.l)
        }
    }
}

// MARK: - Lot detail

struct LotDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @Query private var allLots: [InventoryLot]

    var lot: InventoryLot

    @State private var showEditor = false
    @State private var showAdjust = false
    @State private var showMove = false
    @State private var showDelete = false
    @State private var adjustText = ""
    @State private var adjustReason = ""
    @State private var moveText = ""
    @State private var actionError: String?

    private var duplicates: [InventoryLot] {
        InventoryService.duplicateCandidates(for: lot, in: allLots)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let actionError {
                    ErrorBanner(title: "Could not apply", message: actionError,
                                onRetry: nil, onDismiss: { self.actionError = nil })
                }

                if !duplicates.isEmpty {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Label("Possible duplicate lot", systemImage: "doc.on.doc")
                                .font(TypeScale.headline(14)).foregroundStyle(Palette.amber)
                            Text("\(duplicates.count) other lot(s) share this item name and lot code. Nothing has been merged — review them and decide.")
                                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(duplicates) { duplicate in
                                Text("— \(duplicate.displayLabel): \(Fmt.quantity(duplicate.onHandQuantity, duplicate.unit.symbol) ?? "")")
                                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                }

                balanceCard
                detailsCard
                ledgerCard
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle(lot.itemName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
                    Button { showAdjust = true } label: {
                        Label("Adjust quantity", systemImage: "plusminus")
                    }
                    Button { showMove = true } label: {
                        Label("Move storage", systemImage: "arrow.left.arrow.right")
                    }
                    if lot.isArchived {
                        Button {
                            InventoryService.restore(lot: lot, context: context)
                            try? context.save()
                            appState.confirm("Lot restored")
                        } label: { Label("Restore lot", systemImage: "arrow.uturn.backward") }
                    } else {
                        Button {
                            InventoryService.archive(lot: lot, reason: "Archived by user", context: context)
                            try? context.save()
                            appState.confirm("Lot archived", detail: "Movement history kept.")
                        } label: { Label("Archive lot", systemImage: "archivebox") }
                    }
                    Divider()
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Delete…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let farm = lot.farm { LotEditorView(farm: farm, lot: lot) }
        }
        .alert("Adjust quantity", isPresented: $showAdjust) {
            TextField("New on-hand quantity", text: $adjustText)
                .keyboardType(.decimalPad)
            TextField("Reason (required)", text: $adjustReason)
            Button("Cancel", role: .cancel) { }
            Button("Apply") { applyAdjustment() }
        } message: {
            Text("Current on hand: \(Fmt.quantity(lot.onHandQuantity, lot.unit.symbol) ?? ""). A reason is required so the ledger stays explainable.")
        }
        .alert("Move storage", isPresented: $showMove) {
            TextField("New storage location", text: $moveText)
            Button("Cancel", role: .cancel) { }
            Button("Move") {
                guard !moveText.isEmpty else { return }
                InventoryService.move(lot: lot, to: moveText, context: context)
                try? context.save()
                appState.confirm("Lot moved", detail: moveText)
                moveText = ""
            }
        }
        .sheet(isPresented: $showDelete) { deleteSheet }
    }

    private var balanceCard: some View {
        GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.xl) {
                    KeyStat(value: Fmt.number(lot.onHandQuantity, decimals: 2),
                            unit: lot.unit.symbol, label: "On hand")
                    KeyStat(value: Fmt.number(lot.reservedQuantity, decimals: 2),
                            unit: lot.unit.symbol, label: "Reserved", tone: Palette.amber)
                    KeyStat(value: Fmt.number(lot.availableQuantity, decimals: 2),
                            unit: lot.unit.symbol, label: "Available", tone: Palette.positive)
                }
                Text("Available = on hand − reserved. Reserving for a task lowers availability only; a confirmed application lowers on hand.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.l)
        }
    }

    private var detailsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Lot details")
                ValueRow(label: "Category", value: lot.category.rawValue)
                ValueRow(label: "Lot code", value: lot.lotCode.isEmpty ? nil : lot.lotCode)
                ValueRow(label: "Storage", value: lot.storageLocation)
                ValueRow(label: "Received", value: Fmt.date(lot.receivedDate))
                ValueRow(label: "Expiry", value: Fmt.date(lot.expiryDate), unknownHint: "None set")
                ValueRow(label: "Supplier", value: lot.supplier)
                ValueRow(label: "Unit cost",
                         value: Fmt.currency(lot.unitCost, code: lot.farm?.currencyCode ?? "USD"))
                ValueRow(label: "Value of stock",
                         value: Fmt.currency(lot.totalValue, code: lot.farm?.currencyCode ?? "USD"),
                         unknownHint: "No unit cost")
                if let safety = lot.safetyFileName {
                    ValueRow(label: "Safety file",
                             value: PhotoStore.exists(safety) ? safety : "\(safety) (missing)")
                }
                if let provenance = lot.labelScanProvenance {
                    Divider().overlay(Palette.hairline)
                    ProvenanceBadge(source: provenance.source, lastUpdated: provenance.retrievedAt)
                    Text("Some fields were filled from a scanned label and confirmed by you on save.")
                        .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var ledgerCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Movement ledger",
                              subtitle: "Every change, with the balance it produced.")
                if lot.movements.isEmpty {
                    Text("No movements recorded.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                } else {
                    let sorted = lot.movements.sorted { $0.timestamp > $1.timestamp }
                    ForEach(sorted) { movement in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(movement.type.rawValue)
                                    .font(TypeScale.headline(13)).foregroundStyle(Palette.cream)
                                Spacer()
                                Text(Fmt.quantity(movement.quantity, movement.unit.symbol) ?? "")
                                    .font(TypeScale.mono(12)).foregroundStyle(Palette.gold)
                            }
                            HStack {
                                Text(Fmt.dateTime(movement.timestamp) ?? "")
                                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                                Spacer()
                                Text("→ on hand \(Fmt.number(movement.balanceAfterOnHand, decimals: 2) ?? "?"), reserved \(Fmt.number(movement.balanceAfterReserved, decimals: 2) ?? "?")")
                                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                            }
                            if let reason = movement.reason {
                                Text(reason).font(.system(size: 11))
                                    .foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 3)
                        if movement.id != sorted.last?.id { Divider().overlay(Palette.hairline) }
                    }
                }
            }
        }
    }

    private var deleteSheet: some View {
        var consequences: [String] = []
        if !lot.movements.isEmpty {
            consequences.append("\(lot.movements.count) ledger entries will be deleted with the lot.")
        }
        if lot.reservedQuantity > 0 {
            consequences.append("\(Fmt.quantity(lot.reservedQuantity, lot.unit.symbol) ?? "") is reserved for tasks; those tasks will keep the requirement but lose the link.")
        }
        let consumed = lot.movements.contains { $0.type == .consume }
        if consumed {
            consequences.append("This lot has been applied to a field. Application records keep a copy of the lot label and will remain.")
        }

        return ConsequenceSheet(
            title: "Delete lot “\(lot.displayLabel)”?",
            entityName: lot.displayLabel,
            consequences: consequences,
            canDelete: !consumed,
            deleteBlockedReason: consumed
                ? "This lot has been consumed by an application record, so its history must stay. Archive it instead."
                : nil,
            onArchive: {
                InventoryService.archive(lot: lot, reason: "Archived instead of deleting", context: context)
                try? context.save()
                showDelete = false
                appState.confirm("Lot archived", detail: "Ledger kept intact.")
            },
            onDetach: nil,
            onDelete: {
                AuditService.log(action: "Deleted", entityType: "Inventory lot", entityID: lot.id,
                                 summary: "Lot \(lot.displayLabel) deleted", context: context)
                lot.farm?.inventoryLots.removeAll { $0.id == lot.id }
                context.delete(lot)
                try? context.save()
                showDelete = false
                appState.confirm("Lot deleted")
            },
            onCancel: { showDelete = false }
        )
    }

    private func applyAdjustment() {
        guard let newValue = Double(adjustText.replacingOccurrences(of: ",", with: ".")) else {
            actionError = "Enter a valid quantity."
            return
        }
        do {
            try InventoryService.adjust(lot: lot, newOnHand: newValue,
                                        reason: adjustReason, context: context)
            try context.save()
            appState.confirm("Stock adjusted",
                             detail: "Now \(Fmt.quantity(newValue, lot.unit.symbol) ?? "")")
            adjustText = ""
            adjustReason = ""
        } catch {
            actionError = error.localizedDescription
        }
    }
}
