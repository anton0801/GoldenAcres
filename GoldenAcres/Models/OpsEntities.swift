//
//  OpsEntities.swift
//  GoldenAcres
//
//  Tasks, inventory and harvest.
//
//  Inventory invariant: `available = onHand - reserved`. A task reservation
//  lowers available only; a confirmed application lowers on-hand. Every change
//  writes a StockMovement, so the ledger always explains the balance.
//

import Foundation
import SwiftData

// MARK: - Task

@Model
final class FarmTask {
    var id: UUID = UUID()
    var title: String = ""
    var detail: String? = nil
    var dueStart: Date? = nil
    var dueEnd: Date? = nil
    var estimatedDurationMinutes: Double? = nil
    var priorityRaw: String = TaskPriority.normal.rawValue
    var assignee: String? = nil
    var equipment: String? = nil
    var requiredInputs: [RequiredInput] = []
    var dependencyIDs: [UUID] = []
    var statusRaw: String = TaskStatus.planned.rawValue
    var blockedReason: String? = nil
    var startedAt: Date? = nil
    var completedAt: Date? = nil
    var actualDurationMinutes: Double? = nil

    /// Set when a forecast the task was planned against has since changed.
    /// The task is flagged for review, never silently rescheduled.
    var weatherReviewNeeded: Bool = false
    var weatherReviewNote: String? = nil
    /// Human-readable description of the window this task came from.
    var sourceWindowDescription: String? = nil

    var fieldID: UUID? = nil
    var fieldNameSnapshot: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Guards against a double tap creating two completions.
    var completionKey: UUID? = nil

    var season: CropSeason?

    init(title: String = "", season: CropSeason? = nil) {
        self.id = UUID()
        self.title = title
        self.season = season
        self.fieldID = season?.field?.id
        self.fieldNameSnapshot = season?.field?.name ?? ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }
    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var isOverdue: Bool {
        guard status.isOpen, let dueEnd else { return false }
        return dueEnd < Date()
    }

    var dueDisplay: String? { Fmt.dateRange(dueStart, dueEnd) }
}

// MARK: - Inventory

@Model
final class InventoryLot {
    var id: UUID = UUID()
    var itemName: String = ""
    var categoryRaw: String = InventoryCategory.other.rawValue
    var lotCode: String = ""
    var onHandQuantity: Double = 0
    var reservedQuantity: Double = 0
    var unitRaw: String = QuantityUnit.kilogram.rawValue
    var storageLocation: String? = nil
    var receivedDate: Date? = nil
    var expiryDate: Date? = nil
    var unitCost: Double? = nil
    var supplier: String? = nil
    var safetyFileName: String? = nil
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var labelScanProvenance: Provenance? = nil

    var farm: Farm?

    @Relationship(deleteRule: .cascade, inverse: \StockMovement.lot)
    var movements: [StockMovement] = []

    init(itemName: String = "", lotCode: String = "",
         quantity: Double = 0, unit: QuantityUnit = .kilogram) {
        self.id = UUID()
        self.itemName = itemName
        self.lotCode = lotCode
        self.onHandQuantity = quantity
        self.unitRaw = unit.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var category: InventoryCategory {
        get { InventoryCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var unit: QuantityUnit {
        get { QuantityUnit(rawValue: unitRaw) ?? .kilogram }
        set { unitRaw = newValue.rawValue }
    }

    /// Physically present minus what is already promised to tasks.
    var availableQuantity: Double { max(onHandQuantity - reservedQuantity, 0) }

    var isExpired: Bool {
        guard let expiryDate else { return false }
        return expiryDate < Date()
    }

    var expiresSoon: Bool {
        guard let expiryDate else { return false }
        let days = expiryDate.timeIntervalSinceNow / 86400
        return days > 0 && days <= 30
    }

    var displayLabel: String {
        lotCode.isEmpty ? itemName : "\(itemName) · \(lotCode)"
    }

    var totalValue: Double? {
        guard let unitCost else { return nil }
        return unitCost * onHandQuantity
    }
}

@Model
final class StockMovement {
    var id: UUID = UUID()
    var typeRaw: String = StockMovementType.receipt.rawValue
    var quantity: Double = 0
    var unitRaw: String = QuantityUnit.kilogram.rawValue
    var reason: String? = nil
    var timestamp: Date = Date()
    var relatedRecordID: UUID? = nil
    var relatedRecordLabel: String? = nil
    var actor: String? = nil
    /// Balances after this movement, so the ledger reconstructs any point in time.
    var balanceAfterOnHand: Double? = nil
    var balanceAfterReserved: Double? = nil

    var lot: InventoryLot?

    init(type: StockMovementType = .receipt, quantity: Double = 0,
         unit: QuantityUnit = .kilogram, lot: InventoryLot? = nil) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.lot = lot
        self.timestamp = Date()
    }

    var type: StockMovementType {
        get { StockMovementType(rawValue: typeRaw) ?? .receipt }
        set { typeRaw = newValue.rawValue }
    }
    var unit: QuantityUnit {
        get { QuantityUnit(rawValue: unitRaw) ?? .kilogram }
        set { unitRaw = newValue.rawValue }
    }
}

// MARK: - Harvest

@Model
final class HarvestBatch {
    var id: UUID = UUID()
    var batchCode: String = ""
    var startedAt: Date = Date()
    var closedAt: Date? = nil
    var statusRaw: String = HarvestStatus.open.rawValue
    var qualityGrade: String? = nil
    var storageDestination: String? = nil
    var crew: String? = nil
    var notes: String? = nil
    var fieldID: UUID? = nil
    var fieldNameSnapshot: String = ""
    /// Any change after closing is appended here rather than editing in place.
    var revisions: [HarvestRevision] = []
    var createdAt: Date = Date()

    var season: CropSeason?

    @Relationship(deleteRule: .cascade, inverse: \HarvestLoad.batch)
    var loads: [HarvestLoad] = []

    init(batchCode: String = "", season: CropSeason? = nil) {
        self.id = UUID()
        self.batchCode = batchCode
        self.season = season
        self.fieldID = season?.field?.id
        self.fieldNameSnapshot = season?.field?.name ?? ""
        self.startedAt = Date()
        self.createdAt = Date()
    }

    var status: HarvestStatus {
        get { HarvestStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var isClosed: Bool { status == .closed }

    /// The single unit shared by all loads, or nil when loads disagree.
    var commonUnit: QuantityUnit? {
        let units = Set(loads.map(\.unitRaw))
        guard units.count == 1, let raw = units.first else { return nil }
        return QuantityUnit(rawValue: raw)
    }

    var totalGross: Double? {
        guard commonUnit != nil, !loads.isEmpty else { return nil }
        return loads.map(\.grossQuantity).reduce(0, +)
    }

    var totalMarketable: Double? {
        guard commonUnit != nil else { return nil }
        let values = loads.compactMap(\.marketableQuantity)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var totalWaste: Double? {
        guard commonUnit != nil else { return nil }
        let values = loads.compactMap(\.wasteQuantity)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// Marketable share of gross — nil when either side is unknown.
    var marketableRatio: Double? {
        guard let gross = totalGross, gross > 0, let marketable = totalMarketable else { return nil }
        return marketable / gross
    }
}

@Model
final class HarvestLoad {
    var id: UUID = UUID()
    var date: Date = Date()
    var grossQuantity: Double = 0
    var marketableQuantity: Double? = nil
    var wasteQuantity: Double? = nil
    var unitRaw: String = QuantityUnit.kilogram.rawValue
    var notes: String? = nil
    /// Set by the client before saving; a repeated submit with the same key is
    /// ignored rather than duplicated.
    var idempotencyKey: String = UUID().uuidString
    var recordedBy: String? = nil
    var createdAt: Date = Date()

    var batch: HarvestBatch?

    init(grossQuantity: Double = 0, unit: QuantityUnit = .kilogram,
         date: Date = Date(), batch: HarvestBatch? = nil) {
        self.id = UUID()
        self.grossQuantity = grossQuantity
        self.unitRaw = unit.rawValue
        self.date = date
        self.batch = batch
        self.idempotencyKey = UUID().uuidString
        self.createdAt = Date()
    }

    var unit: QuantityUnit {
        get { QuantityUnit(rawValue: unitRaw) ?? .kilogram }
        set { unitRaw = newValue.rawValue }
    }

    /// Marketable + waste must never exceed gross.
    var isConsistent: Bool {
        let m = marketableQuantity ?? 0
        let w = wasteQuantity ?? 0
        return m + w <= grossQuantity + 0.0001
    }

    /// Portion of gross not yet classified as marketable or waste.
    var unclassifiedQuantity: Double? {
        guard marketableQuantity != nil || wasteQuantity != nil else { return nil }
        let m = marketableQuantity ?? 0
        let w = wasteQuantity ?? 0
        return max(grossQuantity - m - w, 0)
    }
}

// MARK: - Audit

@Model
final class AuditEvent {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var actor: String = "You"
    var action: String = ""
    var entityType: String = ""
    var entityID: UUID? = nil
    var summary: String = ""
    var details: String? = nil

    init(action: String, entityType: String, entityID: UUID? = nil,
         summary: String, details: String? = nil, actor: String = "You") {
        self.id = UUID()
        self.timestamp = Date()
        self.action = action
        self.entityType = entityType
        self.entityID = entityID
        self.summary = summary
        self.details = details
        self.actor = actor
    }
}

// MARK: - Season review

@Model
final class SeasonReviewRecord {
    var id: UUID = UUID()
    var seasonID: UUID = UUID()
    var completedAt: Date? = nil
    var lessons: [SeasonLesson] = []
    var createdAt: Date = Date()

    init(seasonID: UUID) {
        self.id = UUID()
        self.seasonID = seasonID
        self.createdAt = Date()
    }
}

// MARK: - External connections

@Model
final class DataConnection {
    var id: UUID = UUID()
    var provider: String = ""
    var isConnected: Bool = false
    var connectedAt: Date? = nil
    var lastSyncAt: Date? = nil
    /// Exactly what the integration can do — no implied capabilities.
    var capabilities: [String] = []
    var statusNote: String? = nil

    init(provider: String, capabilities: [String] = []) {
        self.id = UUID()
        self.provider = provider
        self.capabilities = capabilities
    }
}
