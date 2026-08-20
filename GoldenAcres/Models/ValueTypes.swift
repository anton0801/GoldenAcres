//
//  ValueTypes.swift
//  GoldenAcres
//
//  Codable value types stored inside models. Anything sourced from outside the
//  user's own typing carries a `Provenance` so the UI can always answer
//  "where did this come from, and when?"
//

import Foundation

// MARK: - Provenance

struct Provenance: Codable, Hashable {
    var source: String
    var sourceDetail: String?
    var retrievedAt: Date
    /// True when the value was read from a stored snapshot rather than fetched live.
    var isCachedSnapshot: Bool

    init(source: String, sourceDetail: String? = nil, retrievedAt: Date = Date(), isCachedSnapshot: Bool = false) {
        self.source = source
        self.sourceDetail = sourceDetail
        self.retrievedAt = retrievedAt
        self.isCachedSnapshot = isCachedSnapshot
    }

    /// Forecast data older than this is shown as stale rather than current.
    func isStale(maxAge: TimeInterval = 3 * 3600, now: Date = Date()) -> Bool {
        now.timeIntervalSince(retrievedAt) > maxAge
    }

    static let manualEntry = Provenance(source: "Entered by user", isCachedSnapshot: false)
}

// MARK: - Boundary

struct FieldBoundary: Codable, Hashable {
    var kind: BoundaryKind
    var points: [GeoPoint]
    /// Raw GeoJSON kept verbatim when imported, so nothing is lost in parsing.
    var geoJSONText: String?
    /// Area derived from the geometry, kept separate from the user-stated area.
    var derivedAreaSquareMeters: Double?
    var note: String?

    init(kind: BoundaryKind = .none,
         points: [GeoPoint] = [],
         geoJSONText: String? = nil,
         derivedAreaSquareMeters: Double? = nil,
         note: String? = nil) {
        self.kind = kind
        self.points = points
        self.geoJSONText = geoJSONText
        self.derivedAreaSquareMeters = derivedAreaSquareMeters
        self.note = note
    }

    static let unset = FieldBoundary()
}

struct GeoPoint: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var latitude: Double
    var longitude: Double
}

// MARK: - Weather

struct WeatherHour: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var time: Date
    /// All measures optional: a provider that omits a variable yields nil,
    /// never 0.
    var temperatureC: Double?
    var precipitationMM: Double?
    var precipitationProbability: Double?
    var windSpeedKMH: Double?
    var windGustKMH: Double?
    var humidityPercent: Double?
    var soilTemperatureC: Double?
}

/// Point-in-time weather attached to a record (e.g. an application).
struct WeatherSnapshot: Codable, Hashable {
    var capturedAt: Date
    var temperatureC: Double?
    var windSpeedKMH: Double?
    var humidityPercent: Double?
    var precipitationMM: Double?
    var provenance: Provenance
}

/// Sunrise/sunset for one day, as reported by the provider.
struct DaylightWindow: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var sunrise: Date?
    var sunset: Date?

    func contains(_ moment: Date) -> Bool? {
        guard let sunrise, let sunset else { return nil }
        return moment >= sunrise && moment <= sunset
    }
}

/// Cached forecast for one field, with the fetch time preserved.
struct ForecastSnapshot: Codable, Hashable {
    var hours: [WeatherHour]
    var provenance: Provenance
    var latitude: Double
    var longitude: Double
    var daylight: [DaylightWindow] = []

    /// Last hour the provider actually covers — beyond it the app says
    /// "no reliable forecast yet" instead of extrapolating.
    var horizonEnd: Date? { hours.map(\.time).max() }

    /// Whether a moment falls in daylight, or nil when the provider gave no
    /// sunrise/sunset for that day.
    func isDaylight(_ moment: Date) -> Bool? {
        let cal = Calendar.current
        guard let day = daylight.first(where: { cal.isDate($0.date, inSameDayAs: moment) }) else {
            return nil
        }
        return day.contains(moment)
    }
}

// MARK: - Work window thresholds

struct WorkConditions: Codable, Hashable {
    var workType: WorkType
    var minTemperatureC: Double?
    var maxTemperatureC: Double?
    var maxWindKMH: Double?
    var maxPrecipitationMM: Double?
    var maxHumidityPercent: Double?
    var minHumidityPercent: Double?
    var minSoilTemperatureC: Double?
    var minimumDurationHours: Int
    var daylightOnly: Bool

    init(workType: WorkType = .spraying,
         minTemperatureC: Double? = nil,
         maxTemperatureC: Double? = nil,
         maxWindKMH: Double? = nil,
         maxPrecipitationMM: Double? = nil,
         maxHumidityPercent: Double? = nil,
         minHumidityPercent: Double? = nil,
         minSoilTemperatureC: Double? = nil,
         minimumDurationHours: Int = 2,
         daylightOnly: Bool = true) {
        self.workType = workType
        self.minTemperatureC = minTemperatureC
        self.maxTemperatureC = maxTemperatureC
        self.maxWindKMH = maxWindKMH
        self.maxPrecipitationMM = maxPrecipitationMM
        self.maxHumidityPercent = maxHumidityPercent
        self.minHumidityPercent = minHumidityPercent
        self.minSoilTemperatureC = minSoilTemperatureC
        self.minimumDurationHours = minimumDurationHours
        self.daylightOnly = daylightOnly
    }

    var hasAnyThreshold: Bool {
        minTemperatureC != nil || maxTemperatureC != nil || maxWindKMH != nil
            || maxPrecipitationMM != nil || maxHumidityPercent != nil
            || minHumidityPercent != nil || minSoilTemperatureC != nil
    }
}

// MARK: - Soil parsing

/// One value lifted out of an uploaded lab report, kept as a *suggestion*
/// until the user confirms it.
struct ParsedFieldSuggestion: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var fieldKey: String
    var rawText: String
    var numericValue: Double?
    var unitText: String?
    var confidence: Double
    /// Where on the page the value was found, so the user can check it.
    var sourceLocation: String?
    var accepted: Bool = false
}

struct SoilNutrientValue: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var value: Double?
    var unit: ConcentrationUnit?
    var note: String?
}

// MARK: - Image suggestion

/// Output of an image classifier. Never overwrites the photo and never
/// becomes the record's category on its own.
struct ImageSuggestion: Codable, Hashable {
    var suggestedCategory: String?
    var confidence: Double?
    var provenance: Provenance
    var isReliable: Bool
    var message: String?
}

// MARK: - Tasks

struct RequiredInput: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var itemName: String
    var quantity: Double?
    var unit: QuantityUnit?
    var lotID: UUID?
    var reservationID: UUID?
}

// MARK: - Harvest revisions

struct HarvestRevision: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var timestamp: Date
    var reason: String
    var changeSummary: String
    var author: String?
}

// MARK: - Season review

struct SeasonLesson: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date
    var category: String?
}

// MARK: - Irrigation calculation record

struct IrrigationCalculation: Codable, Hashable {
    var targetDepthMM: Double?
    var areaSquareMeters: Double?
    var rainAdjustmentMM: Double?
    var effectiveDepthMM: Double?
    var volumeLiters: Double?
    var flowLitersPerMinute: Double?
    var estimatedMinutes: Double?
    var assumptions: [String]
    var computedAt: Date
    /// Reasons the calculation could not be completed, if any.
    var blockers: [String]
}

// MARK: - Export metadata

struct ExportMetadata: Codable, Hashable {
    var generatedAt: Date
    var dataRangeStart: Date?
    var dataRangeEnd: Date?
    var version: String
    var gaps: [String]
}
