//
//  WeatherSnapshot.swift
//  JARVIS
//
//  Value types describing the local weather shown in the header.
//  Data comes from Open-Meteo, which needs no API key.
//

import Foundation

/// Temperature unit preference.
enum TemperatureUnit: String, CaseIterable, Identifiable, Codable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    /// Symbol appended to rendered temperatures.
    var symbol: String {
        switch self {
        case .celsius: return "C"
        case .fahrenheit: return "F"
        }
    }

    /// Converts a Celsius value into this unit.
    func value(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9 / 5 + 32
        }
    }

    /// Produces a rounded, unit suffixed string such as "18 C".
    func formatted(celsius: Double, includeUnit: Bool = true) -> String {
        let rounded = Int(value(fromCelsius: celsius).rounded())
        return includeUnit ? "\(rounded) \(symbol)" : "\(rounded)"
    }
}

/// Coarse weather condition mapped from the WMO weather interpretation codes.
enum WeatherCondition: String, Codable, CaseIterable {
    case clear
    case mostlyClear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case rain
    case snow
    case thunderstorm
    case unknown

    /// SF Symbol for the condition.
    var symbolName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .mostlyClear: return "sun.min.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .overcast: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .unknown: return "cloud.fill"
        }
    }

    /// Short description rendered next to the temperature.
    var summary: String {
        switch self {
        case .clear: return "Clear"
        case .mostlyClear: return "Mostly clear"
        case .partlyCloudy: return "Partly cloudy"
        case .overcast: return "Overcast"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .thunderstorm: return "Thunderstorm"
        case .unknown: return "Unknown"
        }
    }

    /// Maps a WMO code from Open-Meteo onto a condition.
    static func fromWMOCode(_ code: Int) -> WeatherCondition {
        switch code {
        case 0: return .clear
        case 1: return .mostlyClear
        case 2: return .partlyCloudy
        case 3: return .overcast
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57: return .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunderstorm
        default: return .unknown
        }
    }
}

/// A weather reading for one location.
struct WeatherSnapshot: Equatable, Codable {
    /// City name resolved from the coordinates used for the lookup.
    var locationName: String
    /// Temperature in Celsius.
    var temperatureCelsius: Double
    /// Feels like temperature in Celsius.
    var apparentCelsius: Double
    /// Wind speed in kilometers per hour.
    var windKph: Double
    /// Relative humidity percentage.
    var humidityPercent: Int
    /// Mapped condition.
    var condition: WeatherCondition
    /// True when the location is currently in daylight.
    var isDaylight: Bool
    /// When the reading was fetched.
    var updatedAt: Date

    /// Renders the temperature in the requested unit.
    func temperatureText(unit: TemperatureUnit) -> String {
        unit.formatted(celsius: temperatureCelsius)
    }

    /// Renders the apparent temperature in the requested unit.
    func apparentText(unit: TemperatureUnit) -> String {
        "Feels like " + unit.formatted(celsius: apparentCelsius)
    }
}
