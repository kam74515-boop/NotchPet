//
//  WeatherView.swift
//  NotchPet
//
//  The expanded-notch Weather tab: current temperature + condition icon +
//  location name, followed by a horizontal hourly strip and a daily strip.
//  Designed for the notch's black background (~560–640pt wide, ~170pt tall).
//

import SwiftUI
import Defaults

struct WeatherView: View {
    @ObservedObject var manager = WeatherManager.shared
    @Default(.weatherUnit) private var unit

    /// Which forecast the single strip is showing.
    private enum ForecastMode: String, CaseIterable { case hourly = "Hourly", daily = "Daily" }
    @State private var forecastMode: ForecastMode = .hourly

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { manager.start() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(manager.locationName.isEmpty ? "Weather" : manager.locationName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Compact hourly/daily switch, shown only when forecast data exists.
            if !manager.hourly.isEmpty || !manager.daily.isEmpty {
                modeToggle
            }

            if manager.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Button {
                    manager.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Refresh weather")
            }
        }
    }

    /// Tiny inline segmented control to switch the forecast strip.
    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(ForecastMode.allCases, id: \.self) { mode in
                Button {
                    forecastMode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(forecastMode == mode ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(forecastMode == mode ? Color.white.opacity(0.16) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        if let current = manager.current {
            VStack(alignment: .leading, spacing: 6) {
                currentSummary(current)
                if !manager.hourly.isEmpty || !manager.daily.isEmpty {
                    forecastStrip
                }
            }
        } else if let error = manager.errorMessage {
            errorState(error)
        } else {
            loadingState
        }
    }

    // MARK: Current summary

    private func currentSummary(_ current: CurrentWeather) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: current.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 28))
                .frame(width: 38, height: 32)

            VStack(alignment: .leading, spacing: 0) {
                Text(manager.formattedTemperature(current.temperature))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(current.condition)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Secondary metrics (feels-like, humidity, wind).
            VStack(alignment: .trailing, spacing: 2) {
                if let feels = current.apparentTemperature {
                    metric(icon: "thermometer.medium",
                           value: "Feels \(manager.formattedTemperature(feels))")
                }
                if let humidity = current.humidity {
                    metric(icon: "humidity.fill",
                           value: "\(Int(humidity.rounded()))%")
                }
                if let wind = current.windSpeed {
                    metric(icon: "wind",
                           value: "\(Int(wind.rounded())) \(unit.windSuffix)")
                }
            }
        }
    }

    private func metric(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: Forecast strip (single, horizontally scrollable, hourly/daily toggle)

    @ViewBuilder
    private var forecastStrip: some View {
        // Fall back to whichever data is available if the chosen mode is empty.
        let showHourly = forecastMode == .hourly ? !manager.hourly.isEmpty : manager.daily.isEmpty
        ScrollView(.horizontal, showsIndicators: false) {
            if showHourly {
                HStack(spacing: 10) {
                    ForEach(manager.hourly) { hour in
                        HourlyCell(hour: hour, manager: manager)
                    }
                }
                .padding(.vertical, 1)
            } else {
                HStack(spacing: 12) {
                    ForEach(manager.daily) { day in
                        DailyCell(day: day, manager: manager)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading weather…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.slash")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Button("Try again") { manager.refresh() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Hourly cell

private struct HourlyCell: View {
    let hour: HourlyForecast
    @ObservedObject var manager: WeatherManager

    var body: some View {
        VStack(spacing: 2) {
            Text(hourLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Image(systemName: hour.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
                .frame(height: 17)
            Text(manager.roundedTemp(hour.temperature))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            if let prob = hour.precipitationProbability, prob >= 20 {
                Text("\(prob)%")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.cyan.opacity(0.7))
            }
        }
        .frame(width: 36)
    }

    private var hourLabel: String {
        if Calendar.current.isDate(hour.date, equalTo: Date(), toGranularity: .hour) {
            return "Now"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "ha"   // e.g. 3PM
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: hour.date).lowercased()
    }
}

// MARK: - Daily cell

private struct DailyCell: View {
    let day: DailyForecast
    @ObservedObject var manager: WeatherManager

    var body: some View {
        VStack(spacing: 2) {
            Text(dayLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Image(systemName: day.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
                .frame(height: 17)
            HStack(spacing: 4) {
                Text(manager.roundedTemp(day.high))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(manager.roundedTemp(day.low))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: 42)
    }

    private var dayLabel: String {
        if Calendar.current.isDateInToday(day.date) { return "Today" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"  // Mon, Tue
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: day.date)
    }
}

#if DEBUG
#Preview {
    WeatherView()
        .frame(width: 600, height: 145)
        .background(Color.black)
}
#endif
