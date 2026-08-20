//
//  ExportService.swift
//  GoldenAcres
//
//  Reports are assembled only from stored records. Every export carries
//  generated_at, data_range and version, and lists its gaps explicitly — a
//  report with missing data says so instead of looking complete.
//

import Foundation
import SwiftData

struct ExportDocument {
    var filename: String
    var text: String
    var metadata: ExportMetadata

    func writeToTemporaryFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try text.data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

@MainActor
enum ExportService {
    static let formatVersion = "1.0"

    // MARK: - Season report

    static func seasonReport(for season: CropSeason, allLots: [InventoryLot]) -> ExportDocument {
        let metrics = SeasonInsights.metrics(for: season, allLots: allLots)
        var lines: [String] = []
        var gaps = metrics.gaps

        let dates = collectDates(for: season)

        lines.append("# Season report — \(season.displayTitle)")
        lines.append("")
        lines.append("Field: \(season.field?.name ?? season.field?.name ?? "Detached from field")")
        lines.append("Farm: \(season.field?.farm?.name ?? "Unknown")")
        lines.append("Status: \(season.status.label)")
        lines.append("Planted: \(Fmt.date(season.actualPlantingDate) ?? "Not recorded")")
        lines.append("Closed: \(Fmt.date(season.closedAt) ?? "Not closed")")
        lines.append("Area: \(Fmt.quantity(season.targetAreaValue, season.targetAreaUnit.symbol) ?? "Unknown")")
        lines.append("")

        lines.append("## Harvest")
        if let unit = metrics.unit {
            lines.append("- Gross: \(Fmt.quantity(metrics.gross, unit.symbol) ?? "Unknown")")
            lines.append("- Marketable: \(Fmt.quantity(metrics.marketable, unit.symbol) ?? "Unknown")")
            lines.append("- Waste: \(Fmt.quantity(metrics.waste, unit.symbol) ?? "Unknown")")
            if let yield = metrics.yieldPerHectare {
                lines.append("- Yield per hectare: \(Fmt.number(yield, decimals: 1) ?? "") \(unit.symbol)/ha")
            } else {
                lines.append("- Yield per hectare: cannot be derived")
            }
        } else {
            lines.append("- No single-unit harvest total available.")
        }
        lines.append("")

        lines.append("## Batches")
        if season.harvestBatches.isEmpty {
            lines.append("- None recorded.")
        }
        for batch in season.harvestBatches.sorted(by: { $0.startedAt < $1.startedAt }) {
            let unitSymbol = batch.commonUnit?.symbol
            lines.append("- Batch \(batch.batchCode) · \(batch.status.rawValue) · \(batch.loads.count) load(s) · gross \(Fmt.quantity(batch.totalGross, unitSymbol) ?? "unknown")")
            if !batch.revisions.isEmpty {
                for revision in batch.revisions {
                    lines.append("  - Revision \(Fmt.dateTime(revision.timestamp) ?? ""): \(revision.changeSummary) (\(revision.reason))")
                }
            }
        }
        lines.append("")

        lines.append("## Tasks")
        lines.append("- Planned: \(metrics.plannedTasks), completed: \(metrics.completedTasks), late: \(metrics.lateTasks)")
        for task in season.tasks.sorted(by: { ($0.dueStart ?? .distantPast) < ($1.dueStart ?? .distantPast) }) {
            lines.append("- [\(task.status.rawValue)] \(task.title) · due \(task.dueDisplay ?? "not set") · \(task.assignee ?? "unassigned")")
        }
        lines.append("")

        lines.append("## Input applications")
        let applications = season.applications.sorted { $0.date < $1.date }
        if applications.isEmpty { lines.append("- None recorded.") }
        for app in applications {
            let voided = app.isVoided ? " [VOIDED: \(app.voidReason ?? "no reason given")]" : ""
            lines.append("- \(Fmt.date(app.date) ?? "") · \(app.productName) · \(Fmt.quantity(app.quantity, app.quantityUnit.symbol) ?? "") · lot \(app.lotLabelSnapshot ?? "not recorded") · area \(Fmt.quantity(app.areaTreatedValue, app.areaUnit.symbol) ?? "unknown")\(voided)")
            if let note = app.registrationNote { lines.append("  - Reference: \(note)") }
        }
        lines.append("")

        lines.append("## Irrigation")
        let plans = (season.field?.irrigationPlans ?? []).filter { $0.seasonID == season.id }
        if plans.isEmpty { lines.append("- None recorded.") }
        for plan in plans {
            lines.append("- \(plan.zone ?? "Plan") · planned \(Fmt.number(plan.calculation?.volumeLiters, decimals: 0).map { "\($0) L" } ?? "not calculated") · recorded \(Fmt.number(plan.totalActualLiters(), decimals: 0).map { "\($0) L" } ?? "none")")
        }
        lines.append("")

        lines.append("## Observations")
        let observations = (season.field?.observations ?? []).filter { $0.seasonID == season.id }
        if observations.isEmpty { lines.append("- None recorded.") }
        for obs in observations.sorted(by: { $0.date < $1.date }) {
            lines.append("- \(Fmt.dateTime(obs.date) ?? "") · \(obs.confirmedCategory ?? obs.observationType.rawValue) · severity \(obs.severity?.rawValue ?? "not rated") · \(obs.summaryLine)")
            if let suggestion = obs.imageSuggestion, let category = suggestion.suggestedCategory {
                lines.append("  - Image suggestion (\(suggestion.provenance.source), \(Int((suggestion.confidence ?? 0) * 100))% confidence): \(category) — not confirmed as a diagnosis")
            }
        }
        lines.append("")

        lines.append("## Soil tests (confirmed only)")
        let tests = (season.field?.soilTests ?? []).filter(\.isConfirmed)
        if tests.isEmpty {
            lines.append("- None confirmed.")
            gaps.append("No confirmed soil tests for this field.")
        }
        for test in tests.sorted(by: { $0.sampleDate < $1.sampleDate }) {
            lines.append("- \(Fmt.date(test.sampleDate) ?? "") · \(test.laboratory ?? "lab not recorded") · pH \(Fmt.number(test.ph, decimals: 1) ?? "unknown") · OM \(Fmt.number(test.organicMatterPercent, decimals: 1).map { "\($0)%" } ?? "unknown")")
        }
        lines.append("")

        if let snapshot = season.closingSnapshot {
            lines.append("## Closing snapshot")
            lines.append("- Taken: \(Fmt.dateTime(snapshot.closedAt) ?? "")")
            lines.append("- These figures were frozen at close and are not affected by later edits elsewhere.")
            gaps.append(contentsOf: snapshot.gaps)
            lines.append("")
        }

        let uniqueGaps = Array(Set(gaps)).sorted()
        lines.append("## Missing information")
        if uniqueGaps.isEmpty {
            lines.append("- No gaps detected in the records used for this report.")
        } else {
            for gap in uniqueGaps { lines.append("- \(gap)") }
        }
        lines.append("")

        let metadata = ExportMetadata(generatedAt: Date(),
                                      dataRangeStart: dates.min(),
                                      dataRangeEnd: dates.max(),
                                      version: formatVersion,
                                      gaps: uniqueGaps)
        lines.append(footer(metadata))

        return ExportDocument(
            filename: "season-report-\(safe(season.displayTitle)).md",
            text: lines.joined(separator: "\n"),
            metadata: metadata
        )
    }

    // MARK: - Field log

    static func fieldLog(for field: FarmField) -> ExportDocument {
        var lines: [String] = []
        var dates: [Date] = []
        var gaps: [String] = []

        lines.append("# Field log — \(field.name)")
        lines.append("")
        lines.append("Farm: \(field.farm?.name ?? "Unknown")")
        lines.append("Area: \(field.areaDisplay ?? "Unknown")")
        lines.append("Boundary: \(field.boundary.kind.label)")
        lines.append("Irrigation method: \(field.irrigationMethod?.rawValue ?? "Unknown")")
        lines.append("Soil type: \(field.soilType ?? "Unknown")")
        lines.append("")

        if field.areaValue == nil { gaps.append("Field area is unknown.") }
        if field.boundary.kind == .none { gaps.append("No boundary recorded.") }

        lines.append("## Seasons")
        if field.seasons.isEmpty { lines.append("- None recorded.") }
        for season in field.seasons.sorted(by: { $0.createdAt < $1.createdAt }) {
            dates.append(season.createdAt)
            lines.append("- \(season.displayTitle) · \(season.status.label) · planted \(Fmt.date(season.actualPlantingDate) ?? "not recorded")")
        }
        lines.append("")

        lines.append("## Observations")
        if field.observations.isEmpty { lines.append("- None recorded.") }
        for obs in field.observations.sorted(by: { $0.date < $1.date }) {
            dates.append(obs.date)
            lines.append("- \(Fmt.dateTime(obs.date) ?? "") · \(obs.confirmedCategory ?? obs.observationType.rawValue) · \(obs.summaryLine)")
        }
        lines.append("")

        lines.append("## Soil tests")
        if field.soilTests.isEmpty { lines.append("- None recorded.") }
        for test in field.soilTests.sorted(by: { $0.sampleDate < $1.sampleDate }) {
            dates.append(test.sampleDate)
            let status = test.isConfirmed ? "confirmed" : "DRAFT — not included in analytics"
            lines.append("- \(Fmt.date(test.sampleDate) ?? "") · \(test.laboratory ?? "lab not recorded") · \(status)")
        }
        lines.append("")

        lines.append("## Irrigation")
        if field.irrigationPlans.isEmpty { lines.append("- None recorded.") }
        for plan in field.irrigationPlans {
            lines.append("- \(plan.zone ?? "Plan") · runs \(plan.runs.count) · recorded \(Fmt.number(plan.totalActualLiters(), decimals: 0).map { "\($0) L" } ?? "none")")
        }
        lines.append("")

        let uniqueGaps = Array(Set(gaps)).sorted()
        lines.append("## Missing information")
        if uniqueGaps.isEmpty {
            lines.append("- No gaps detected.")
        } else {
            for gap in uniqueGaps { lines.append("- \(gap)") }
        }
        lines.append("")

        let metadata = ExportMetadata(generatedAt: Date(),
                                      dataRangeStart: dates.min(),
                                      dataRangeEnd: dates.max(),
                                      version: formatVersion,
                                      gaps: uniqueGaps)
        lines.append(footer(metadata))

        return ExportDocument(filename: "field-log-\(safe(field.name)).md",
                              text: lines.joined(separator: "\n"),
                              metadata: metadata)
    }

    // MARK: - Full export

    static func fullExport(farm: Farm) -> ExportDocument {
        var lines: [String] = []
        lines.append("# Full data export — \(farm.name)")
        lines.append("")
        lines.append("Country: \(farm.country.isEmpty ? "Not set" : farm.country)")
        lines.append("Units: \(farm.unitSystem.label) · Currency: \(farm.currencyCode)")
        lines.append("Fields: \(farm.fields.count) · Inventory lots: \(farm.inventoryLots.count)")
        lines.append("")

        for field in farm.fields.sorted(by: { $0.name < $1.name }) {
            lines.append("## Field: \(field.name)")
            lines.append("- Area: \(field.areaDisplay ?? "Unknown")")
            lines.append("- Seasons: \(field.seasons.count)")
            lines.append("- Observations: \(field.observations.count)")
            lines.append("- Soil tests: \(field.soilTests.count)")
            lines.append("")
        }

        lines.append("## Inventory")
        for lot in farm.inventoryLots.sorted(by: { $0.itemName < $1.itemName }) {
            lines.append("- \(lot.displayLabel) · on hand \(Fmt.quantity(lot.onHandQuantity, lot.unit.symbol) ?? "") · reserved \(Fmt.quantity(lot.reservedQuantity, lot.unit.symbol) ?? "") · \(lot.isArchived ? "archived" : "active")")
        }
        lines.append("")

        let metadata = ExportMetadata(generatedAt: Date(),
                                      dataRangeStart: farm.createdAt,
                                      dataRangeEnd: Date(),
                                      version: formatVersion,
                                      gaps: [])
        lines.append(footer(metadata))

        return ExportDocument(filename: "farm-export-\(safe(farm.name)).md",
                              text: lines.joined(separator: "\n"),
                              metadata: metadata)
    }

    // MARK: - Helpers

    private static func footer(_ metadata: ExportMetadata) -> String {
        var out = "---\n"
        out += "generated_at: \(ISO8601DateFormatter().string(from: metadata.generatedAt))\n"
        out += "data_range: \(metadata.dataRangeStart.map { Fmt.date($0) ?? "" } ?? "n/a") → \(metadata.dataRangeEnd.map { Fmt.date($0) ?? "" } ?? "n/a")\n"
        out += "version: \(metadata.version)\n"
        out += "gap_count: \(metadata.gaps.count)\n"
        out += "note: Assembled only from records stored in this app. Figures marked unknown were never recorded and are not estimated.\n"
        return out
    }

    private static func collectDates(for season: CropSeason) -> [Date] {
        var dates: [Date] = [season.createdAt]
        if let planted = season.actualPlantingDate { dates.append(planted) }
        if let closed = season.closedAt { dates.append(closed) }
        dates.append(contentsOf: season.tasks.compactMap(\.completedAt))
        dates.append(contentsOf: season.applications.map(\.date))
        dates.append(contentsOf: season.harvestBatches.flatMap(\.loads).map(\.date))
        return dates
    }

    private static func safe(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(cleaned).lowercased()
    }
}
