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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        if let current = manager.current {
            VStack(alignment: .leading, spacing: 10) {
                currentSummary(current)
                if !manager.hourly.isEmpty || !manager.daily.isEmpty {
                    forecastStrips
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
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: current.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 34))
                .frame(width: 44, height: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text(manager.formattedTemperature(current.temperature))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(current.condition)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 8)

            // Secondary metrics (feels-like, humidity, wind).
            VStack(alignment: .trailing, spacing: 3) {
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

    // MARK: Forecast strips

    private var forecastStrips: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !manager.hourly.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(manager.hourly) { hour in
                            HourlyCell(hour: hour, manager: manager)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            if !manager.daily.isEmpty {
                Divider().background(Color.white.opacity(0.08))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(manager.daily) { day in
                            DailyCell(day: day, manager: manager)
                        }
                    }
                    .padding(.vertical, 1)
                }
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
        VStack(spacing: 3) {
            Text(hourLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Image(systemName: hour.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 15))
                .frame(height: 18)
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
        VStack(spacing: 3) {
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
        .frame(width: 600, height: 180)
        .background(Color.black)
}
#endif
