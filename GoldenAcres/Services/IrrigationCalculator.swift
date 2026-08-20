//
//  IrrigationCalculator.swift
//  GoldenAcres
//
//  Volume = area × effective depth. Nothing more is implied.
//
//  The calculator refuses to produce a number when an input is missing, and
//  lists what is blocking it. Evapotranspiration is never substituted with 0 —
//  if the user has not supplied a target depth, there is no target depth.
//

import Foundation

enum IrrigationCalculator {

    /// Applies 1 mm over 1 m² = 1 litre.
    static let litersPerMillimeterPerSquareMeter: Double = 1.0

    static func calculate(areaSquareMeters: Double?,
                          targetDepth: Double?,
                          depthUnit: DepthUnit,
                          rainAdjustmentMM: Double?,
                          rainAdjustmentSource: String?,
                          flow: Double?,
                          flowUnit: FlowUnit) -> IrrigationCalculation {

        var assumptions: [String] = []
        var blockers: [String] = []

        let targetMM = targetDepth.map { $0 * depthUnit.inMillimeters }

        if targetDepth == nil {
            blockers.append("No target application depth entered.")
        }
        if areaSquareMeters == nil {
            blockers.append("Field area is unknown, so the volume cannot be derived.")
        }

        // Rain credit is optional and explicit. Absent rain data means no
        // adjustment is applied — it does not mean rainfall is zero.
        let effectiveMM: Double?
        if let targetMM {
            if let rain = rainAdjustmentMM {
                effectiveMM = max(targetMM - rain, 0)
                let source = rainAdjustmentSource ?? "entered by user"
                assumptions.append("Rain credit of \(Fmt.number(rain, decimals: 1) ?? "—") mm subtracted from the target (source: \(source)).")
                if targetMM - rain < 0 {
                    assumptions.append("Rain credit exceeds the target, so the required depth is shown as 0 mm rather than a negative value.")
                }
            } else {
                effectiveMM = targetMM
                assumptions.append("No rain credit applied. This is not an assumption that rainfall will be zero — no rain figure was supplied.")
            }
        } else {
            effectiveMM = nil
        }

        let volumeLiters: Double?
        if let effectiveMM, let areaSquareMeters {
            volumeLiters = effectiveMM * areaSquareMeters * litersPerMillimeterPerSquareMeter
            assumptions.append("1 mm applied over 1 m² is taken as 1 litre.")
            assumptions.append("Assumes even distribution over the whole area; no allowance is made for system efficiency, runoff or evaporation.")
        } else {
            volumeLiters = nil
        }

        let flowLPM = flow.map { $0 * flowUnit.inLitersPerMinute }
        let minutes: Double?
        if let volumeLiters, let flowLPM, flowLPM > 0 {
            minutes = volumeLiters / flowLPM
            assumptions.append("Run time assumes the stated flow of \(Fmt.number(flow, decimals: 1) ?? "—") \(flowUnit.symbol) is delivered continuously.")
        } else {
            minutes = nil
            if flow == nil {
                blockers.append("No available flow entered, so run time cannot be estimated.")
            } else if let flowLPM, flowLPM <= 0 {
                blockers.append("Flow must be greater than zero to estimate run time.")
            }
        }

        return IrrigationCalculation(
            targetDepthMM: targetMM,
            areaSquareMeters: areaSquareMeters,
            rainAdjustmentMM: rainAdjustmentMM,
            effectiveDepthMM: effectiveMM,
            volumeLiters: volumeLiters,
            flowLitersPerMinute: flowLPM,
            estimatedMinutes: minutes,
            assumptions: assumptions,
            computedAt: Date(),
            blockers: blockers
        )
    }

    /// Turns a calculation into inspectable steps for the disclosure view.
    static func steps(for calc: IrrigationCalculation,
                      areaUnit: AreaUnit,
                      depthUnit: DepthUnit,
                      volumeUnit: VolumeUnit) -> [CalculationStep] {
        var steps: [CalculationStep] = []

        if let area = calc.areaSquareMeters {
            let converted = area / areaUnit.inSquareMeters
            steps.append(CalculationStep(
                label: "Area",
                expression: "\(Fmt.number(converted, decimals: 3) ?? "—") \(areaUnit.symbol) = \(Fmt.number(area, decimals: 0) ?? "—") m²"
            ))
        } else {
            steps.append(CalculationStep(label: "Area", expression: "Unknown",
                                         note: "Set the field area to enable this calculation.",
                                         isMissing: true))
        }

        if let target = calc.targetDepthMM {
            let converted = target / depthUnit.inMillimeters
            steps.append(CalculationStep(
                label: "Target depth",
                expression: "\(Fmt.number(converted, decimals: 2) ?? "—") \(depthUnit.symbol) = \(Fmt.number(target, decimals: 1) ?? "—") mm"
            ))
        } else {
            steps.append(CalculationStep(label: "Target depth", expression: "Not entered",
                                         isMissing: true))
        }

        if let rain = calc.rainAdjustmentMM {
            steps.append(CalculationStep(label: "Rain credit",
                                         expression: "− \(Fmt.number(rain, decimals: 1) ?? "—") mm"))
        } else {
            steps.append(CalculationStep(label: "Rain credit", expression: "None applied",
                                         note: "No rainfall figure supplied."))
        }

        if let effective = calc.effectiveDepthMM {
            steps.append(CalculationStep(label: "Effective depth",
                                         expression: "\(Fmt.number(effective, decimals: 1) ?? "—") mm"))
        }

        if let volume = calc.volumeLiters {
            let converted = volume / volumeUnit.inLiters
            steps.append(CalculationStep(
                label: "Volume",
                expression: "\(Fmt.number(calc.effectiveDepthMM, decimals: 1) ?? "—") mm × \(Fmt.number(calc.areaSquareMeters, decimals: 0) ?? "—") m² = \(Fmt.number(converted, decimals: 1) ?? "—") \(volumeUnit.symbol)"
            ))
        }

        if let minutes = calc.estimatedMinutes, let flow = calc.flowLitersPerMinute {
            steps.append(CalculationStep(
                label: "Estimated run time",
                expression: "\(Fmt.number(calc.volumeLiters, decimals: 0) ?? "—") L ÷ \(Fmt.number(flow, decimals: 1) ?? "—") L/min = \(Fmt.duration(minutes: minutes) ?? "—")"
            ))
        } else {
            steps.append(CalculationStep(label: "Estimated run time",
                                         expression: "Cannot estimate", isMissing: true))
        }

        return steps
    }
}
