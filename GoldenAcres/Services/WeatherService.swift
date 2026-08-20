//
//  WeatherService.swift
//  GoldenAcres
//
//  Forecast data comes from Open-Meteo (open data, no key). Every value keeps
//  its provenance and fetch time. When the network is unavailable the caller
//  gets the stored snapshot clearly flagged as cached — never a value that
//  looks live, and never a fabricated number.
//

import Foundation

enum WeatherError: LocalizedError {
    case noCoordinate
    case network(String)
    case decoding(String)
    case noCachedData

    var errorDescription: String? {
        switch self {
        case .noCoordinate:
            return "This field has no coordinates yet, so no forecast can be requested."
        case .network(let detail):
            return "Could not reach the weather service. \(detail)"
        case .decoding(let detail):
            return "The weather service replied in an unexpected format. \(detail)"
        case .noCachedData:
            return "No forecast has been downloaded for this field yet."
        }
    }
}

/// Result of a forecast request, carrying how the data was obtained.
struct WeatherFetchResult {
    var snapshot: ForecastSnapshot
    var wasServedFromCache: Bool
    /// Populated when live fetch failed but a cached snapshot was returned.
    var fallbackReason: String?
}

actor WeatherService {
    static let shared = WeatherService()

    static let sourceName = "Open-Meteo"
    static let sourceURL = "https://open-meteo.com"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches a fresh forecast; on failure returns the provided cached
    /// snapshot marked as cached, or throws when nothing is stored.
    func forecast(latitude: Double,
                  longitude: Double,
                  cached: ForecastSnapshot?,
                  forecastDays: Int = 7) async -> Result<WeatherFetchResult, WeatherError> {
        do {
            let fresh = try await fetchLive(latitude: latitude,
                                            longitude: longitude,
                                            forecastDays: forecastDays)
            return .success(WeatherFetchResult(snapshot: fresh, wasServedFromCache: false))
        } catch {
            let message = (error as? WeatherError)?.errorDescription ?? error.localizedDescription
            if var cached {
                cached.provenance.isCachedSnapshot = true
                return .success(WeatherFetchResult(snapshot: cached,
                                                   wasServedFromCache: true,
                                                   fallbackReason: message))
            }
            if let weatherError = error as? WeatherError {
                return .failure(weatherError)
            }
            return .failure(.network(message))
        }
    }

    private func fetchLive(latitude: Double,
                           longitude: Double,
                           forecastDays: Int) async throws -> ForecastSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "hourly", value: [
                "temperature_2m", "precipitation", "precipitation_probability",
                "wind_speed_10m", "wind_gusts_10m", "relative_humidity_2m",
                "soil_temperature_6cm"
            ].joined(separator: ",")),
            .init(name: "daily", value: "sunrise,sunset"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: String(forecastDays))
        ]

        guard let url = components.url else {
            throw WeatherError.network("Could not build the request URL.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WeatherError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WeatherError.network("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WeatherError.network("Service returned status \(http.statusCode).")
        }

        do {
            let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            return payload.toSnapshot(latitude: latitude, longitude: longitude)
        } catch {
            throw WeatherError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Wire format

private struct OpenMeteoResponse: Decodable {
    struct Hourly: Decodable {
        var time: [String]
        var temperature_2m: [Double?]?
        var precipitation: [Double?]?
        var precipitation_probability: [Double?]?
        var wind_speed_10m: [Double?]?
        var wind_gusts_10m: [Double?]?
        var relative_humidity_2m: [Double?]?
        var soil_temperature_6cm: [Double?]?
    }
    struct Daily: Decodable {
        var time: [String]
        var sunrise: [String?]?
        var sunset: [String?]?
    }

    var utc_offset_seconds: Int?
    var hourly: Hourly?
    var daily: Daily?

    func toSnapshot(latitude: Double, longitude: Double) -> ForecastSnapshot {
        let offset = utc_offset_seconds ?? 0
        // Open-Meteo returns local wall-clock times without a zone suffix when
        // timezone=auto; interpret them against the returned offset.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: offset) ?? .gmt
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(secondsFromGMT: offset) ?? .gmt
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        func element(_ array: [Double?]?, _ index: Int) -> Double? {
            guard let array, index < array.count else { return nil }
            return array[index]
        }

        var hours: [WeatherHour] = []
        if let hourly {
            for (index, stamp) in hourly.time.enumerated() {
                guard let date = formatter.date(from: stamp) else { continue }
                hours.append(
                    WeatherHour(
                        time: date,
                        temperatureC: element(hourly.temperature_2m, index),
                        precipitationMM: element(hourly.precipitation, index),
                        precipitationProbability: element(hourly.precipitation_probability, index),
                        windSpeedKMH: element(hourly.wind_speed_10m, index),
                        windGustKMH: element(hourly.wind_gusts_10m, index),
                        humidityPercent: element(hourly.relative_humidity_2m, index),
                        soilTemperatureC: element(hourly.soil_temperature_6cm, index)
                    )
                )
            }
        }

        var daylight: [DaylightWindow] = []
        if let daily {
            for (index, stamp) in daily.time.enumerated() {
                guard let day = dayFormatter.date(from: stamp) else { continue }
                let sunriseText = (index < (daily.sunrise?.count ?? 0)) ? daily.sunrise?[index] : nil
                let sunsetText = (index < (daily.sunset?.count ?? 0)) ? daily.sunset?[index] : nil
                daylight.append(
                    DaylightWindow(
                        date: day,
                        sunrise: sunriseText.flatMap { formatter.date(from: $0) },
                        sunset: sunsetText.flatMap { formatter.date(from: $0) }
                    )
                )
            }
        }

        return ForecastSnapshot(
            hours: hours,
            provenance: Provenance(
                source: WeatherService.sourceName,
                sourceDetail: WeatherService.sourceURL,
                retrievedAt: Date(),
                isCachedSnapshot: false
            ),
            latitude: latitude,
            longitude: longitude,
            daylight: daylight
        )
    }
}
