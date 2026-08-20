//
//  HarvestService.swift
//  GoldenAcres
//
//  Loads roll up into a batch; the batch total is always derived from its
//  lines. Closing takes a snapshot. Anything changed after closing is appended
//  as a revision — the original figures are never edited away.
//

import Foundation
import SwiftData

enum HarvestError: LocalizedError {
    case nonPositiveGross
    case splitExceedsGross(gross: Double, marketable: Double, waste: Double, unit: String)
    case mixedUnits(existing: String, incoming: String)
    case batchClosed
    case duplicateSubmission

    var errorDescription: String? {
        switch self {
        case .nonPositiveGross:
            return "Gross quantity must be greater than zero."
        case .splitExceedsGross(let gross, let marketable, let waste, let unit):
            let sum = Fmt.number(marketable + waste, decimals: 2) ?? "0"
            return "Marketable + waste (\(sum) \(unit)) cannot exceed gross (\(Fmt.number(gross, decimals: 2) ?? "0") \(unit))."
        case .mixedUnits(let existing, let incoming):
            return "This batch records loads in \(existing). Add \(incoming) as a separate batch so totals stay meaningful."
        case .batchClosed:
            return "This batch is closed. Reopen it or record a revision instead."
        case .duplicateSubmission:
            return "That load was already saved."
        }
    }
}

@MainActor
enum HarvestService {

    // MARK: - Loads

    @discardableResult
    static func addLoad(to batch: HarvestBatch,
                        gross: Double,
                        marketable: Double?,
                        waste: Double?,
                        unit: QuantityUnit,
                        date: Date,
                        notes: String?,
                        recordedBy: String?,
                        idempotencyKey: String,
                        context: ModelContext) throws -> HarvestLoad {

        guard !batch.isClosed else { throw HarvestError.batchClosed }
        guard gross > 0 else { throw HarvestError.nonPositiveGross }

        // A repeated submit with the same key is a no-op, not a second load.
        if let existing = batch.loads.first(where: { $0.idempotencyKey == idempotencyKey }) {
            _ = existing
            throw HarvestError.duplicateSubmission
        }

        if let existingUnit = batch.commonUnit, existingUnit != unit {
            throw HarvestError.mixedUnits(existing: existingUnit.symbol, incoming: unit.symbol)
        }

        let m = marketable ?? 0
        let w = waste ?? 0
        guard m + w <= gross + 0.0001 else {
            throw HarvestError.splitExceedsGross(gross: gross, marketable: m,
                                                 waste: w, unit: unit.symbol)
        }

        let load = HarvestLoad(grossQuantity: gross, unit: unit, date: date, batch: batch)
        load.marketableQuantity = marketable
        load.wasteQuantity = waste
        load.notes = notes
        load.recordedBy = recordedBy
        load.idempotencyKey = idempotencyKey
        context.insert(load)
        batch.loads.append(load)

        AuditService.log(action: "Added load", entityType: "Harvest batch", entityID: batch.id,
                         summary: "Load of \(Fmt.number(gross, decimals: 2) ?? "0") \(unit.symbol) added to \(batch.batchCode)",
                         context: context)
        return load
    }

    static func removeLoad(_ load: HarvestLoad, from batch: HarvestBatch, context: ModelContext) {
        batch.loads.removeAll { $0.id == load.id }
        context.delete(load)
        AuditService.log(action: "Removed load", entityType: "Harvest batch", entityID: batch.id,
                         summary: "A load was removed from \(batch.batchCode)", context: context)
    }

    // MARK: - Closing

    static func close(batch: HarvestBatch, context: ModelContext) {
        batch.status = .closed
        batch.closedAt = Date()
        AuditService.log(action: "Closed", entityType: "Harvest batch", entityID: batch.id,
                         summary: "Batch \(batch.batchCode) closed with \(batch.loads.count) load(s)",
                         context: context)
    }

    static func reopen(batch: HarvestBatch, reason: String, context: ModelContext) {
        batch.status = .open
        batch.revisions.append(
            HarvestRevision(timestamp: Date(), reason: reason,
                            changeSummary: "Batch reopened after closing", author: nil)
        )
        AuditService.log(action: "Reopened", entityType: "Harvest batch", entityID: batch.id,
                         summary: "Batch \(batch.batchCode) reopened", details: reason,
                         context: context)
    }

    /// Records a correction to a closed batch without rewriting its history.
    static func addRevision(to batch: HarvestBatch,
                            reason: String,
                            changeSummary: String,
                            context: ModelContext) {
        batch.revisions.append(
            HarvestRevision(timestamp: Date(), reason: reason,
                            changeSummary: changeSummary, author: nil)
        )
        AuditService.log(action: "Revised", entityType: "Harvest batch", entityID: batch.id,
                         summary: "Revision recorded on \(batch.batchCode)",
                         details: changeSummary, context: context)
    }

    // MARK: - Season close

    /// Builds the immutable snapshot stored on the season at close.
    static func snapshot(for season: CropSeason) -> SeasonSnapshot {
        var gaps: [String] = []

        let batches = season.harvestBatches
        let allLoads = batches.flatMap(\.loads)
        let units = Set(allLoads.map(\.unitRaw))

        var gross: Double?
        var marketable: Double?
        var waste: Double?
        var unitRaw: String?

        if units.count == 1, let raw = units.first {
            unitRaw = raw
            gross = allLoads.map(\.grossQuantity).reduce(0, +)
            let m = allLoads.compactMap(\.marketableQuantity)
            marketable = m.isEmpty ? nil : m.reduce(0, +)
            let w = allLoads.compactMap(\.wasteQuantity)
            waste = w.isEmpty ? nil : w.reduce(0, +)
            if m.count < allLoads.count {
                gaps.append("\(allLoads.count - m.count) load(s) have no marketable quantity recorded.")
            }
        } else if units.count > 1 {
            gaps.append("Loads use \(units.count) different units, so no season total can be calculated.")
        } else {
            gaps.append("No harvest loads were recorded for this season.")
        }

        if batches.contains(where: { !$0.isClosed }) {
            gaps.append("\(batches.filter { !$0.isClosed }.count) harvest batch(es) are still open.")
        }

        let openTasks = season.tasks.filter { $0.status.isOpen }
        if !openTasks.isEmpty {
            gaps.append("\(openTasks.count) task(s) were still open at close.")
        }

        if season.field?.areaValue == nil {
            gaps.append("Field area is unknown, so yield per area cannot be derived.")
        }

        let water = season.field?.irrigationPlans
            .compactMap { $0.totalActualLiters() }
            .reduce(0, +)

        return SeasonSnapshot(
            closedAt: Date(),
            marketableQuantity: marketable,
            grossQuantity: gross,
            wasteQuantity: waste,
            quantityUnitRaw: unitRaw,
            harvestedAreaSquareMeters: season.targetAreaSquareMeters ?? season.field?.areaSquareMeters,
            taskCountPlanned: season.tasks.count,
            taskCountCompleted: season.tasks.filter { $0.status == .completed }.count,
            applicationCount: season.applications.filter { !$0.isVoided }.count,
            recordedWaterLiters: (water ?? 0) > 0 ? water : nil,
            gaps: gaps
        )
    }

    static func closeSeason(_ season: CropSeason, context: ModelContext) {
        season.closingSnapshot = snapshot(for: season)
        season.status = .closed
        season.closedAt = Date()
        season.updatedAt = Date()
        AuditService.log(action: "Closed season", entityType: "Crop season", entityID: season.id,
                         summary: "Season \(season.displayTitle) closed", context: context)
    }
}
