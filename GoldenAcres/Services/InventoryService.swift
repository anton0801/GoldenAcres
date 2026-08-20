//
//  InventoryService.swift
//  GoldenAcres
//
//  Guards the stock invariant: available = onHand − reserved.
//
//  Reserving lowers availability without touching physical stock; a confirmed
//  application consumes it. Every change writes a StockMovement carrying the
//  resulting balances, so the ledger can always explain the current number.
//

import Foundation
import SwiftData

enum InventoryError: LocalizedError {
    case negativeQuantity
    case insufficientAvailable(available: Double, requested: Double, unit: String)
    case insufficientOnHand(onHand: Double, requested: Double, unit: String)
    case unitMismatch(lotUnit: String, requestedUnit: String)
    case missingReason
    case archived

    var errorDescription: String? {
        switch self {
        case .negativeQuantity:
            return "Quantity must be greater than zero."
        case .insufficientAvailable(let available, let requested, let unit):
            return "Only \(Fmt.number(available, decimals: 2) ?? "0") \(unit) available, but \(Fmt.number(requested, decimals: 2) ?? "0") \(unit) requested."
        case .insufficientOnHand(let onHand, let requested, let unit):
            return "Only \(Fmt.number(onHand, decimals: 2) ?? "0") \(unit) on hand, but \(Fmt.number(requested, decimals: 2) ?? "0") \(unit) requested."
        case .unitMismatch(let lotUnit, let requestedUnit):
            return "This lot is measured in \(lotUnit); \(requestedUnit) cannot be converted without an explicit factor."
        case .missingReason:
            return "An adjustment needs a reason so the ledger stays explainable."
        case .archived:
            return "This lot is archived. Restore it before recording movements."
        }
    }
}

@MainActor
enum InventoryService {

    // MARK: - Receipt

    @discardableResult
    static func receive(lot: InventoryLot,
                        quantity: Double,
                        unit: QuantityUnit,
                        reason: String?,
                        context: ModelContext) throws -> StockMovement {
        guard quantity > 0 else { throw InventoryError.negativeQuantity }
        guard !lot.isArchived else { throw InventoryError.archived }
        let converted = try convert(quantity, from: unit, to: lot.unit)

        lot.onHandQuantity += converted
        lot.updatedAt = Date()
        return record(.receipt, on: lot, quantity: converted,
                      reason: reason, context: context)
    }

    // MARK: - Reservation

    /// Lowers availability for a task without changing physical stock.
    @discardableResult
    static func reserve(lot: InventoryLot,
                        quantity: Double,
                        unit: QuantityUnit,
                        forTask taskID: UUID?,
                        taskLabel: String?,
                        context: ModelContext) throws -> StockMovement {
        guard quantity > 0 else { throw InventoryError.negativeQuantity }
        guard !lot.isArchived else { throw InventoryError.archived }
        let converted = try convert(quantity, from: unit, to: lot.unit)

        guard converted <= lot.availableQuantity + 0.0001 else {
            throw InventoryError.insufficientAvailable(available: lot.availableQuantity,
                                                       requested: converted,
                                                       unit: lot.unit.symbol)
        }
        lot.reservedQuantity += converted
        lot.updatedAt = Date()
        return record(.reserve, on: lot, quantity: converted,
                      reason: "Reserved for \(taskLabel ?? "a task")",
                      relatedID: taskID, relatedLabel: taskLabel, context: context)
    }

    @discardableResult
    static func releaseReservation(lot: InventoryLot,
                                   quantity: Double,
                                   forTask taskID: UUID?,
                                   taskLabel: String?,
                                   context: ModelContext) -> StockMovement {
        let amount = min(quantity, lot.reservedQuantity)
        lot.reservedQuantity = max(lot.reservedQuantity - amount, 0)
        lot.updatedAt = Date()
        return record(.release, on: lot, quantity: amount,
                      reason: "Reservation released",
                      relatedID: taskID, relatedLabel: taskLabel, context: context)
    }

    // MARK: - Consumption

    /// Called when an application record is confirmed. Consumes physical stock
    /// and clears any matching reservation.
    @discardableResult
    static func consume(lot: InventoryLot,
                        quantity: Double,
                        unit: QuantityUnit,
                        applicationID: UUID,
                        applicationLabel: String,
                        releasingReservation: Double? = nil,
                        context: ModelContext) throws -> StockMovement {
        guard quantity > 0 else { throw InventoryError.negativeQuantity }
        let converted = try convert(quantity, from: unit, to: lot.unit)

        guard converted <= lot.onHandQuantity + 0.0001 else {
            throw InventoryError.insufficientOnHand(onHand: lot.onHandQuantity,
                                                    requested: converted,
                                                    unit: lot.unit.symbol)
        }

        if let releasing = releasingReservation, releasing > 0 {
            lot.reservedQuantity = max(lot.reservedQuantity - min(releasing, lot.reservedQuantity), 0)
        }
        lot.onHandQuantity -= converted
        lot.updatedAt = Date()

        let movement = record(.consume, on: lot, quantity: converted,
                              reason: "Applied: \(applicationLabel)",
                              relatedID: applicationID, relatedLabel: applicationLabel,
                              context: context)

        // A lot that reaches zero is archived, but its movement history stays.
        if lot.onHandQuantity <= 0.0001 && lot.reservedQuantity <= 0.0001 {
            lot.onHandQuantity = 0
            lot.isArchived = true
            record(.archive, on: lot, quantity: 0,
                   reason: "Automatically archived — lot fully consumed", context: context)
        }
        return movement
    }

    // MARK: - Adjustment

    @discardableResult
    static func adjust(lot: InventoryLot,
                       newOnHand: Double,
                       reason: String,
                       context: ModelContext) throws -> StockMovement {
        guard newOnHand >= 0 else { throw InventoryError.negativeQuantity }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InventoryError.missingReason
        }
        let delta = newOnHand - lot.onHandQuantity
        lot.onHandQuantity = newOnHand
        lot.updatedAt = Date()
        let direction = delta >= 0 ? "increased" : "decreased"
        return record(.adjustment, on: lot, quantity: abs(delta),
                      reason: "Stock \(direction) by \(Fmt.number(abs(delta), decimals: 2) ?? "0") \(lot.unit.symbol) — \(reason)",
                      context: context)
    }

    @discardableResult
    static func move(lot: InventoryLot,
                     to storage: String,
                     context: ModelContext) -> StockMovement {
        let previous = lot.storageLocation ?? "unspecified"
        lot.storageLocation = storage
        lot.updatedAt = Date()
        return record(.transfer, on: lot, quantity: lot.onHandQuantity,
                      reason: "Moved from \(previous) to \(storage)", context: context)
    }

    @discardableResult
    static func archive(lot: InventoryLot, reason: String?, context: ModelContext) -> StockMovement {
        lot.isArchived = true
        lot.updatedAt = Date()
        return record(.archive, on: lot, quantity: lot.onHandQuantity,
                      reason: reason ?? "Archived by user", context: context)
    }

    static func restore(lot: InventoryLot, context: ModelContext) {
        lot.isArchived = false
        lot.updatedAt = Date()
        AuditService.log(action: "Restored", entityType: "Inventory lot", entityID: lot.id,
                         summary: "Restored lot \(lot.displayLabel)", context: context)
    }

    // MARK: - Duplicate detection

    /// Flags lots that look like the same physical stock, for a merge review.
    /// Nothing is merged automatically.
    static func duplicateCandidates(for lot: InventoryLot, in lots: [InventoryLot]) -> [InventoryLot] {
        guard !lot.lotCode.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return lots.filter {
            $0.id != lot.id
                && !$0.isArchived
                && $0.lotCode.caseInsensitiveCompare(lot.lotCode) == .orderedSame
                && $0.itemName.caseInsensitiveCompare(lot.itemName) == .orderedSame
        }
    }

    // MARK: - Helpers

    private static func convert(_ quantity: Double,
                                from unit: QuantityUnit,
                                to target: QuantityUnit) throws -> Double {
        guard let converted = unit.convert(quantity, to: target) else {
            throw InventoryError.unitMismatch(lotUnit: target.symbol, requestedUnit: unit.symbol)
        }
        return converted
    }

    @discardableResult
    private static func record(_ type: StockMovementType,
                               on lot: InventoryLot,
                               quantity: Double,
                               reason: String?,
                               relatedID: UUID? = nil,
                               relatedLabel: String? = nil,
                               context: ModelContext) -> StockMovement {
        let movement = StockMovement(type: type, quantity: quantity, unit: lot.unit, lot: lot)
        movement.reason = reason
        movement.relatedRecordID = relatedID
        movement.relatedRecordLabel = relatedLabel
        movement.balanceAfterOnHand = lot.onHandQuantity
        movement.balanceAfterReserved = lot.reservedQuantity
        context.insert(movement)
        lot.movements.append(movement)

        AuditService.log(action: type.rawValue, entityType: "Inventory lot", entityID: lot.id,
                         summary: "\(type.rawValue) \(Fmt.number(quantity, decimals: 2) ?? "0") \(lot.unit.symbol) — \(lot.displayLabel)",
                         details: reason, context: context)
        return movement
    }
}

// MARK: - Audit

@MainActor
enum AuditService {
    static func log(action: String,
                    entityType: String,
                    entityID: UUID?,
                    summary: String,
                    details: String? = nil,
                    context: ModelContext) {
        let event = AuditEvent(action: action, entityType: entityType,
                               entityID: entityID, summary: summary, details: details)
        context.insert(event)
    }
}
