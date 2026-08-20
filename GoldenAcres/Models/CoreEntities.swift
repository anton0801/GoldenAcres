//
//  CoreEntities.swift
//  GoldenAcres
//
//  The ownership spine: Farm → Field → Crop season.
//
//  Deletion policy: structural children cascade, but evidentiary records
//  (observations, applications, harvests, soil tests) are nullified and keep a
//  name snapshot. History is never rewritten — an orphaned record stays
//  readable and is marked as detached.
//

import Foundation
import SwiftData

// MARK: - Farm

@Model
final class Farm {
    var id: UUID = UUID()
    var name: String = ""
    var country: String = ""
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var unitSystemRaw: String = UnitSystem.metric.rawValue
    var currencyCode: String = "USD"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false

    // Settings surfaced on the Data & Integrations screen.
    var weatherSourceName: String = "Open-Meteo"
    var retentionMonths: Int? = nil
    var lastSyncAt: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \FarmField.farm)
    var fields: [FarmField] = []

    @Relationship(deleteRule: .cascade, inverse: \InventoryLot.farm)
    var inventoryLots: [InventoryLot] = []

    @Relationship(deleteRule: .cascade, inverse: \TeamMember.farm)
    var teamMembers: [TeamMember] = []

    init(name: String = "", country: String = "", timeZoneIdentifier: String = TimeZone.current.identifier,
         unitSystem: UnitSystem = .metric, currencyCode: String = "USD") {
        self.id = UUID()
        self.name = name
        self.country = country
        self.timeZoneIdentifier = timeZoneIdentifier
        self.unitSystemRaw = unitSystem.rawValue
        self.currencyCode = currencyCode
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
        set { unitSystemRaw = newValue.rawValue }
    }

    var activeFields: [FarmField] { fields.filter { !$0.isArchived } }

    var activeSeasons: [CropSeason] {
        fields.flatMap(\.seasons).filter { $0.status == .active }
    }
}

// MARK: - Field

@Model
final class FarmField {
    var id: UUID = UUID()
    var name: String = ""
    /// Nil means the area is genuinely unknown — it is never treated as 0.
    var areaValue: Double? = nil
    var areaUnitRaw: String = AreaUnit.hectare.rawValue
    var boundary: FieldBoundary = FieldBoundary.unset
    var soilType: String? = nil
    var irrigationMethodRaw: String? = nil
    var notes: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false

    /// Last forecast pulled for this field, kept so offline mode can show a
    /// clearly-labelled snapshot rather than nothing or stale-looking numbers.
    var cachedForecast: ForecastSnapshot? = nil

    var farm: Farm?

    @Relationship(deleteRule: .cascade, inverse: \CropSeason.field)
    var seasons: [CropSeason] = []

    @Relationship(deleteRule: .nullify, inverse: \FieldObservation.field)
    var observations: [FieldObservation] = []

    @Relationship(deleteRule: .nullify, inverse: \SoilTest.field)
    var soilTests: [SoilTest] = []

    @Relationship(deleteRule: .nullify, inverse: \IrrigationPlan.field)
    var irrigationPlans: [IrrigationPlan] = []

    init(name: String = "", areaValue: Double? = nil, areaUnit: AreaUnit = .hectare) {
        self.id = UUID()
        self.name = name
        self.areaValue = areaValue
        self.areaUnitRaw = areaUnit.rawValue
        self.boundary = .unset
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var areaUnit: AreaUnit {
        get { AreaUnit(rawValue: areaUnitRaw) ?? .hectare }
        set { areaUnitRaw = newValue.rawValue }
    }

    var irrigationMethod: IrrigationMethod? {
        get { irrigationMethodRaw.flatMap(IrrigationMethod.init(rawValue:)) }
        set { irrigationMethodRaw = newValue?.rawValue }
    }

    var areaSquareMeters: Double? {
        guard let areaValue else { return nil }
        return areaValue * areaUnit.inSquareMeters
    }

    var areaDisplay: String? {
        Fmt.quantity(areaValue, areaUnit.symbol)
    }

    var currentSeason: CropSeason? {
        seasons.filter { $0.status == .active }
            .sorted { ($0.activatedAt ?? .distantPast) > ($1.activatedAt ?? .distantPast) }
            .first
    }

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    /// Field-level coordinate, falling back to the boundary centroid.
    var resolvedCoordinate: (lat: Double, lon: Double)? {
        if let latitude, let longitude { return (latitude, longitude) }
        let pts = boundary.points
        guard !pts.isEmpty else { return nil }
        let lat = pts.map(\.latitude).reduce(0, +) / Double(pts.count)
        let lon = pts.map(\.longitude).reduce(0, +) / Double(pts.count)
        return (lat, lon)
    }
}

// MARK: - Crop season

@Model
final class CropSeason {
    var id: UUID = UUID()
    var cropName: String = ""
    var variety: String? = nil
    var intendedUseRaw: String? = nil
    var plantingWindowStart: Date? = nil
    var plantingWindowEnd: Date? = nil
    var actualPlantingDate: Date? = nil
    var expectedHarvestStart: Date? = nil
    var expectedHarvestEnd: Date? = nil
    var targetAreaValue: Double? = nil
    var targetAreaUnitRaw: String = AreaUnit.hectare.rawValue
    var seedLotID: UUID? = nil
    /// Kept so the season stays readable if the lot is later archived.
    var seedLotLabel: String? = nil
    var notes: String? = nil
    var statusRaw: String = SeasonStatus.draft.rawValue
    var allowsIntercropping: Bool = false
    var activatedAt: Date? = nil
    var closedAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Provenance for any crop-reference data used while setting up.
    var referenceSource: String? = nil
    var referenceUpdatedAt: Date? = nil

    /// Snapshot taken at close, so later edits elsewhere can't rewrite outcomes.
    var closingSnapshot: SeasonSnapshot? = nil

    var field: FarmField?

    @Relationship(deleteRule: .cascade, inverse: \FarmTask.season)
    var tasks: [FarmTask] = []

    @Relationship(deleteRule: .nullify, inverse: \HarvestBatch.season)
    var harvestBatches: [HarvestBatch] = []

    @Relationship(deleteRule: .nullify, inverse: \InputApplication.season)
    var applications: [InputApplication] = []

    init(cropName: String = "", field: FarmField? = nil) {
        self.id = UUID()
        self.cropName = cropName
        self.field = field
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var status: SeasonStatus {
        get { SeasonStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var intendedUse: IntendedUse? {
        get { intendedUseRaw.flatMap(IntendedUse.init(rawValue:)) }
        set { intendedUseRaw = newValue?.rawValue }
    }

    var targetAreaUnit: AreaUnit {
        get { AreaUnit(rawValue: targetAreaUnitRaw) ?? .hectare }
        set { targetAreaUnitRaw = newValue.rawValue }
    }

    var targetAreaSquareMeters: Double? {
        guard let targetAreaValue else { return nil }
        return targetAreaValue * targetAreaUnit.inSquareMeters
    }

    var displayTitle: String {
        let base = cropName.isEmpty ? "Untitled crop" : cropName
        if let variety, !variety.isEmpty { return "\(base) · \(variety)" }
        return base
    }

    var openTasks: [FarmTask] { tasks.filter { $0.status.isOpen } }

    /// Total harvested quantity, only when all closed batches share one unit.
    /// Mixed units return nil rather than a meaningless sum.
    func totalMarketable() -> (value: Double, unit: QuantityUnit)? {
        let loads = harvestBatches.flatMap(\.loads)
        guard !loads.isEmpty else { return nil }
        let units = Set(loads.map(\.unitRaw))
        guard units.count == 1,
              let unit = QuantityUnit(rawValue: units.first!) else { return nil }
        let total = loads.compactMap(\.marketableQuantity).reduce(0, +)
        return (total, unit)
    }
}

/// Immutable numbers captured when a season closes.
struct SeasonSnapshot: Codable, Hashable {
    var closedAt: Date
    var marketableQuantity: Double?
    var grossQuantity: Double?
    var wasteQuantity: Double?
    var quantityUnitRaw: String?
    var harvestedAreaSquareMeters: Double?
    var taskCountPlanned: Int
    var taskCountCompleted: Int
    var applicationCount: Int
    var recordedWaterLiters: Double?
    var gaps: [String]
}

// MARK: - Team

@Model
final class TeamMember {
    var id: UUID = UUID()
    var name: String = ""
    var email: String? = nil
    var roleRaw: String = TeamRole.worker.rawValue
    var invitedAt: Date = Date()
    var isActive: Bool = true
    var farm: Farm?

    init(name: String = "", email: String? = nil, role: TeamRole = .worker) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.roleRaw = role.rawValue
        self.invitedAt = Date()
    }

    var role: TeamRole {
        get { TeamRole(rawValue: roleRaw) ?? .worker }
        set { roleRaw = newValue.rawValue }
    }
}
