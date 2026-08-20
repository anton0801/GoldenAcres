//
//  WorkWindowEngine.swift
//  GoldenAcres
//
//  Matches user-defined thresholds against a forecast and explains every
//  interval it accepts or rejects. A window is a planning hint, not a promise
//  about conditions — the UI says so wherever a window is shown.
//
//  A missing measurement is never treated as a pass: the hour is marked
//  "cannot verify" and reported as such.
//

import Foundation

// MARK: - Per-hour verdict

struct HourVerdict: Identifiable {
    enum Outcome {
        case pass
        case fail
        case unverifiable
    }

    let id = UUID()
    var hour: WeatherHour
    var outcome: Outcome
    /// Human-readable reasons, e.g. "Wind 24 km/h exceeds max 15 km/h".
    var failures: [String]
    var unverified: [String]

    var isUsable: Bool { outcome == .pass }
}

// MARK: - Window

struct WorkWindow: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
    var verdicts: [HourVerdict]
    var isAccepted: Bool
    /// Why this stretch was rejected, when it was.
    var rejectionReasons: [String]

    var durationHours: Int {
        max(Int(end.timeIntervalSince(start) / 3600), 0)
    }

    var summary: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM, HH:mm"
        let e = DateFormatter()
        e.dateFormat = "HH:mm"
        return "\(f.string(from: start)) – \(e.string(from: end))"
    }

    /// Worst-case readings inside the window, for an at-a-glance check.
    var peakWind: Double? { verdicts.compactMap(\.hour.windSpeedKMH).max() }
    var totalRain: Double? {
        let values = verdicts.compactMap(\.hour.precipitationMM)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    var temperatureRange: (min: Double, max: Double)? {
        let values = verdicts.compactMap(\.hour.temperatureC)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return (lo, hi)
    }
}

struct WorkWindowAnalysis {
    var accepted: [WorkWindow]
    var rejected: [WorkWindow]
    var horizonEnd: Date?
    /// True when the requested search range extends past the forecast horizon.
    var exceedsHorizon: Bool
    var evaluatedHourCount: Int
    var provenance: Provenance
    /// Variables the forecast never supplied, so thresholds on them could not
    /// be checked at all.
    var unavailableVariables: [String]
}

// MARK: - Engine

enum WorkWindowEngine {

    static func analyze(snapshot: ForecastSnapshot,
                        conditions: WorkConditions,
                        from searchStart: Date = Date(),
                        through searchEnd: Date? = nil) -> WorkWindowAnalysis {

        let horizon = snapshot.horizonEnd
        let upperBound = searchEnd ?? horizon ?? searchStart
        let hours = snapshot.hours
            .filter { $0.time >= searchStart && $0.time <= upperBound }
            .sorted { $0.time < $1.time }

        let verdicts = hours.map { evaluate(hour: $0, conditions: conditions, snapshot: snapshot) }

        // Group consecutive hours by usability.
        var groups: [[HourVerdict]] = []
        for verdict in verdicts {
            if var last = groups.last,
               let previous = last.last,
               previous.isUsable == verdict.isUsable,
               verdict.hour.time.timeIntervalSince(previous.hour.time) <= 3700 {
                last.append(verdict)
                groups[groups.count - 1] = last
            } else {
                groups.append([verdict])
            }
        }

        var accepted: [WorkWindow] = []
        var rejected: [WorkWindow] = []

        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let start = first.hour.time
            let end = last.hour.time.addingTimeInterval(3600)
            let usable = first.isUsable
            let lengthHours = group.count

            if usable {
                if lengthHours >= conditions.minimumDurationHours {
                    accepted.append(WorkWindow(start: start, end: end, verdicts: group,
                                               isAccepted: true, rejectionReasons: []))
                } else {
                    rejected.append(
                        WorkWindow(start: start, end: end, verdicts: group, isAccepted: false,
                                   rejectionReasons: [
                                    "Conditions fit, but the stretch is \(lengthHours) h and you require at least \(conditions.minimumDurationHours) h."
                                   ])
                    )
                }
            } else {
                // Summarise the distinct reasons across the stretch.
                var reasonCounts: [String: Int] = [:]
                for verdict in group {
                    for reason in verdict.failures { reasonCounts[reason, default: 0] += 1 }
                    for reason in verdict.unverified {
                        reasonCounts["Cannot verify: \(reason)", default: 0] += 1
                    }
                }
                let reasons = reasonCounts
                    .sorted { $0.value > $1.value }
                    .prefix(4)
                    .map { "\($0.key) (\($0.value) h)" }
                rejected.append(WorkWindow(start: start, end: end, verdicts: group,
                                           isAccepted: false,
                                           rejectionReasons: Array(reasons)))
            }
        }

        var unavailable: [String] = []
        func allNil(_ keyPath: KeyPath<WeatherHour, Double?>) -> Bool {
            !hours.isEmpty && hours.allSatisfy { $0[keyPath: keyPath] == nil }
        }
        if conditions.minSoilTemperatureC != nil, allNil(\.soilTemperatureC) {
            unavailable.append("Soil temperature")
        }
        if (conditions.maxHumidityPercent != nil || conditions.minHumidityPercent != nil),
           allNil(\.humidityPercent) {
            unavailable.append("Humidity")
        }
        if conditions.maxWindKMH != nil, allNil(\.windSpeedKMH) {
            unavailable.append("Wind speed")
        }

        let exceeds: Bool = {
            guard let horizon, let requestedEnd = searchEnd else { return false }
            return requestedEnd > horizon
        }()

        return WorkWindowAnalysis(
            accepted: accepted,
            rejected: rejected,
            horizonEnd: horizon,
            exceedsHorizon: exceeds,
            evaluatedHourCount: hours.count,
            provenance: snapshot.provenance,
            unavailableVariables: unavailable
        )
    }

    // MARK: - Single hour

    static func evaluate(hour: WeatherHour,
                         conditions: WorkConditions,
                         snapshot: ForecastSnapshot?) -> HourVerdict {
        var failures: [String] = []
        var unverified: [String] = []

        func check(_ value: Double?,
                   label: String,
                   unit: String,
                   min: Double? = nil,
                   max: Double? = nil) {
            guard min != nil || max != nil else { return }
            guard let value else {
                unverified.append("\(label) not provided by the forecast")
                return
            }
            if let min, value < min {
                failures.append("\(label) \(fmt(value)) \(unit) below minimum \(fmt(min)) \(unit)")
            }
            if let max, value > max {
                failures.append("\(label) \(fmt(value)) \(unit) exceeds maximum \(fmt(max)) \(unit)")
            }
        }

        check(hour.temperatureC, label: "Temperature", unit: "°C",
              min: conditions.minTemperatureC, max: conditions.maxTemperatureC)
        check(hour.windSpeedKMH, label: "Wind", unit: "km/h",
              max: conditions.maxWindKMH)
        check(hour.precipitationMM, label: "Rain", unit: "mm",
              max: conditions.maxPrecipitationMM)
        check(hour.humidityPercent, label: "Humidity", unit: "%",
              min: conditions.minHumidityPercent, max: conditions.maxHumidityPercent)
        check(hour.soilTemperatureC, label: "Soil temperature", unit: "°C",
              min: conditions.minSoilTemperatureC)

        if conditions.daylightOnly {
            switch snapshot?.isDaylight(hour.time) {
            case .some(true):
                break
            case .some(false):
                failures.append("Outside daylight hours")
            case .none:
                unverified.append("Sunrise/sunset not provided for this day")
            }
        }

        let outcome: HourVerdict.Outcome
        if !failures.isEmpty {
            outcome = .fail
        } else if !unverified.isEmpty {
            // Unverifiable is not a pass — the app will not claim conditions
            // are suitable using data it does not have.
            outcome = .unverifiable
        } else {
            outcome = .pass
        }

        return HourVerdict(hour: hour, outcome: outcome,
                           failures: failures, unverified: unverified)
    }

    private static func fmt(_ value: Double) -> String {
        Fmt.number(value, decimals: 1) ?? "—"
    }

    // MARK: - Change detection

    /// Compares a task's original window against a newer forecast and reports
    /// what changed. The caller flags the task for review; nothing is moved.
    static func changeSummary(for window: (start: Date, end: Date),
                              conditions: WorkConditions,
                              newSnapshot: ForecastSnapshot) -> String? {
        let hours = newSnapshot.hours.filter { $0.time >= window.start && $0.time < window.end }
        guard !hours.isEmpty else { return nil }
        let verdicts = hours.map { evaluate(hour: $0, conditions: conditions, snapshot: newSnapshot) }
        let failing = verdicts.filter { !$0.isUsable }
        guard !failing.isEmpty else { return nil }
        let reasons = Set(failing.flatMap(\.failures)).sorted().prefix(3)
        if reasons.isEmpty {
            return "\(failing.count) h in this window can no longer be verified against the latest forecast."
        }
        return "\(failing.count) h now fail: " + reasons.joined(separator: "; ")
    }

    // MARK: - Presets

    /// Starting points only — every threshold stays editable, and none of these
    /// are presented as agronomic advice.
    static func startingThresholds(for work: WorkType) -> WorkConditions {
        switch work {
        case .spraying:
            return WorkConditions(workType: .spraying, maxWindKMH: 15,
                                  maxPrecipitationMM: 0.1, minimumDurationHours: 2,
                                  daylightOnly: true)
        case .sowing:
            return WorkConditions(workType: .sowing, maxPrecipitationMM: 1,
                                  minimumDurationHours: 4, daylightOnly: true)
        case .irrigation:
            return WorkConditions(workType: .irrigation, maxPrecipitationMM: 0.5,
                                  minimumDurationHours: 2, daylightOnly: false)
        case .harvesting:
            return WorkConditions(workType: .harvesting, maxPrecipitationMM: 0.2,
                                  minimumDurationHours: 4, daylightOnly: true)
        case .custom:
            return WorkConditions(workType: .custom, minimumDurationHours: 2,
                                  daylightOnly: false)
        }
    }
}
