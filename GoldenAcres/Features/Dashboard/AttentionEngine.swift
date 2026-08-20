//
//  AttentionEngine.swift
//  GoldenAcres
//
//  Derives "needs attention" items strictly from stored records: a missing
//  required value, an overdue task, a forecast that changed under a plan, a
//  lot past its date. Nothing here is a judgement about the crop.
//

import SwiftUI
import SwiftData

struct AttentionItem: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var icon: String
    var tone: PillTone
    var fieldID: UUID?
    var sortWeight: Int
}

@MainActor
enum AttentionEngine {

    static func items(farm: Farm, tasks: [FarmTask], lots: [InventoryLot]) -> [AttentionItem] {
        var items: [AttentionItem] = []

        // Fields missing information needed by other screens.
        for field in farm.activeFields {
            if field.areaValue == nil {
                items.append(AttentionItem(
                    title: "\(field.name): area not set",
                    detail: "Irrigation volume and yield per area cannot be calculated until the area is entered.",
                    icon: "ruler", tone: .warning, fieldID: field.id, sortWeight: 2))
            }
            if field.resolvedCoordinate == nil {
                items.append(AttentionItem(
                    title: "\(field.name): no coordinates",
                    detail: "A forecast cannot be requested without a location. Drop a pin or import a boundary.",
                    icon: "location.slash", tone: .neutral, fieldID: field.id, sortWeight: 4))
            }

            // Stale cached forecast presented honestly.
            if let snapshot = field.cachedForecast, snapshot.provenance.isStale(maxAge: 12 * 3600) {
                items.append(AttentionItem(
                    title: "\(field.name): forecast is out of date",
                    detail: "Last updated \(RelativeTime.string(from: snapshot.provenance.retrievedAt)). Refresh before relying on a work window.",
                    icon: "clock.badge.exclamationmark", tone: .warning,
                    fieldID: field.id, sortWeight: 3))
            }

            for season in field.seasons where season.status == .active {
                if season.actualPlantingDate == nil {
                    items.append(AttentionItem(
                        title: "\(season.displayTitle): planting date missing",
                        detail: "The season is active but no actual planting date was recorded.",
                        icon: "calendar.badge.exclamationmark", tone: .warning,
                        fieldID: field.id, sortWeight: 2))
                }
                if season.seedLotID == nil {
                    items.append(AttentionItem(
                        title: "\(season.displayTitle): no seed lot linked",
                        detail: "Traceability will show a gap from harvest back to seed.",
                        icon: "leaf", tone: .neutral, fieldID: field.id, sortWeight: 5))
                }
            }

            // Soil tests still in draft never reach analytics.
            let drafts = field.soilTests.filter { !$0.isConfirmed }
            if !drafts.isEmpty {
                items.append(AttentionItem(
                    title: "\(field.name): \(drafts.count) unconfirmed soil test(s)",
                    detail: "Draft values are excluded from every comparison until you confirm them.",
                    icon: "testtube.2", tone: .neutral, fieldID: field.id, sortWeight: 4))
            }
        }

        // Tasks.
        let overdue = tasks.filter(\.isOverdue)
        if !overdue.isEmpty {
            items.append(AttentionItem(
                title: "\(overdue.count) task(s) overdue",
                detail: overdue.prefix(3).map(\.title).joined(separator: ", "),
                icon: "exclamationmark.triangle", tone: .risk, fieldID: nil, sortWeight: 0))
        }

        let flagged = tasks.filter(\.weatherReviewNeeded)
        if !flagged.isEmpty {
            items.append(AttentionItem(
                title: "\(flagged.count) task(s) need a weather review",
                detail: "The forecast changed after these were planned. They have not been moved for you.",
                icon: "cloud.sun.bolt", tone: .warning, fieldID: nil, sortWeight: 1))
        }

        let blocked = tasks.filter { $0.status == .blocked }
        if !blocked.isEmpty {
            items.append(AttentionItem(
                title: "\(blocked.count) task(s) blocked",
                detail: blocked.compactMap(\.blockedReason).first ?? "No reason recorded.",
                icon: "hand.raised", tone: .risk, fieldID: nil, sortWeight: 1))
        }

        // Inventory.
        let expired = lots.filter { !$0.isArchived && $0.isExpired }
        if !expired.isEmpty {
            items.append(AttentionItem(
                title: "\(expired.count) lot(s) past expiry",
                detail: expired.prefix(3).map(\.displayLabel).joined(separator: ", "),
                icon: "calendar.badge.minus", tone: .risk, fieldID: nil, sortWeight: 1))
        }
        let expiring = lots.filter { !$0.isArchived && $0.expiresSoon }
        if !expiring.isEmpty {
            items.append(AttentionItem(
                title: "\(expiring.count) lot(s) expire within 30 days",
                detail: expiring.prefix(3).map(\.displayLabel).joined(separator: ", "),
                icon: "hourglass", tone: .warning, fieldID: nil, sortWeight: 3))
        }
        let overReserved = lots.filter { !$0.isArchived && $0.reservedQuantity > $0.onHandQuantity }
        if !overReserved.isEmpty {
            items.append(AttentionItem(
                title: "\(overReserved.count) lot(s) reserved beyond stock",
                detail: "More is promised to tasks than is physically on hand.",
                icon: "exclamationmark.arrow.circlepath", tone: .risk, fieldID: nil, sortWeight: 0))
        }

        // Harvest batches left open.
        let openBatches = farm.fields
            .flatMap(\.seasons)
            .flatMap(\.harvestBatches)
            .filter { !$0.isClosed }
        if !openBatches.isEmpty {
            items.append(AttentionItem(
                title: "\(openBatches.count) harvest batch(es) still open",
                detail: "Season totals stay provisional until these are closed.",
                icon: "basket", tone: .warning, fieldID: nil, sortWeight: 3))
        }

        // Loads with an inconsistent split.
        let badLoads = openBatches.flatMap(\.loads).filter { !$0.isConsistent }
        if !badLoads.isEmpty {
            items.append(AttentionItem(
                title: "\(badLoads.count) harvest load(s) don't add up",
                detail: "Marketable plus waste exceeds the gross quantity recorded.",
                icon: "sum", tone: .risk, fieldID: nil, sortWeight: 0))
        }

        return items.sorted { lhs, rhs in
            if lhs.sortWeight != rhs.sortWeight { return lhs.sortWeight < rhs.sortWeight }
            return lhs.title < rhs.title
        }
    }
}

// MARK: - Alert review screen

struct AlertReviewView: View {
    @Environment(\.dismiss) private var dismiss
    var farm: Farm

    @Query private var tasks: [FarmTask]
    @Query private var lots: [InventoryLot]

    var body: some View {
        NavigationStack {
            ScrollView {
                let items = AttentionEngine.items(farm: farm, tasks: tasks, lots: lots)
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("Every item below comes from a record you entered, or from a required value that is still missing.")
                        .font(TypeScale.body(13))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if items.isEmpty {
                        HonestEmptyState(
                            icon: "bell.slash",
                            title: "No alerts",
                            message: "Nothing in your records is currently flagged. This is not an assessment of field conditions."
                        )
                    } else {
                        ForEach(items) { item in
                            CardShell {
                                HStack(alignment: .top, spacing: Spacing.m) {
                                    Image(systemName: item.icon)
                                        .foregroundStyle(item.tone.color)
                                        .font(.system(size: 15))
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(TypeScale.headline(14))
                                            .foregroundStyle(Palette.cream)
                                        Text(item.detail)
                                            .font(TypeScale.body(12))
                                            .foregroundStyle(Palette.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.gold)
                }
            }
        }
    }
}
