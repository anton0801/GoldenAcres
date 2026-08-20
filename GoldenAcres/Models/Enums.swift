//
//  Enums.swift
//  GoldenAcres
//
//  Domain vocabularies. Observation categories are deliberately descriptive
//  ("leaf symptom") rather than diagnostic ("blight") — the app records what
//  was seen, it does not name a disease.
//

import SwiftUI

// MARK: - Season

enum SeasonStatus: String, CaseIterable, Codable, Identifiable {
    case draft, active, closed, archived
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var tone: PillTone {
        switch self {
        case .draft: return .neutral
        case .active: return .gold
        case .closed: return .positive
        case .archived: return .neutral
        }
    }
}

enum IntendedUse: String, CaseIterable, Codable, Identifiable {
    case freshMarket = "Fresh market"
    case processing = "Processing"
    case seed = "Seed production"
    case forage = "Forage / fodder"
    case coverCrop = "Cover crop"
    case ownUse = "Own use"
    case other = "Other"
    var id: String { rawValue }
}

// MARK: - Field

enum IrrigationMethod: String, CaseIterable, Codable, Identifiable {
    case drip = "Drip"
    case sprinkler = "Sprinkler"
    case pivot = "Center pivot"
    case furrow = "Furrow"
    case flood = "Flood"
    case manual = "Manual / hose"
    case rainfed = "Rainfed (none)"
    var id: String { rawValue }
}

enum BoundaryKind: String, Codable, CaseIterable, Identifiable {
    case none, approximateArea, pins, geoJSON
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Not set"
        case .approximateArea: return "Approximate area only"
        case .pins: return "Pin points"
        case .geoJSON: return "Imported GeoJSON"
        }
    }
}

// MARK: - Observation

enum ObservationType: String, CaseIterable, Codable, Identifiable {
    case cropStage = "Crop stage"
    case leafSymptom = "Leaf / plant symptom"
    case pestSighting = "Pest sighting"
    case weedPressure = "Weed pressure"
    case weatherDamage = "Weather damage"
    case mechanicalDamage = "Mechanical / animal damage"
    case soilCondition = "Soil condition"
    case irrigationIssue = "Irrigation issue"
    case equipmentIssue = "Equipment issue"
    case generalNote = "General note"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cropStage: return "leaf"
        case .leafSymptom: return "aqi.medium"
        case .pestSighting: return "ant"
        case .weedPressure: return "camera.macro"
        case .weatherDamage: return "cloud.bolt.rain"
        case .mechanicalDamage: return "hammer"
        case .soilCondition: return "square.stack.3d.down.right"
        case .irrigationIssue: return "drop.triangle"
        case .equipmentIssue: return "wrench.and.screwdriver"
        case .generalNote: return "note.text"
        }
    }
}

enum Severity: String, CaseIterable, Codable, Identifiable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    var id: String { rawValue }
    var tone: PillTone {
        switch self {
        case .low: return .neutral
        case .moderate: return .warning
        case .high: return .risk
        }
    }
}

// MARK: - Soil

enum SoilTestStatus: String, CaseIterable, Codable, Identifiable {
    case draft, confirmed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - Inputs & inventory

enum InputCategory: String, CaseIterable, Codable, Identifiable {
    case fertilizer = "Fertilizer"
    case cropProtection = "Crop protection"
    case soilAmendment = "Soil amendment"
    case seedTreatment = "Seed treatment"
    case adjuvant = "Adjuvant"
    case other = "Other"
    var id: String { rawValue }
}

enum InventoryCategory: String, CaseIterable, Codable, Identifiable {
    case seeds = "Seeds"
    case fertilizers = "Fertilizers"
    case cropProtection = "Crop protection"
    case fuel = "Fuel"
    case packaging = "Packaging"
    case spareParts = "Spare parts"
    case other = "Other"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .seeds: return "leaf.circle"
        case .fertilizers: return "bag"
        case .cropProtection: return "shield.lefthalf.filled"
        case .fuel: return "fuelpump"
        case .packaging: return "shippingbox"
        case .spareParts: return "gearshape.2"
        case .other: return "square.grid.2x2"
        }
    }
}

enum StockMovementType: String, CaseIterable, Codable, Identifiable {
    case receipt = "Received"
    case reserve = "Reserved"
    case release = "Reservation released"
    case consume = "Consumed"
    case adjustment = "Adjusted"
    case transfer = "Moved"
    case archive = "Archived"
    var id: String { rawValue }

    /// Whether this movement changes physical on-hand stock.
    var affectsOnHand: Bool {
        switch self {
        case .receipt, .consume, .adjustment: return true
        case .reserve, .release, .transfer, .archive: return false
        }
    }
}

// MARK: - Tasks

enum TaskStatus: String, CaseIterable, Codable, Identifiable {
    case planned = "Planned"
    case inProgress = "In progress"
    case blocked = "Blocked"
    case completed = "Completed"
    case cancelled = "Cancelled"
    var id: String { rawValue }

    var tone: PillTone {
        switch self {
        case .planned: return .neutral
        case .inProgress: return .gold
        case .blocked: return .risk
        case .completed: return .positive
        case .cancelled: return .neutral
        }
    }
    var isOpen: Bool { self == .planned || self == .inProgress || self == .blocked }
}

enum TaskPriority: String, CaseIterable, Codable, Identifiable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    case urgent = "Urgent"
    var id: String { rawValue }
    var tone: PillTone {
        switch self {
        case .low, .normal: return .neutral
        case .high: return .warning
        case .urgent: return .risk
        }
    }
    var sortWeight: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .normal: return 2
        case .low: return 3
        }
    }
}

// MARK: - Weather work windows

enum WorkType: String, CaseIterable, Codable, Identifiable {
    case sowing = "Sowing"
    case spraying = "Spraying"
    case irrigation = "Irrigation"
    case harvesting = "Harvesting"
    case custom = "Custom work"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sowing: return "seal"
        case .spraying: return "spray.and.wipe"
        case .irrigation: return "drop"
        case .harvesting: return "basket"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// MARK: - Harvest

enum HarvestStatus: String, CaseIterable, Codable, Identifiable {
    case open = "Open"
    case closed = "Closed"
    var id: String { rawValue }
    var tone: PillTone { self == .open ? .gold : .positive }
}

// MARK: - Access

enum TeamRole: String, CaseIterable, Codable, Identifiable {
    case owner = "Owner"
    case manager = "Manager"
    case worker = "Worker"
    case viewer = "Viewer"
    var id: String { rawValue }

    var canEditStructure: Bool { self == .owner || self == .manager }
    var canRecord: Bool { self != .viewer }
    var canDeleteFarm: Bool { self == .owner }

    var summary: String {
        switch self {
        case .owner: return "Full access, including deleting the farm."
        case .manager: return "Create and edit fields, seasons, tasks and inventory."
        case .worker: return "Record observations, tasks and harvest loads."
        case .viewer: return "Read-only access to records and reports."
        }
    }
}
