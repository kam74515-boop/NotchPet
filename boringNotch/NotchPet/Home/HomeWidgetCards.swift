//
//  HomeWidgetCards.swift
//  NotchPet
//
//  The compact widget cards and the horizontal board that lays out the enabled widgets
//  on the Home page. Each card reuses an existing manager singleton for its data.
//

import SwiftUI
import Defaults

// MARK: - Card chrome

/// Shared rounded-rect card background used by every widget.
private struct WidgetCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Board

struct HomeWidgetBoard: View {
    @Default(.homeWidgetsEnabled) private var enabled
    @Default(.homeWidgetsOrder) private var order
    @EnvironmentObject var vm: BoringViewModel

    private let spacing: CGFloat = 10

    var body: some View {
        let widgets = HomeWidgetRegistry.enabledOrdered
        GeometryReader { geo in
            if widgets.isEmpty {
                emptyState.frame(width: geo.size.width, height: geo.size.height)
            } else {
                let totalFlex = widgets.reduce(0) { $0 + $1.flex }
                let available = max(0, geo.size.width - spacing * CGFloat(widgets.count - 1))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(widgets) { widget in
                            let proportional = available * (widget.flex / max(totalFlex, 0.001))
                            let minimum = max(70, widget.flex * 68)
                            card(for: widget)
                                .frame(width: max(proportional, minimum))
                        }
                    }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func card(for widget: HomeWidgetKind) -> some View {
        switch widget {
        case .clock:    WidgetCard { ClockWidget() }
        case .weather:  WidgetCard { WeatherWidget() }
        case .music:    WidgetCard { MusicWidget() }
        case .calendar: CalendarWidgetCard().environmentObject(vm)
        case .todo:     WidgetCard { TodoWidget() }
        case .pomodoro: WidgetCard { PomodoroWidget() }
        case .battery:  WidgetCard { BatteryWidget() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
            Text("No widgets")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
            Text("Add widgets in Settings → Home Widgets")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Clock / Date

struct ClockWidget: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 27, weight: .semibold, design: .rounded))
            Text(now, format: .dateTime.weekday(.wide))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            Text(now, format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
        }
        .onReceive(timer) { now = $0 }
    }
}

// MARK: - Weather

struct WeatherWidget: View {
    @ObservedObject var manager = WeatherManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: manager.current?.symbol ?? "cloud.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 23))
            Text(manager.formattedTemperature(manager.current?.temperature))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(LocalizedStringKey(manager.current?.condition ?? "--"))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            Text(manager.locationName)
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .onAppear { manager.start() }
    }
}

// MARK: - Music (mini)

struct MusicWidget: View {
    @ObservedObject var music = MusicManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: music.albumArt)
                    .resizable().scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(music.songTitle)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(music.artistName)
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 22) {
                Spacer(minLength: 0)
                Button { music.previousTrack() } label: { Image(systemName: "backward.fill") }
                Button { music.togglePlay() } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16))
                }
                Button { music.nextTrack() } label: { Image(systemName: "forward.fill") }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Calendar (wraps the existing CalendarView)

struct CalendarWidgetCard: View {
    var body: some View {
        CalendarView()
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - To-Do

struct TodoWidget: View {
    @ObservedObject var manager = TodoManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "checklist").font(.system(size: 11))
                Text("To-Do").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(manager.remainingCount)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            }
            Divider().overlay(Color.white.opacity(0.12))
            ForEach(manager.displayedItems.prefix(3)) { item in
                HStack(spacing: 6) {
                    Button { manager.toggleDone(item) } label: {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? Color.green : Color.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    Text(item.title)
                        .font(.system(size: 11))
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? .white.opacity(0.4) : .white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if manager.displayedItems.isEmpty {
                Text("All clear ✓")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pomodoro

struct PomodoroWidget: View {
    @ObservedObject var manager = PomodoroManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: manager.phase.symbol).foregroundStyle(manager.phase.tint)
                Text(LocalizedStringKey(manager.phase.displayName))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 0)
                Button { coordinator.currentView = .pomodoro } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("Set Pomodoro duration")
                .accessibilityLabel("Set Pomodoro duration")
            }
            Text(manager.remainingString)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 16) {
                Button { manager.toggle() } label: {
                    Image(systemName: manager.isRunning ? "pause.fill" : "play.fill")
                }
                Button { manager.skip() } label: { Image(systemName: "forward.end.fill") }
                Button { manager.reset() } label: { Image(systemName: "arrow.counterclockwise") }
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Battery

struct BatteryWidget: View {
    @ObservedObject var battery = BatteryStatusViewModel.shared

    private var fraction: Double {
        let maxCap = Double(battery.maxCapacity)
        let lvl = Double(battery.levelBattery)
        if maxCap > 0 { return min(1, max(0, lvl / maxCap)) }
        return min(1, max(0, lvl / 100))
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((fraction * 100).rounded()))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .frame(width: 48, height: 48)
            Text(statusText)
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ringColor: Color {
        if battery.isCharging { return .green }
        return fraction < 0.2 ? .red : .white
    }

    private var statusText: String {
        if battery.isCharging { return "Charging" }
        if battery.isInLowPowerMode { return "Low Power" }
        return battery.isPluggedIn ? "Plugged" : "Battery"
    }
}
