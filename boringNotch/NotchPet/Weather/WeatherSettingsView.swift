//
//  WeatherSettingsView.swift
//  NotchPet
//
//  Settings pane for the Weather module: temperature unit (C/F), whether to use
//  CoreLocation, a manual-city fallback (name + lat/lon), and the refresh interval.
//

import SwiftUI
import CoreLocation
import Defaults

struct WeatherSettingsView: View {
    @ObservedObject var manager = WeatherManager.shared

    @Default(.weatherUnit) private var unit
    @Default(.weatherUseLocation) private var useLocation
    @Default(.weatherManualCity) private var manualCity
    @Default(.weatherRefreshMinutes) private var refreshMinutes

    // Local editable copies for the manual-city text fields so we only commit on apply.
    @State private var cityName: String = ""
    @State private var latText: String = ""
    @State private var lonText: String = ""

    var body: some View {
        Form {
            Section("Units") {
                Picker("Temperature", selection: $unit) {
                    Text("Celsius (°C)").tag(WeatherUnit.celsius)
                    Text("Fahrenheit (°F)").tag(WeatherUnit.fahrenheit)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Use my location", isOn: $useLocation)
                if useLocation {
                    locationStatusRow
                }
            } header: {
                Text("Location")
            } footer: {
                Text("When location access is off or denied, the manual city below is used instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("City name", text: $cityName)
                HStack {
                    TextField("Latitude", text: $latText)
                        .frame(maxWidth: .infinity)
                    TextField("Longitude", text: $lonText)
                        .frame(maxWidth: .infinity)
                }
                Button("Save manual city") { applyManualCity() }
                    .disabled(!isManualCityValid)
            } header: {
                Text("Manual City")
            } footer: {
                Text("Enter coordinates between -90…90 (latitude) and -180…180 (longitude). Used as a fallback for weather data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Refresh") {
                Stepper(value: $refreshMinutes, in: 5...180, step: 5) {
                    Text("Every \(refreshMinutes) minutes")
                }
                Button("Refresh now") { manager.refresh() }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadFields)
    }

    // MARK: Location status

    @ViewBuilder
    private var locationStatusRow: some View {
        let status = CLLocationManager().authorizationStatus
        HStack(spacing: 6) {
            Image(systemName: statusIcon(status))
                .foregroundStyle(statusColor(status))
            Text(statusText(status))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func statusIcon(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways, .authorized: return "checkmark.circle.fill"
        case .denied, .restricted:           return "exclamationmark.triangle.fill"
        default:                              return "questionmark.circle"
        }
    }

    private func statusColor(_ status: CLAuthorizationStatus) -> Color {
        switch status {
        case .authorizedAlways, .authorized: return .green
        case .denied, .restricted:           return .orange
        default:                             return .secondary
        }
    }

    private func statusText(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways, .authorized:
            return "Location access granted"
        case .denied:
            return "Location denied — using manual city. Enable in System Settings › Privacy."
        case .restricted:
            return "Location restricted — using manual city."
        case .notDetermined:
            return "Location permission will be requested when the Weather tab opens."
        @unknown default:
            return "Location status unknown — using manual city."
        }
    }

    // MARK: Manual-city editing

    private func loadFields() {
        cityName = manualCity.name
        latText = String(manualCity.latitude)
        lonText = String(manualCity.longitude)
    }

    private var parsedLat: Double? {
        guard let v = Double(latText.trimmingCharacters(in: .whitespaces)),
              (-90.0...90.0).contains(v) else { return nil }
        return v
    }

    private var parsedLon: Double? {
        guard let v = Double(lonText.trimmingCharacters(in: .whitespaces)),
              (-180.0...180.0).contains(v) else { return nil }
        return v
    }

    private var isManualCityValid: Bool {
        parsedLat != nil && parsedLon != nil
            && !cityName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func applyManualCity() {
        guard let lat = parsedLat, let lon = parsedLon else { return }
        manualCity = ManualCity(
            name: cityName.trimmingCharacters(in: .whitespaces),
            latitude: lat,
            longitude: lon
        )
        // Writing to Defaults triggers the manager's publisher subscription to refetch.
    }
}
