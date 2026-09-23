//
//  WeatherService.swift
//  JARVIS
//
//  Local weather for the dashboard header, from Open-Meteo. No API key
//  is required and no account is involved. The location is whatever the
//  user configures in Settings; the optional IP lookup exists only for
//  the one time "use my current location" button and is clearly opt in.
//

import Foundation
import CoreLocation
import os

/// State of the weather widget.
enum WeatherStatus: Equatable {
    /// No location configured yet.
    case notConfigured
    /// A request is in flight.
    case loading
    /// A reading is available.
    case ready
    /// The last request failed.
    case failed(String)
}

/// Fetches the current conditions for the configured location.
@MainActor
@Observable
final class WeatherService {

    /// How long a reading stays fresh.
    static let refreshInterval: TimeInterval = 900

    /// Current reading, if any.
    private(set) var snapshot: WeatherSnapshot?

    /// Current status of the widget.
    private(set) var status: WeatherStatus = .notConfigured

    private let session: URLSession
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Monitor")
    private var lastFetch: Date?

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Fetching

    /// Refreshes the reading when the location changed or the data is stale.
    func refresh(settings: AppSettings, force: Bool = false) async {
        guard let latitude = settings.weatherLatitude, let longitude = settings.weatherLongitude else {
            status = .notConfigured
            snapshot = nil
            return
        }

        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < Self.refreshInterval, snapshot != nil {
            return
        }

        status = .loading
        do {
            let reading = try await fetch(latitude: latitude, longitude: longitude)
            snapshot = WeatherSnapshot(
                locationName: settings.weatherLocationName.isEmpty ? "Current location" : settings.weatherLocationName,
                temperatureCelsius: reading.temperature,
                apparentCelsius: reading.apparent,
                windKph: reading.wind,
                humidityPercent: reading.humidity,
                condition: reading.condition,
                isDaylight: reading.isDaylight,
                updatedAt: Date()
            )
            lastFetch = Date()
            status = .ready
        } catch {
            logger.debug("Weather fetch failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    /// Looks up coordinates for a place name using the Open-Meteo geocoder.
    func geocode(place: String) async throws -> (name: String, latitude: Double, longitude: Double)? {
        let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else {
            throw AIServiceError.network("The geocoding address could not be built.")
        }

        let (data, response) = try await session.data(from: url)
        try Self.validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        guard let match = decoded.results?.first else { return nil }
        return (match.name, match.latitude, match.longitude)
    }

    /// Resolves an approximate location from the public IP address.
    ///
    /// This sends the machine's public address to a third party service. It
    /// only runs when the user presses the button in Settings.
    func resolveLocationFromIP() async throws -> (name: String, latitude: Double, longitude: Double)? {
        guard let url = URL(string: "https://ipapi.co/json/") else { return nil }
        let (data, response) = try await session.data(from: url)
        try Self.validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(IPLocationResponse.self, from: data)
        guard let latitude = decoded.latitude, let longitude = decoded.longitude else { return nil }
        let name = decoded.city ?? decoded.region ?? "Current location"
        return (name, latitude, longitude)
    }

    // MARK: - Request

    private struct Reading {
        var temperature: Double
        var apparent: Double
        var wind: Double
        var humidity: Int
        var condition: WeatherCondition
        var isDaylight: Bool
    }

    private func fetch(latitude: Double, longitude: Double) async throws -> Reading {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
            ),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else {
            throw AIServiceError.network("The weather address could not be built.")
        }

        let (data, response) = try await session.data(from: url)
        try Self.validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
        guard let current = decoded.current else {
            throw AIServiceError.decoding("The weather response did not include current conditions.")
        }

        return Reading(
            temperature: current.temperature,
            apparent: current.apparentTemperature ?? current.temperature,
            wind: current.windSpeed ?? 0,
            humidity: current.humidity ?? 0,
            condition: WeatherCondition.fromWMOCode(current.weatherCode ?? -1),
            isDaylight: (current.isDay ?? 1) == 1
        )
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.network("The weather service returned a non HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.serverError(status: http.statusCode, message: ProviderHTTP.extractMessage(from: data))
        }
    }

    // MARK: - Wire types

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let apparentTemperature: Double?
            let humidity: Int?
            let windSpeed: Double?
            let weatherCode: Int?
            let isDay: Int?

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case humidity = "relative_humidity_2m"
                case windSpeed = "wind_speed_10m"
                case weatherCode = "weather_code"
                case isDay = "is_day"
            }
        }

        let current: Current?
    }

    private struct GeocodingResponse: Decodable {
        struct Place: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
        }

        let results: [Place]?
    }

    private struct IPLocationResponse: Decodable {
        let city: String?
        let region: String?
        let latitude: Double?
        let longitude: Double?
    }
}
