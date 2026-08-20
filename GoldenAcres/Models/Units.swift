//
//  Units.swift
//  GoldenAcres
//
//  Every quantity carries its unit. Conversions are explicit and return nil
//  when a conversion is not defined, so incompatible values are never silently
//  merged into one number.
//

import Foundation

// MARK: - Unit system

enum UnitSystem: String, CaseIterable, Codable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var label: String { self == .metric ? "Metric" : "Imperial" }

    var defaultArea: AreaUnit { self == .metric ? .hectare : .acre }
    var defaultDepth: DepthUnit { self == .metric ? .millimeter : .inch }
    var defaultVolume: VolumeUnit { self == .metric ? .liter : .gallonUS }
    var defaultMass: MassUnit { self == .metric ? .kilogram : .pound }
    var defaultFlow: FlowUnit { self == .metric ? .litersPerMinute : .gallonsPerMinute }
}

// MARK: - Area

enum AreaUnit: String, CaseIterable, Codable, Identifiable {
    case hectare = "ha"
    case acre = "ac"
    case squareMeter = "m²"
    case squareFoot = "ft²"

    var id: String { rawValue }
    var symbol: String { rawValue }
    var label: String {
        switch self {
        case .hectare: return "Hectares (ha)"
        case .acre: return "Acres (ac)"
        case .squareMeter: return "Square meters (m²)"
        case .squareFoot: return "Square feet (ft²)"
        }
    }

    var inSquareMeters: Double {
        switch self {
        case .hectare: return 10_000
        case .acre: return 4046.8564224
        case .squareMeter: return 1
        case .squareFoot: return 0.09290304
        }
    }

    func convert(_ value: Double, to other: AreaUnit) -> Double {
        value * inSquareMeters / other.inSquareMeters
    }
}

// MARK: - Depth (irrigation / rainfall / sampling depth)

enum DepthUnit: String, CaseIterable, Codable, Identifiable {
    case millimeter = "mm"
    case centimeter = "cm"
    case inch = "in"

    var id: String { rawValue }
    var symbol: String { rawValue }
    var inMillimeters: Double {
        switch self {
        case .millimeter: return 1
        case .centimeter: return 10
        case .inch: return 25.4
        }
    }
    func convert(_ value: Double, to other: DepthUnit) -> Double {
        value * inMillimeters / other.inMillimeters
    }
}

// MARK: - Volume

enum VolumeUnit: String, CaseIterable, Codable, Identifiable {
    case liter = "L"
    case cubicMeter = "m³"
    case gallonUS = "gal"

    var id: String { rawValue }
    var symbol: String { rawValue }
    var inLiters: Double {
        switch self {
        case .liter: return 1
        case .cubicMeter: return 1000
        case .gallonUS: return 3.785411784
        }
    }
    func convert(_ value: Double, to other: VolumeUnit) -> Double {
        value * inLiters / other.inLiters
    }
}

// MARK: - Mass

enum MassUnit: String, CaseIterable, Codable, Identifiable {
    case kilogram = "kg"
    case gram = "g"
    case tonne = "t"
    case pound = "lb"

    var id: String { rawValue }
    var symbol: String { rawValue }
    var inKilograms: Double {
        switch self {
        case .kilogram: return 1
        case .gram: return 0.001
        case .tonne: return 1000
        case .pound: return 0.45359237
        }
    }
    func convert(_ value: Double, to other: MassUnit) -> Double {
        value * inKilograms / other.inKilograms
    }
}

// MARK: - Flow

enum FlowUnit: String, CaseIterable, Codable, Identifiable {
    case litersPerMinute = "L/min"
    case cubicMetersPerHour = "m³/h"
    case gallonsPerMinute = "gal/min"

    var id: String { rawValue }
    var symbol: String { rawValue }
    var inLitersPerMinute: Double {
        switch self {
        case .litersPerMinute: return 1
        case .cubicMetersPerHour: return 1000.0 / 60.0
        case .gallonsPerMinute: return 3.785411784
        }
    }
    func convert(_ value: Double, to other: FlowUnit) -> Double {
        value * inLitersPerMinute / other.inLitersPerMinute
    }
}

// MARK: - Generic quantity units used for inventory & harvest

/// Inventory and harvest lines accept mass, volume or discrete counts. Two
/// quantities can only be summed when `dimension` matches.
enum QuantityUnit: String, CaseIterable, Codable, Identifiable {
    case kilogram = "kg"
    case gram = "g"
    case tonne = "t"
    case pound = "lb"
    case liter = "L"
    case milliliter = "mL"
    case gallonUS = "gal"
    case unitCount = "units"
    case bag = "bags"
    case crate = "crates"
    case seedCount = "seeds"

    var id: String { rawValue }
    var symbol: String { rawValue }

    enum Dimension: String { case mass, volume, count }

    var dimension: Dimension {
        switch self {
        case .kilogram, .gram, .tonne, .pound: return .mass
        case .liter, .milliliter, .gallonUS: return .volume
        case .unitCount, .bag, .crate, .seedCount: return .count
        }
    }

    /// Base factor within the dimension (kg for mass, L for volume, 1 for count).
    /// Count-style units are intentionally *not* interchangeable: a bag is not a
    /// crate, so each keeps its own identity and only converts to itself.
    var baseFactor: Double? {
        switch self {
        case .kilogram: return 1
        case .gram: return 0.001
        case .tonne: return 1000
        case .pound: return 0.45359237
        case .liter: return 1
        case .milliliter: return 0.001
        case .gallonUS: return 3.785411784
        case .unitCount, .bag, .crate, .seedCount: return nil
        }
    }

    /// Returns nil when the two units cannot be converted without an assumption
    /// the app is not entitled to make (e.g. kg → L needs a density).
    func convert(_ value: Double, to other: QuantityUnit) -> Double? {
        if self == other { return value }
        guard dimension == other.dimension,
              let from = baseFactor, let to = other.baseFactor else { return nil }
        return value * from / to
    }

    static var massAndVolume: [QuantityUnit] {
        allCases.filter { $0.dimension != .count }
    }
}

// MARK: - Concentration units for soil results

enum ConcentrationUnit: String, CaseIterable, Codable, Identifiable {
    case ppm = "ppm"
    case mgPerKg = "mg/kg"
    case percent = "%"
    case cmolPerKg = "cmol/kg"
    case dSPerM = "dS/m"
    case mgPerL = "mg/L"

    var id: String { rawValue }
    var symbol: String { rawValue }

    /// ppm and mg/kg are numerically identical for soil; everything else needs
    /// laboratory context, so comparison across them is blocked.
    func isComparable(with other: ConcentrationUnit) -> Bool {
        if self == other { return true }
        let interchangeable: Set<ConcentrationUnit> = [.ppm, .mgPerKg]
        return interchangeable.contains(self) && interchangeable.contains(other)
    }
}

// MARK: - Formatting

enum Fmt {
    static func number(_ value: Double?, decimals: Int = 2) -> String? {
        guard let value, value.isFinite else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = decimals
        f.minimumFractionDigits = 0
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: value))
    }

    /// Formats a value with its unit, or nil when the value is unknown.
    static func quantity(_ value: Double?, _ unit: String?, decimals: Int = 2) -> String? {
        guard let text = number(value, decimals: decimals) else { return nil }
        guard let unit else { return text }
        return "\(text) \(unit)"
    }

    static func date(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func dateTime(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func dateRange(_ start: Date?, _ end: Date?) -> String? {
        switch (start, end) {
        case let (s?, e?): return "\(date(s)!) → \(date(e)!)"
        case let (s?, nil): return "from \(date(s)!)"
        case let (nil, e?): return "until \(date(e)!)"
        default: return nil
        }
    }

    static func currency(_ value: Double?, code: String) -> String? {
        guard let value else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value))
    }

    static func duration(minutes: Double?) -> String? {
        guard let minutes, minutes.isFinite else { return nil }
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total) min" }
        return "\(total / 60) h \(total % 60) min"
    }
}
