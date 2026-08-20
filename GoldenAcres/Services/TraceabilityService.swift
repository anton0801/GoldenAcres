//
//  TraceabilityService.swift
//  GoldenAcres
//
//  Walks Field → Season → Seed lot → Tasks → Inputs → Observations → Harvest.
//
//  The trace is assembled only from records that exist. Anything absent is
//  reported as a named gap rather than omitted, so a clean-looking report and
//  an incomplete one are never confused.
//

import Foundation
import SwiftData

// MARK: - Trace model

struct TraceNode: Identifiable {
    enum Kind: String {
        case farm = "Farm"
        case field = "Field"
        case season = "Season"
        case seedLot = "Seed lot"
        case task = "Task"
        case application = "Input application"
        case inputLot = "Input lot"
        case observation = "Observation"
        case soilTest = "Soil test"
        case irrigation = "Irrigation"
        case harvestBatch = "Harvest batch"
        case harvestLoad = "Harvest load"
        case gap = "Missing information"

        var icon: String {
            switch self {
            case .farm: return "house"
            case .field: return "square.dashed"
            case .season: return "calendar"
            case .seedLot: return "leaf.circle"
            case .task: return "checklist"
            case .application: return "drop.triangle"
            case .inputLot: return "shippingbox"
            case .observation: return "eye"
            case .soilTest: return "testtube.2"
            case .irrigation: return "drop"
            case .harvestBatch: return "basket"
            case .harvestLoad: return "shippingbox.fill"
            case .gap: return "questionmark.circle"
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var subtitle: String?
    var timestamp: Date?
    var entityID: UUID?
    var isGap: Bool = false
    var detailLines: [String] = []
}

struct TraceResult {
    var lotTitle: String
    var nodes: [TraceNode]
    var gaps: [String]
    var generatedAt: Date

    var hasGaps: Bool { !gaps.isEmpty }
}

// MARK: - Service

@MainActor
enum TraceabilityService {

    /// Traces a harvest batch back through everything that produced it.
    static func trace(batch: HarvestBatch,
                      allLots: [InventoryLot]) -> TraceResult {
        var nodes: [TraceNode] = []
        var gaps: [String] = []

        let season = batch.season
        let field = season?.field ?? nil
        let farm = field?.farm

        // Farm
        if let farm {
            nodes.append(TraceNode(kind: .farm, title: farm.name,
                                   subtitle: farm.country.isEmpty ? nil : farm.country,
                                   entityID: farm.id))
        } else {
            gaps.append("The farm record for this batch is not available.")
        }

        // Field
        if let field {
            nodes.append(TraceNode(
                kind: .field,
                title: field.name,
                subtitle: field.areaDisplay.map { "Area \($0)" } ?? "Area unknown",
                entityID: field.id,
                detailLines: [
                    "Boundary: \(field.boundary.kind.label)",
                    "Irrigation method: \(field.irrigationMethod?.rawValue ?? "Unknown")",
                    "Soil type: \(field.soilType ?? "Unknown")"
                ]
            ))
        } else {
            let name = batch.fieldNameSnapshot.isEmpty ? "Unknown field" : batch.fieldNameSnapshot
            nodes.append(TraceNode(kind: .gap,
                                   title: "Field record detached",
                                   subtitle: "Recorded as “\(name)” at the time",
                                   isGap: true))
            gaps.append("The field this batch came from is no longer linked.")
        }

        // Season
        if let season {
            nodes.append(TraceNode(
                kind: .season,
                title: season.displayTitle,
                subtitle: Fmt.date(season.actualPlantingDate).map { "Planted \($0)" } ?? "Planting date not recorded",
                timestamp: season.actualPlantingDate,
                entityID: season.id,
                detailLines: [
                    "Intended use: \(season.intendedUse?.rawValue ?? "Unknown")",
                    "Status: \(season.status.label)"
                ]
            ))
            if season.actualPlantingDate == nil {
                gaps.append("Actual planting date was never recorded for this season.")
            }

            // Seed lot
            if let seedLotID = season.seedLotID,
               let lot = allLots.first(where: { $0.id == seedLotID }) {
                nodes.append(TraceNode(
                    kind: .seedLot,
                    title: lot.displayLabel,
                    subtitle: lot.supplier.map { "Supplier: \($0)" },
                    entityID: lot.id,
                    detailLines: [
                        "Received: \(Fmt.date(lot.receivedDate) ?? "Unknown")",
                        "Storage: \(lot.storageLocation ?? "Unknown")"
                    ]
                ))
            } else if let label = season.seedLotLabel {
                nodes.append(TraceNode(kind: .gap,
                                       title: "Seed lot no longer available",
                                       subtitle: "Recorded as “\(label)”",
                                       isGap: true))
                gaps.append("The seed lot record “\(label)” is no longer in inventory.")
            } else {
                nodes.append(TraceNode(kind: .gap, title: "No seed lot linked",
                                       subtitle: "Seed origin cannot be traced",
                                       isGap: true))
                gaps.append("No seed lot was linked to this season.")
            }

            // Tasks
            let completed = season.tasks.filter { $0.status == .completed }
                .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            for task in completed {
                nodes.append(TraceNode(
                    kind: .task,
                    title: task.title,
                    subtitle: Fmt.dateTime(task.completedAt).map { "Completed \($0)" },
                    timestamp: task.completedAt,
                    entityID: task.id,
                    detailLines: [
                        "Assignee: \(task.assignee ?? "Unassigned")",
                        "Equipment: \(task.equipment ?? "Not recorded")"
                    ]
                ))
            }
            if season.tasks.isEmpty {
                gaps.append("No tasks were recorded for this season.")
            }

            // Applications
            let applications = season.applications
                .filter { !$0.isVoided }
                .sorted { $0.date < $1.date }
            for app in applications {
                var details = [
                    "Quantity: \(Fmt.quantity(app.quantity, app.quantityUnit.symbol) ?? "Unknown")",
                    "Area treated: \(Fmt.quantity(app.areaTreatedValue, app.areaUnit.symbol) ?? "Unknown")",
                    "Operator: \(app.operatorName ?? "Not recorded")",
                    "Reference note: \(app.registrationNote ?? "None recorded")"
                ]
                if let weather = app.weatherSnapshot {
                    details.append("Weather at application: \(Fmt.number(weather.temperatureC, decimals: 1).map { "\($0) °C" } ?? "unknown temp"), wind \(Fmt.number(weather.windSpeedKMH, decimals: 1).map { "\($0) km/h" } ?? "unknown") — source \(weather.provenance.source)")
                } else {
                    details.append("No weather snapshot attached.")
                }
                nodes.append(TraceNode(
                    kind: .application,
                    title: app.productName,
                    subtitle: "\(Fmt.date(app.date) ?? "") · lot \(app.lotLabelSnapshot ?? "not recorded")",
                    timestamp: app.date,
                    entityID: app.id,
                    detailLines: details
                ))
            }

            // Observations linked to this season
            let observations = (field?.observations ?? [])
                .filter { $0.seasonID == season.id }
                .sorted { $0.date < $1.date }
            for obs in observations {
                nodes.append(TraceNode(
                    kind: .observation,
                    title: obs.confirmedCategory ?? obs.observationType.rawValue,
                    subtitle: obs.summaryLine,
                    timestamp: obs.date,
                    entityID: obs.id,
                    detailLines: [
                        "Severity: \(obs.severity?.rawValue ?? "Not rated")",
                        "Photos: \(obs.photoFilenames.count)"
                    ]
                ))
            }

            // Irrigation
            let plans = (field?.irrigationPlans ?? []).filter { $0.seasonID == season.id }
            for plan in plans {
                let actual = plan.totalActualLiters()
                nodes.append(TraceNode(
                    kind: .irrigation,
                    title: "Irrigation \(plan.zone ?? "plan")",
                    subtitle: actual.map { "Recorded \(Fmt.number($0, decimals: 0) ?? "") L" }
                        ?? "No actual water recorded",
                    timestamp: plan.startWindow,
                    entityID: plan.id,
                    detailLines: [
                        "Planned volume: \(Fmt.number(plan.calculation?.volumeLiters, decimals: 0).map { "\($0) L" } ?? "Not calculated")",
                        "Runs recorded: \(plan.runs.count)"
                    ]
                ))
            }

            // Soil tests
            let tests = (field?.soilTests ?? []).filter { $0.isConfirmed }
            for test in tests {
                nodes.append(TraceNode(
                    kind: .soilTest,
                    title: test.laboratory ?? "Soil test",
                    subtitle: "Sampled \(Fmt.date(test.sampleDate) ?? "unknown date")",
                    timestamp: test.sampleDate,
                    entityID: test.id,
                    detailLines: [
                        "pH: \(Fmt.number(test.ph, decimals: 1) ?? "Unknown")",
                        "Organic matter: \(Fmt.number(test.organicMatterPercent, decimals: 1).map { "\($0) %" } ?? "Unknown")"
                    ]
                ))
            }
        } else {
            nodes.append(TraceNode(kind: .gap, title: "Season record detached",
                                   subtitle: "This batch is no longer linked to a season",
                                   isGap: true))
            gaps.append("The crop season for this batch is no longer linked.")
        }

        // Harvest batch and loads
        nodes.append(TraceNode(
            kind: .harvestBatch,
            title: "Batch \(batch.batchCode)",
            subtitle: batch.isClosed
                ? "Closed \(Fmt.dateTime(batch.closedAt) ?? "")"
                : "Still open",
            timestamp: batch.closedAt ?? batch.startedAt,
            entityID: batch.id,
            detailLines: [
                "Quality grade: \(batch.qualityGrade ?? "Not graded")",
                "Storage: \(batch.storageDestination ?? "Not recorded")",
                "Crew: \(batch.crew ?? "Not recorded")",
                "Revisions: \(batch.revisions.count)"
            ]
        ))

        for load in batch.loads.sorted(by: { $0.date < $1.date }) {
            nodes.append(TraceNode(
                kind: .harvestLoad,
                title: "\(Fmt.quantity(load.grossQuantity, load.unit.symbol) ?? "") gross",
                subtitle: Fmt.dateTime(load.date),
                timestamp: load.date,
                entityID: load.id,
                detailLines: [
                    "Marketable: \(Fmt.quantity(load.marketableQuantity, load.unit.symbol) ?? "Not recorded")",
                    "Waste: \(Fmt.quantity(load.wasteQuantity, load.unit.symbol) ?? "Not recorded")"
                ]
            ))
        }

        if batch.loads.isEmpty {
            gaps.append("This batch has no loads recorded.")
        }
        if batch.commonUnit == nil && batch.loads.count > 1 {
            gaps.append("Loads in this batch use different units, so no total is shown.")
        }
        if batch.qualityGrade == nil {
            gaps.append("No quality grade was recorded.")
        }

        return TraceResult(
            lotTitle: "Batch \(batch.batchCode)",
            nodes: nodes,
            gaps: gaps,
            generatedAt: Date()
        )
    }
}
