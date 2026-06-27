//
//  WeatherModels.swift
//  NotchPet
//
//  Codable models for the Open-Meteo forecast API (https://open-meteo.com/),
//  plus WMO weather-code -> (SF Symbol, condition text) mapping and the
//  lightweight value types the WeatherManager/Views consume.
//
//  Open-Meteo is free and requires no API key. We request the `current`,
//  `hourly` and `daily` blocks; the structs below mirror that JSON shape.
//

import Foundation
import Defaults

// MARK: - Units

/// Temperature unit the user can toggle in settings. Drives the `temperature_unit`
/// query parameter so Open-Meteo returns values already converted for us.
enum WeatherUnit: String, CaseIterable, Identifiable, Defaults.Serializable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"

    var id: String { rawValue }

    /// Open-Meteo expects "celsius" / "fahrenheit".
    var apiValue: String { self == .celsius ? "celsius" : "fahrenheit" }
    var symbol: String { self == .celsius ? "°C" : "°F" }
    /// Open-Meteo wind speed unit paired with the temperature choice.
    var windApiValue: String { self == .celsius ? "kmh" : "mph" }
    var windSuffix: String { self == .celsius ? "km/h" : "mph" }
}

// MARK: - Manual location stored in Defaults

/// A user-entered fallback location used when CoreLocation is denied/unavailable.
struct ManualCity: Codable, Hashable, Defaults.Serializable {
    var name: String
    var latitude: Double
    var longitude: Double
}

// MARK: - Open-Meteo raw response

/// Top-level Open-Meteo forecast response.
struct OpenMeteoResponse: Codable {
    let latitude: Double
    let longitude: Double
    let timezone: String?
    let current: CurrentWeatherBlock?
    let hourly: HourlyBlock?
    let daily: DailyBlock?

    struct CurrentWeatherBlock: Codable {
        let time: String
        let temperature2m: Double?
        let apparentTemperature: Double?
        let relativeHumidity2m: Double?
        let weatherCode: Int?
        let windSpeed10m: Double?
        let isDay: Int?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity2m = "relative_humidity_2m"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
            case isDay = "is_day"
        }
    }

    struct HourlyBlock: Codable {
        let time: [String]
        let temperature2m: [Double]?
        let weatherCode: [Int]?
        let precipitationProbability: [Int?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitationProbability = "precipitation_probability"
        }
    }

    struct DailyBlock: Codable {
        let time: [String]
        let weatherCode: [Int]?
        let temperature2mMax: [Double]?
        let temperature2mMin: [Double]?
        let precipitationProbabilityMax: [Int?]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }
}

// MARK: - View-facing value types

/// Snapshot of "right now" conditions.
struct CurrentWeather: Equatable {
    let temperature: Double
    let apparentTemperature: Double?
    let humidity: Double?
    let windSpeed: Double?
    let code: Int
    let isDay: Bool

    var symbol: String { WMOCode.symbol(for: code, isDay: isDay) }
    var condition: String { WMOCode.text(for: code) }
}

/// One hour in the hourly strip.
struct HourlyForecast: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let temperature: Double
    let code: Int
    let isDay: Bool
    let precipitationProbability: Int?

    var symbol: String { WMOCode.symbol(for: code, isDay: isDay) }
}

/// One day in the daily strip.
struct DailyForecast: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let high: Double
    let low: Double
    let code: Int
    let precipitationProbability: Int?

    var symbol: String { WMOCode.symbol(for: code, isDay: true) }
    var condition: String { WMOCode.text(for: code) }
}

// MARK: - WMO code mapping

/// Maps WMO weather interpretation codes (as returned by Open-Meteo) to an
/// SF Symbol and a short human-readable condition string.
/// Reference: https://open-meteo.com/en/docs (WMO Weather interpretation codes).
enum WMOCode {
    /// SF Symbol for a code, choosing day/night variants where it matters.
    static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0:                         return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1:                         return isDay ? "sun.max.fill" : "moon.fill"
        case 2:                         return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:                         return "cloud.fill"
        case 45, 48:                    return "cloud.fog.fill"
        case 51, 53, 55:                return "cloud.drizzle.fill"           // drizzle
        case 56, 57:                    return "cloud.sleet.fill"             // freezing drizzle
        case 61, 63, 65:                return "cloud.rain.fill"              // rain
        case 66, 67:                    return "cloud.sleet.fill"            // freezing rain
        case 71, 73, 75, 77:            return "cloud.snow.fill"             // snow
        case 80, 81, 82:                return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill" // showers
        case 85, 86:                    return "cloud.snow.fill"            // snow showers
        case 95:                        return "cloud.bolt.rain.fill"       // thunderstorm
        case 96, 99:                    return "cloud.bolt.rain.fill"       // thunderstorm w/ hail
        default:                        return "cloud.fill"
        }
    }

    /// Short condition text for a code.
    static func text(for code: Int) -> String {
        switch code {
        case 0:                 return "Clear"
        case 1:                 return "Mainly Clear"
        case 2:                 return "Partly Cloudy"
        case 3:                 return "Overcast"
        case 45, 48:            return "Fog"
        case 51:                return "Light Drizzle"
        case 53:                return "Drizzle"
        case 55:                return "Heavy Drizzle"
        case 56, 57:            return "Freezing Drizzle"
        case 61:                return "Light Rain"
        case 63:                return "Rain"
        case 65:                return "Heavy Rain"
        case 66, 67:            return "Freezing Rain"
        case 71:                return "Light Snow"
        case 73:                return "Snow"
        case 75:                return "Heavy Snow"
        case 77:                return "Snow Grains"
        case 80:                return "Light Showers"
        case 81:                return "Showers"
        case 82:                return "Heavy Showers"
        case 85, 86:            return "Snow Showers"
        case 95:                return "Thunderstorm"
        case 96, 99:            return "Thunderstorm, Hail"
        default:                return "Unknown"
        }
    }
}
