//
//  WeatherManager.swift
//  NotchPet
//
//  Singleton that resolves a location (CoreLocation, with a manual-city fallback)
//  and fetches current + hourly + daily weather from Open-Meteo via URLSession.
//  Results are cached, refreshed on a user-configurable interval, and published
//  for the SwiftUI views. Works gracefully when location is denied.
//

import Foundation
import CoreLocation
import Combine
import Defaults

// MARK: - Defaults keys

extension Defaults.Keys {
    /// Temperature unit (and paired wind unit) for display.
    static let weatherUnit = Key<WeatherUnit>("notchpet.weather.unit", default: .celsius)
    /// When true, prefer CoreLocation; otherwise always use the manual city.
    static let weatherUseLocation = Key<Bool>("notchpet.weather.useLocation", default: true)
    /// Manual fallback city used when location is denied/unset or "use location" is off.
    static let weatherManualCity = Key<ManualCity>(
        "notchpet.weather.manualCity",
        default: ManualCity(name: "San Francisco", latitude: 37.7749, longitude: -122.4194)
    )
    /// Refresh interval in minutes (clamped on use).
    static let weatherRefreshMinutes = Key<Int>("notchpet.weather.refreshMinutes", default: 30)
}

@MainActor
final class WeatherManager: NSObject, ObservableObject {
    static let shared = WeatherManager()

    // MARK: Published state

    @Published private(set) var current: CurrentWeather?
    @Published private(set) var hourly: [HourlyForecast] = []
    @Published private(set) var daily: [DailyForecast] = []
    @Published private(set) var locationName: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    // MARK: Private

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var refreshTimer: Timer?
    private var fetchTask: Task<Void, Never>?
    /// Coordinate used for the most recent successful fetch (drives the timer refresh).
    private var lastCoordinate: CLLocationCoordinate2D?
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        // Re-fetch when the user changes unit / location preferences / manual city.
        // Reactions are no-ops until start() has run so we never fetch before the
        // Weather tab is first shown.
        Defaults.publisher(.weatherUnit)
            .sink { [weak self] _ in
                // Unit change only needs a refetch at the same coordinate.
                Task { @MainActor in
                    guard let self, self.started else { return }
                    if let coord = self.lastCoordinate {
                        self.fetch(at: coord)
                    } else {
                        self.resolveLocationAndFetch()
                    }
                }
            }
            .store(in: &cancellables)
        Defaults.publisher(.weatherUseLocation)
            .sink { [weak self] _ in Task { @MainActor in self?.reactToSettingChange() } }
            .store(in: &cancellables)
        Defaults.publisher(.weatherManualCity)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.started else { return }
                    if !self.usingDeviceLocation { self.resolveLocationAndFetch() }
                }
            }
            .store(in: &cancellables)
        Defaults.publisher(.weatherRefreshMinutes)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.started else { return }
                    self.startRefreshTimer()
                }
            }
            .store(in: &cancellables)
    }

    /// Re-resolve location and refetch in response to a settings change (unit or
    /// use-location toggle), but only once the module is active.
    private func reactToSettingChange() {
        guard started else { return }
        resolveLocationAndFetch()
    }

    /// Whether we should attempt to use the device location right now.
    private var usingDeviceLocation: Bool {
        guard Defaults[.weatherUseLocation] else { return false }
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorized, .notDetermined:
            return true
        default:
            return false
        }
    }

    // MARK: Lifecycle

    /// Call once (e.g. when the Weather tab first appears). Idempotent.
    func start() {
        guard !started else { return }
        started = true
        resolveLocationAndFetch()
        startRefreshTimer()
    }

    /// Force a refresh using the current location/manual city.
    func refresh() {
        resolveLocationAndFetch()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let minutes = max(5, Defaults[.weatherRefreshMinutes])
        let interval = TimeInterval(minutes) * 60
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.resolveLocationAndFetch() }
        }
        // Tolerance keeps the timer cheap and lets it coalesce across sleep wakeups.
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: Location resolution

    private func resolveLocationAndFetch() {
        errorMessage = nil
        if usingDeviceLocation {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
                // Delegate callback will request a location once authorized.
            case .authorizedAlways, .authorized:
                locationManager.requestLocation()
            default:
                fallbackToManualCity()
            }
        } else {
            fallbackToManualCity()
        }
    }

    private func fallbackToManualCity() {
        let city = Defaults[.weatherManualCity]
        let coord = CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude)
        lastCoordinate = coord
        locationName = city.name.isEmpty ? "Manual Location" : city.name
        fetch(at: coord)
    }

    // MARK: Networking

    private func fetch(at coordinate: CLLocationCoordinate2D) {
        lastCoordinate = coordinate
        fetchTask?.cancel()
        isLoading = true
        let unit = Defaults[.weatherUnit]

        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await Self.fetchOpenMeteo(coordinate: coordinate, unit: unit)
                if Task.isCancelled { return }
                self.apply(response: response, unit: unit)
            } catch is CancellationError {
                // Superseded by a newer request; ignore.
            } catch {
                if Task.isCancelled { return }
                self.isLoading = false
                // Keep any cached data on screen but surface the failure.
                self.errorMessage = (error as? URLError) != nil
                    ? "No connection"
                    : "Couldn't load weather"
            }
        }
    }

    /// Builds the Open-Meteo URL and decodes the response. `nonisolated static`
    /// so the network/decoding work happens off the main actor.
    nonisolated private static func fetchOpenMeteo(
        coordinate: CLLocationCoordinate2D,
        unit: WeatherUnit
    ) async throws -> OpenMeteoResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "current",
                         value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            URLQueryItem(name: "daily",
                         value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "temperature_unit", value: unit.apiValue),
            URLQueryItem(name: "wind_speed_unit", value: unit.windApiValue),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    }

    // MARK: Mapping

    private func apply(response: OpenMeteoResponse, unit: WeatherUnit) {
        // Parse Open-Meteo's "yyyy-MM-dd'T'HH:mm" (current/hourly) and "yyyy-MM-dd" (daily)
        // local timestamps. timezone=auto means strings are in the location's local time.
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        hourFormatter.locale = Locale(identifier: "en_US_POSIX")
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let tz = response.timezone, let timeZone = TimeZone(identifier: tz) {
            hourFormatter.timeZone = timeZone
            dayFormatter.timeZone = timeZone
        }

        // Current
        if let c = response.current, let temp = c.temperature2m, let code = c.weatherCode {
            current = CurrentWeather(
                temperature: temp,
                apparentTemperature: c.apparentTemperature,
                humidity: c.relativeHumidity2m,
                windSpeed: c.windSpeed10m,
                code: code,
                isDay: (c.isDay ?? 1) == 1
            )
        }

        // Hourly: show the next 12 hours from "now".
        if let h = response.hourly,
           let temps = h.temperature2m,
           let codes = h.weatherCode {
            let now = Date()
            var built: [HourlyForecast] = []
            let count = min(h.time.count, temps.count, codes.count)
            for i in 0..<count {
                guard let date = hourFormatter.date(from: h.time[i]) else { continue }
                let prob = h.precipitationProbability?[safe: i] ?? nil
                let isDay = isDaytime(date, response: response)
                built.append(HourlyForecast(
                    date: date,
                    temperature: temps[i],
                    code: codes[i],
                    isDay: isDay,
                    precipitationProbability: prob
                ))
            }
            // Keep from the current hour onward; cap to 12 entries.
            let upcoming = built.filter { $0.date >= now.addingTimeInterval(-3600) }
            hourly = Array(upcoming.prefix(12))
        }

        // Daily
        if let d = response.daily,
           let codes = d.weatherCode,
           let highs = d.temperature2mMax,
           let lows = d.temperature2mMin {
            var built: [DailyForecast] = []
            let count = min(d.time.count, codes.count, highs.count, lows.count)
            for i in 0..<count {
                guard let date = dayFormatter.date(from: d.time[i]) else { continue }
                let prob = d.precipitationProbabilityMax?[safe: i] ?? nil
                built.append(DailyForecast(
                    date: date,
                    high: highs[i],
                    low: lows[i],
                    code: codes[i],
                    precipitationProbability: prob
                ))
            }
            daily = Array(built.prefix(7))
        }

        isLoading = false
        errorMessage = nil
        lastUpdated = Date()
    }

    /// Rough day/night classification for an hourly entry based on local hour.
    /// Open-Meteo only returns is_day for `current`, so approximate for hourly.
    private func isDaytime(_ date: Date, response: OpenMeteoResponse) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        if let tz = response.timezone, let timeZone = TimeZone(identifier: tz) {
            calendar.timeZone = timeZone
        }
        let hour = calendar.component(.hour, from: date)
        return (6...19).contains(hour)
    }

    // MARK: Formatting helpers (used by the views)

    func formattedTemperature(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))\(Defaults[.weatherUnit].symbol)"
    }

    /// Temperature value only (no degree symbol) for compact strips.
    func roundedTemp(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorized:
                if Defaults[.weatherUseLocation] {
                    manager.requestLocation()
                } else {
                    self.fallbackToManualCity()
                }
            case .denied, .restricted:
                self.fallbackToManualCity()
            case .notDetermined:
                break // waiting on the user's choice
            @unknown default:
                self.fallbackToManualCity()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.fetch(at: location.coordinate)
            self.reverseGeocode(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // CoreLocation failed: drop back to the manual city so the UI still works.
            if self.current == nil {
                self.fallbackToManualCity()
            }
        }
    }

    /// Turn coordinates into a friendly place name for the header.
    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self else { return }
                if let place = placemarks?.first {
                    self.locationName = place.locality
                        ?? place.subAdministrativeArea
                        ?? place.administrativeArea
                        ?? "Current Location"
                } else if self.locationName.isEmpty {
                    self.locationName = "Current Location"
                }
            }
        }
    }
}

// MARK: - Safe indexing

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
