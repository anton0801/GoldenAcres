//
//  RecordEntities.swift
//  GoldenAcres
//
//  Evidentiary records: observations, soil tests, irrigation, applications.
//  These keep name snapshots of their parents so a record stays readable even
//  if the parent is later removed.
//

import Foundation
import SwiftData

// MARK: - Observation

@Model
final class FieldObservation {
    var id: UUID = UUID()
    var date: Date = Date()
    var observationTypeRaw: String = ObservationType.generalNote.rawValue
    var severityRaw: String? = nil
    var notes: String? = nil
    /// Filenames in the app's photo store. The original is never overwritten
    /// by any analysis result.
    var photoFilenames: [String] = []
    var affectedAreaValue: Double? = nil
    var affectedAreaUnitRaw: String = AreaUnit.hectare.rawValue
    var relatedCropStage: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var seasonID: UUID? = nil
    var fieldNameSnapshot: String = ""

    /// Machine suggestion kept strictly separate from the confirmed category.
    var imageSuggestion: ImageSuggestion? = nil
    var confirmedCategory: String? = nil
    var linkedTaskID: UUID? = nil
    var reviewRequested: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false

    var field: FarmField?

    init(date: Date = Date(), type: ObservationType = .generalNote, field: FarmField? = nil) {
        self.id = UUID()
        self.date = date
        self.observationTypeRaw = type.rawValue
        self.field = field
        self.fieldNameSnapshot = field?.name ?? ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var observationType: ObservationType {
        get { ObservationType(rawValue: observationTypeRaw) ?? .generalNote }
        set { observationTypeRaw = newValue.rawValue }
    }

    var severity: Severity? {
        get { severityRaw.flatMap(Severity.init(rawValue:)) }
        set { severityRaw = newValue?.rawValue }
    }

    var affectedAreaUnit: AreaUnit {
        get { AreaUnit(rawValue: affectedAreaUnitRaw) ?? .hectare }
        set { affectedAreaUnitRaw = newValue.rawValue }
    }

    var isDetached: Bool { field == nil }

    var summaryLine: String {
        if let notes, !notes.isEmpty { return notes }
        if !photoFilenames.isEmpty { return "\(photoFilenames.count) photo(s), no note" }
        return "No details recorded"
    }
}

// MARK: - Soil test

@Model
final class SoilTest {
    var id: UUID = UUID()
    var laboratory: String? = nil
    var sampleDate: Date = Date()
    var zone: String? = nil
    var depthValue: Double? = nil
    var depthUnitRaw: String = DepthUnit.centimeter.rawValue

    var ph: Double? = nil
    var organicMatterPercent: Double? = nil

    var nitrogenValue: Double? = nil
    var nitrogenUnitRaw: String? = nil
    var phosphorusValue: Double? = nil
    var phosphorusUnitRaw: String? = nil
    var potassiumValue: Double? = nil
    var potassiumUnitRaw: String? = nil
    var salinityValue: Double? = nil
    var salinityUnitRaw: String? = nil

    var micronutrients: [SoilNutrientValue] = []

    var originalFileName: String? = nil
    var notes: String? = nil
    var statusRaw: String = SoilTestStatus.draft.rawValue

    /// Per-field extraction results from an uploaded report, each with its own
    /// confidence and page location. Only confirmed values reach analytics.
    var parsedSuggestions: [ParsedFieldSuggestion] = []
    var parseProvenance: Provenance? = nil
    var parseFailedReason: String? = nil

    var confirmedAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var fieldNameSnapshot: String = ""

    var field: FarmField?

    init(sampleDate: Date = Date(), field: FarmField? = nil) {
        self.id = UUID()
        self.sampleDate = sampleDate
        self.field = field
        self.fieldNameSnapshot = field?.name ?? ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var status: SoilTestStatus {
        get { SoilTestStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var depthUnit: DepthUnit {
        get { DepthUnit(rawValue: depthUnitRaw) ?? .centimeter }
        set { depthUnitRaw = newValue.rawValue }
    }

    var nitrogenUnit: ConcentrationUnit? {
        get { nitrogenUnitRaw.flatMap(ConcentrationUnit.init(rawValue:)) }
        set { nitrogenUnitRaw = newValue?.rawValue }
    }
    var phosphorusUnit: ConcentrationUnit? {
        get { phosphorusUnitRaw.flatMap(ConcentrationUnit.init(rawValue:)) }
        set { phosphorusUnitRaw = newValue?.rawValue }
    }
    var potassiumUnit: ConcentrationUnit? {
        get { potassiumUnitRaw.flatMap(ConcentrationUnit.init(rawValue:)) }
        set { potassiumUnitRaw = newValue?.rawValue }
    }
    var salinityUnit: ConcentrationUnit? {
        get { salinityUnitRaw.flatMap(ConcentrationUnit.init(rawValue:)) }
        set { salinityUnitRaw = newValue?.rawValue }
    }

    var isConfirmed: Bool { status == .confirmed }

    /// A numeric value without a unit cannot be compared with anything.
    var valuesMissingUnits: [String] {
        var missing: [String] = []
        if nitrogenValue != nil && nitrogenUnit == nil { missing.append("Nitrogen") }
        if phosphorusValue != nil && phosphorusUnit == nil { missing.append("Phosphorus") }
        if potassiumValue != nil && potassiumUnit == nil { missing.append("Potassium") }
        if salinityValue != nil && salinityUnit == nil { missing.append("Salinity") }
        for m in micronutrients where m.value != nil && m.unit == nil {
            missing.append(m.name)
        }
        return missing
    }

    var recordedValueCount: Int {
        [ph, organicMatterPercent, nitrogenValue, phosphorusValue,
         potassiumValue, salinityValue].compactMap { $0 }.count
            + micronutrients.compactMap(\.value).count
    }
}

// MARK: - Irrigation

@Model
final class IrrigationPlan {
    var id: UUID = UUID()
    var zone: String? = nil
    var cropStage: String? = nil
    var methodRaw: String? = nil
    var availableFlowValue: Double? = nil
    var flowUnitRaw: String = FlowUnit.litersPerMinute.rawValue
    var targetDepthValue: Double? = nil
    var depthUnitRaw: String = DepthUnit.millimeter.rawValue
    /// Rain credited against the target, taken from forecast or entered by hand.
    var rainAdjustmentMM: Double? = nil
    var rainAdjustmentSource: String? = nil
    var startWindow: Date? = nil
    var plannedDurationMinutes: Double? = nil
    var waterSource: String? = nil
    var restrictions: String? = nil
    var statusRaw: String = "draft"
    var seasonID: UUID? = nil
    var fieldNameSnapshot: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Full, inspectable calculation including blockers and assumptions.
    var calculation: IrrigationCalculation? = nil

    var field: FarmField?

    @Relationship(deleteRule: .cascade, inverse: \IrrigationRun.plan)
    var runs: [IrrigationRun] = []

    init(field: FarmField? = nil) {
        self.id = UUID()
        self.field = field
        self.fieldNameSnapshot = field?.name ?? ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var method: IrrigationMethod? {
        get { methodRaw.flatMap(IrrigationMethod.init(rawValue:)) }
        set { methodRaw = newValue?.rawValue }
    }
    var flowUnit: FlowUnit {
        get { FlowUnit(rawValue: flowUnitRaw) ?? .litersPerMinute }
        set { flowUnitRaw = newValue.rawValue }
    }
    var depthUnit: DepthUnit {
        get { DepthUnit(rawValue: depthUnitRaw) ?? .millimeter }
        set { depthUnitRaw = newValue.rawValue }
    }

    /// Recorded water is summed only across runs that share a unit.
    func totalActualLiters() -> Double? {
        let values = runs.compactMap { run -> Double? in
            guard let v = run.actualVolumeValue else { return nil }
            return v * run.volumeUnit.inLiters
        }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

@Model
final class IrrigationRun {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var actualVolumeValue: Double? = nil
    var volumeUnitRaw: String = VolumeUnit.liter.rawValue
    var meterReadingStart: Double? = nil
    var meterReadingEnd: Double? = nil
    var notes: String? = nil
    var recordedAt: Date = Date()

    var plan: IrrigationPlan?

    init(startedAt: Date = Date(), plan: IrrigationPlan? = nil) {
        self.id = UUID()
        self.startedAt = startedAt
        self.plan = plan
        self.recordedAt = Date()
    }

    var volumeUnit: VolumeUnit {
        get { VolumeUnit(rawValue: volumeUnitRaw) ?? .liter }
        set { volumeUnitRaw = newValue.rawValue }
    }

    var durationMinutes: Double? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt) / 60
    }
}

// MARK: - Input application (immutable record)

@Model
final class InputApplication {
    var id: UUID = UUID()
    var productName: String = ""
    var categoryRaw: String = InputCategory.other.rawValue
    /// Free-text reference to the official label/registration. The app never
    /// asserts that a product is approved for a use.
    var registrationNote: String? = nil
    var lotID: UUID? = nil
    var lotLabelSnapshot: String? = nil
    var quantity: Double = 0
    var quantityUnitRaw: String = QuantityUnit.liter.rawValue
    var areaTreatedValue: Double? = nil
    var areaUnitRaw: String = AreaUnit.hectare.rawValue
    var date: Date = Date()
    var operatorName: String? = nil
    var purpose: String? = nil
    var weatherSnapshot: WeatherSnapshot? = nil
    var attachmentNames: [String] = []
    var fieldID: UUID? = nil
    var fieldNameSnapshot: String = ""
    var createdAt: Date = Date()

    /// Corrections never edit history: the original is voided and a new record
    /// points back at it.
    var voidedAt: Date? = nil
    var voidReason: String? = nil
    var supersedesID: UUID? = nil

    var labelScanProvenance: Provenance? = nil

    var season: CropSeason?

    init(productName: String = "", quantity: Double = 0,
         unit: QuantityUnit = .liter, date: Date = Date()) {
        self.id = UUID()
        self.productName = productName
        self.quantity = quantity
        self.quantityUnitRaw = unit.rawValue
        self.date = date
        self.createdAt = Date()
    }

    var category: InputCategory {
        get { InputCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var quantityUnit: QuantityUnit {
        get { QuantityUnit(rawValue: quantityUnitRaw) ?? .liter }
        set { quantityUnitRaw = newValue.rawValue }
    }
    var areaUnit: AreaUnit {
        get { AreaUnit(rawValue: areaUnitRaw) ?? .hectare }
        set { areaUnitRaw = newValue.rawValue }
    }

    var isVoided: Bool { voidedAt != nil }

    /// Rate per area, only when both numbers and their units are present.
    var ratePerHectare: Double? {
        guard let areaTreatedValue, areaTreatedValue > 0 else { return nil }
        let ha = areaTreatedValue * areaUnit.inSquareMeters / AreaUnit.hectare.inSquareMeters
        guard ha > 0 else { return nil }
        return quantity / ha
    }
}
