//
//  SeasonInsights.swift
//  GoldenAcres
//
//  Season metrics and cross-season comparison.
//
//  Two rules hold throughout: seasons whose units or areas are not comparable
//  are refused rather than coerced, and a relationship between two recorded
//  numbers is described as a correlation, never as a cause.
//

import Foundation

// MARK: - Metrics for one season

struct SeasonMetrics {
    var season: CropSeason
    var marketable: Double?
    var gross: Double?
    var waste: Double?
    var unit: QuantityUnit?
    var areaSquareMeters: Double?
    var yieldPerHectare: Double?
    var plannedTasks: Int
    var completedTasks: Int
    var lateTasks: Int
    var applicationCount: Int
    var waterLiters: Double?
    var weatherFlaggedTasks: Int
    var observationCount: Int
    var costTotal: Double?
    var costPerHectare: Double?
    var gaps: [String]

    var taskCompletionRatio: Double? {
        guard plannedTasks > 0 else { return nil }
        return Double(completedTasks) / Double(plannedTasks)
    }

    var wasteRatio: Double? {
        guard let gross, gross > 0, let waste else { return nil }
        return waste / gross
    }
}

// MARK: - Comparison

struct SeasonComparison {
    struct Row: Identifiable {
        let id = UUID()
        var label: String
        var values: [String?]
        var note: String?
    }
    var seasons: [CropSeason]
    var rows: [Row]
    var blockedReasons: [String]
    var isComparable: Bool { blockedReasons.isEmpty }
}

// MARK: - Observation pattern (correlation only)

struct ObservationPattern: Identifiable {
    let id = UUID()
    var category: String
    var count: Int
    var months: [String]
    /// Explicitly framed as a co-occurrence, never a cause.
    var statement: String
}

// MARK: - Service

@MainActor
enum SeasonInsights {

    static func metrics(for season: CropSeason, allLots: [InventoryLot]) -> SeasonMetrics {
        var gaps: [String] = []

        let loads = season.harvestBatches.flatMap(\.loads)
        let units = Set(loads.map(\.unitRaw))
        var unit: QuantityUnit?
        var gross: Double?
        var marketable: Double?
        var waste: Double?

        if units.count == 1, let raw = units.first {
            unit = QuantityUnit(rawValue: raw)
            gross = loads.map(\.grossQuantity).reduce(0, +)
            let m = loads.compactMap(\.marketableQuantity)
            marketable = m.isEmpty ? nil : m.reduce(0, +)
            let w = loads.compactMap(\.wasteQuantity)
            waste = w.isEmpty ? nil : w.reduce(0, +)
        } else if units.count > 1 {
            gaps.append("Harvest loads use \(units.count) different units — no total is calculated.")
        } else {
            gaps.append("No harvest loads recorded.")
        }

        let area = season.targetAreaSquareMeters ?? season.field?.areaSquareMeters
        if area == nil { gaps.append("Area unknown — yield per area cannot be derived.") }

        var yieldPerHa: Double?
        if let marketable, let area, area > 0, let unit, unit.dimension == .mass {
            let hectares = area / AreaUnit.hectare.inSquareMeters
            yieldPerHa = marketable / hectares
        } else if marketable != nil, let unit, unit.dimension != .mass {
            gaps.append("Yield per area is only derived for mass units; this season is recorded in \(unit.symbol).")
        }

        let tasks = season.tasks
        let completed = tasks.filter { $0.status == .completed }
        let late = completed.filter { task in
            guard let due = task.dueEnd, let done = task.completedAt else { return false }
            return done > due
        }

        let plans = (season.field?.irrigationPlans ?? []).filter { $0.seasonID == season.id }
        let water = plans.compactMap { $0.totalActualLiters() }.reduce(0, +)
        if plans.isEmpty { gaps.append("No irrigation plans linked to this season.") }
        else if water == 0 { gaps.append("Irrigation plans exist but no actual water was recorded.") }

        let applications = season.applications.filter { !$0.isVoided }

        // Cost is only summed from lots that actually carry a unit cost.
        var cost: Double?
        var costedCount = 0
        var costAccumulator: Double = 0
        for app in applications {
            guard let lotID = app.lotID,
                  let lot = allLots.first(where: { $0.id == lotID }),
                  let unitCost = lot.unitCost else { continue }
            guard let converted = app.quantityUnit.convert(app.quantity, to: lot.unit) else { continue }
            costAccumulator += converted * unitCost
            costedCount += 1
        }
        if costedCount > 0 {
            cost = costAccumulator
            if costedCount < applications.count {
                gaps.append("Cost covers \(costedCount) of \(applications.count) applications — the rest have no unit cost on their lot.")
            }
        } else if !applications.isEmpty {
            gaps.append("No unit costs recorded on the lots used, so input cost is unknown.")
        }

        var costPerHa: Double?
        if let cost, let area, area > 0 {
            costPerHa = cost / (area / AreaUnit.hectare.inSquareMeters)
        }

        let observations = (season.field?.observations ?? []).filter { $0.seasonID == season.id }

        return SeasonMetrics(
            season: season,
            marketable: marketable,
            gross: gross,
            waste: waste,
            unit: unit,
            areaSquareMeters: area,
            yieldPerHectare: yieldPerHa,
            plannedTasks: tasks.count,
            completedTasks: completed.count,
            lateTasks: late.count,
            applicationCount: applications.count,
            waterLiters: water > 0 ? water : nil,
            weatherFlaggedTasks: tasks.filter(\.weatherReviewNeeded).count,
            observationCount: observations.count,
            costTotal: cost,
            costPerHectare: costPerHa,
            gaps: gaps
        )
    }

    // MARK: - Comparison

    static func compare(_ seasons: [CropSeason], allLots: [InventoryLot]) -> SeasonComparison {
        var blocked: [String] = []

        guard seasons.count >= 2 else {
            return SeasonComparison(seasons: seasons, rows: [],
                                    blockedReasons: ["Select at least two closed seasons to compare."])
        }

        let all = seasons.map { metrics(for: $0, allLots: allLots) }

        // Yield can only be compared when the unit is the same across seasons.
        let units = Set(all.compactMap { $0.unit?.rawValue })
        if units.count > 1 {
            blocked.append("These seasons record harvest in different units (\(units.sorted().joined(separator: ", "))). Convert them to one unit before comparing yields.")
        }
        if all.contains(where: { $0.areaSquareMeters == nil }) {
            blocked.append("At least one season has no known area, so per-area figures cannot be compared.")
        }

        func row(_ label: String, _ transform: (SeasonMetrics) -> String?, note: String? = nil) -> SeasonComparison.Row {
            SeasonComparison.Row(label: label, values: all.map(transform), note: note)
        }

        var rows: [SeasonComparison.Row] = [
            row("Crop") { $0.season.displayTitle },
            row("Field") { $0.season.field?.name ?? $0.season.field?.name ?? "Detached" },
            row("Closed") { Fmt.date($0.season.closedAt) },
            row("Marketable") { m in
                guard let v = m.marketable, let u = m.unit else { return nil }
                return Fmt.quantity(v, u.symbol)
            },
            row("Gross") { m in
                guard let v = m.gross, let u = m.unit else { return nil }
                return Fmt.quantity(v, u.symbol)
            },
            row("Waste share") { m in
                guard let r = m.wasteRatio else { return nil }
                return "\(Fmt.number(r * 100, decimals: 1) ?? "") %"
            },
            row("Tasks completed") { "\($0.completedTasks) of \($0.plannedTasks)" },
            row("Late tasks") { "\($0.lateTasks)" },
            row("Applications") { "\($0.applicationCount)" },
            row("Water recorded") { m in
                guard let w = m.waterLiters else { return nil }
                return "\(Fmt.number(w, decimals: 0) ?? "") L"
            },
            row("Observations") { "\($0.observationCount)" }
        ]

        if units.count <= 1 {
            rows.insert(
                row("Yield per ha", { m in
                    guard let y = m.yieldPerHectare, let u = m.unit else { return nil }
                    return "\(Fmt.number(y, decimals: 1) ?? "") \(u.symbol)/ha"
                }, note: "Derived from marketable quantity ÷ area."),
                at: 5
            )
        }

        return SeasonComparison(seasons: seasons, rows: rows, blockedReasons: blocked)
    }

    // MARK: - Patterns

    /// Groups observations by confirmed category and month. Presented strictly
    /// as what was recorded — no causal claim is attached.
    static func observationPatterns(for seasons: [CropSeason]) -> [ObservationPattern] {
        var buckets: [String: [FieldObservation]] = [:]
        for season in seasons {
            let observations = (season.field?.observations ?? [])
                .filter { $0.seasonID == season.id }
            for obs in observations {
                let key = obs.confirmedCategory ?? obs.observationType.rawValue
                buckets[key, default: []].append(obs)
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"

        return buckets
            .filter { $0.value.count >= 2 }
            .map { key, values in
                let months = Array(Set(values.map { formatter.string(from: $0.date) })).sorted()
                return ObservationPattern(
                    category: key,
                    count: values.count,
                    months: months,
                    statement: "Recorded \(values.count) times, in \(months.joined(separator: ", ")). This is a count of your own entries, not an explanation of why it happened."
                )
            }
            .sorted { $0.count > $1.count }
    }

    /// Insights need at least two comparable closed seasons.
    static func insightsAvailable(closedSeasons: [CropSeason]) -> (available: Bool, reason: String?) {
        guard closedSeasons.count >= 2 else {
            return (false, "Insights appear once you have closed at least two seasons. You have \(closedSeasons.count).")
        }
        let crops = Set(closedSeasons.map { $0.cropName.lowercased() })
        if crops.count == closedSeasons.count {
            return (true, "These seasons are for different crops, so differences may reflect the crop rather than your practice.")
        }
        return (true, nil)
    }
}
