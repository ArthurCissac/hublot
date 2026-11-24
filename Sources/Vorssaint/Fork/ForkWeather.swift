// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// The island's Weather page (see `ForkWeatherLogic`). Open-Meteo is asked
/// only while the page is open: on opening (when ten minutes have gone by),
/// then every half hour; and for suggestions while a city is typed.
final class ForkWeather: ObservableObject {
    typealias Logic = ForkWeatherLogic
    typealias City = Logic.City

    static let shared = ForkWeather()
    static let defaultShortcut = GlobalShortcut(keyCode: Int64(kVK_ANSI_W), modifiers: [.control, .option])

    /// The companion's city, looked up once by name.
    @Published private(set) var home: City?
    @Published private(set) var cities: [City] = []
    @Published private(set) var forecasts: [String: Logic.Forecast] = [:]
    @Published private(set) var failed: Set<String> = []
    @Published private(set) var suggestions: [City] = []
    @Published private(set) var searching = false

    private var fetched: [String: Date] = [:]
    private var homeName: String?
    private var open = false
    private var timer: Timer?
    private var searchWork: DispatchWorkItem?
    private var searchSession: URLSession?
    private let hotkey = QuickToolHotkey(id: 9_106)
    private var observer: NSObjectProtocol?
    /// Registering the shortcut writes a preference under upstream's lock: deferred (ForkCoalescedMainAction).
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.syncWithPreferences() }

    var enabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.forkWeatherEnabled) }

    /// Every city shown, the user's own first.
    var shown: [City] { (home.map { [$0] } ?? []) + cities.filter { $0.id != home?.id } }

    func start() {
        cities = Logic.cities(from: UserDefaults.standard.string(forKey: DefaultsKey.forkWeatherCities))
        hotkey.onPress = { NotchService.shared.open(.weather) }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.resync.schedule() }
        resync.schedule()
    }

    private func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let wanted = enabled && defaults.bool(forKey: DefaultsKey.forkWeatherShortcutEnabled)
        _ = hotkey.sync(enabled: wanted, shortcut: Self.defaultShortcut, storageKey: DefaultsKey.forkWeatherShortcut)
        let name = ForkMascotWeather.city
        if name != homeName {
            homeName = name
            home = nil
            if open { lookUpHome() }
        }
        if !enabled { pageClosed() }
    }

    // MARK: The page

    func pageOpened() {
        guard enabled else { return }
        open = true
        if home == nil { lookUpHome() }
        refresh(interval: Logic.freshFor)
        timer?.invalidate()
        let timer = Timer(timeInterval: Logic.refreshWhileOpen, repeats: true) { [weak self] _ in
            self?.refresh(interval: Logic.refreshWhileOpen - 60)
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pageClosed() {
        open = false
        timer?.invalidate(); timer = nil
        searchWork?.cancel()
        searchSession?.invalidateAndCancel()
    }

    func refresh(interval: TimeInterval = 0) {
        for city in shown where Logic.refreshDue(last: fetched[city.id], now: Date(), interval: interval) {
            load(city)
        }
    }

    private func load(_ city: City) {
        guard let url = Logic.forecastURL(city) else { return }
        fetched[city.id] = Date()
        _ = ForkSpotifyHTTP.send(URLRequest(url: url, timeoutInterval: 10), maximumBytes: Logic.maximumSize) { [weak self] status, data in
            guard let self else { return }
            guard (200...299).contains(status ?? 0), let forecast = Logic.forecast(from: data) else {
                self.failed.insert(city.id)
                self.fetched[city.id] = nil
                return
            }
            self.failed.remove(city.id)
            self.forecasts[city.id] = forecast
        }
    }

    private func lookUpHome() {
        guard let name = homeName,
              let url = ForkMascotExtrasLogic.geocodingURL(city: name, french: L10n.shared.language == .fr) else { return }
        _ = ForkSpotifyHTTP.send(URLRequest(url: url, timeoutInterval: 10), maximumBytes: Logic.maximumSize) { [weak self] status, data in
            guard let self, (200...299).contains(status ?? 0), let found = Logic.places(from: data).first,
                  name == self.homeName else { return }
            self.home = found
            if self.open { self.load(found) }
        }
    }

    // MARK: Cities

    /// Suggestions a moment after typing stops.
    func search(_ text: String) {
        searchWork?.cancel()
        searchSession?.invalidateAndCancel()
        guard let url = Logic.searchURL(text, french: L10n.shared.language == .fr) else {
            suggestions = []
            searching = false
            return
        }
        searching = true
        let work = DispatchWorkItem { [weak self] in
            self?.searchSession = ForkSpotifyHTTP.send(URLRequest(url: url, timeoutInterval: 10),
                                                       maximumBytes: Logic.maximumSize) { [weak self] status, data in
                guard let self else { return }
                self.searching = false
                self.suggestions = (200...299).contains(status ?? 0) ? Logic.places(from: data) : []
            }
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func add(_ city: City) {
        cities = Logic.adding(city, to: cities)
        UserDefaults.standard.set(Logic.stored(cities), forKey: DefaultsKey.forkWeatherCities)
        suggestions = []
        load(city)
    }

    func remove(_ city: City) {
        cities = Logic.removing(city.id, from: cities)
        UserDefaults.standard.set(Logic.stored(cities), forKey: DefaultsKey.forkWeatherCities)
        forecasts[city.id] = nil
    }

    var canAdd: Bool { cities.count < Logic.maximumCities }
}

// MARK: - The page

private let forkWeatherSun = Color(red: 1.0, green: 0.8, blue: 0.3)

private func forkWeatherTint(_ code: Int, isDay: Bool) -> Color {
    switch code {
    case 0, 1, 2: return isDay ? forkWeatherSun : Color(red: 0.75, green: 0.8, blue: 1)
    case 51...67, 80...82: return Color(red: 0.45, green: 0.7, blue: 1)
    case 71...77, 85, 86: return .white
    case 95...99: return Color(red: 0.75, green: 0.6, blue: 1)
    default: return Color(white: 0.82)
    }
}

/// The island's Weather page: one card per city, the user's own first; a
/// click unfolds the coming hours and days; a field adds a city.
struct ForkWeatherIslandPage: View {
    let size: CGSize
    @ObservedObject private var weather = ForkWeather.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var expanded: String?
    @State private var query = ""
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var french: Bool { l10n.language == .fr }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1) }

    var body: some View {
        let text = ForkWeatherStrings.current
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if weather.shown.isEmpty {
                        Text(text.empty)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    ForEach(weather.shown) { card($0, text: text) }
                    adder(text)
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: size.width, height: size.height, alignment: .top)
        .onAppear { weather.pageOpened() }
        .onDisappear { weather.pageClosed() }
    }

    private func card(_ city: ForkWeather.City, text: ForkWeatherStrings) -> some View {
        let forecast = weather.forecasts[city.id]
        let isHome = city.id == weather.home?.id
        let open = expanded == city.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: forecast.map { ForkWeatherLogic.symbol(code: $0.code, isDay: $0.isDay) } ?? "cloud")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(forecast.map { forkWeatherTint($0.code, isDay: $0.isDay) } ?? .white.opacity(0.5))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(city.name).font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                        if isHome {
                            Text(text.home)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                        }
                    }
                    Text(subtitle(forecast, city: city, text: text))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let forecast {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(ForkWeatherLogic.degrees(forecast.celsius))
                            .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        if let today = forecast.days.first {
                            Text("\(ForkWeatherLogic.degrees(today.low)) / \(ForkWeatherLogic.degrees(today.high))")
                                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                } else if weather.failed.contains(city.id) {
                    Button { weather.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain)
                        .help(text.retry)
                } else {
                    ProgressView().controlSize(.small)
                }
                if !isHome, hovered == city.id {
                    Button { withAnimation(motion) { weather.remove(city) } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help(text.remove)
                    .accessibilityLabel("\(text.remove) \(city.name)")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(motion) { expanded = open ? nil : city.id } }
            if open, let forecast { details(forecast) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(open ? 0.09 : 0.055)))
        .onHover { inside in hovered = inside ? city.id : (hovered == city.id ? nil : hovered) }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ forecast: ForkWeatherLogic.Forecast?, city: ForkWeather.City, text: ForkWeatherStrings) -> String {
        guard let forecast else { return city.country ?? "" }
        if let hour = ForkWeatherLogic.nextRain(forecast) { return text.rainAround(ForkWeatherLogic.hourLabel(hour, french: french)) }
        return ForkWeatherLogic.sky(code: forecast.code, french: french)
    }

    private func details(_ forecast: ForkWeatherLogic.Forecast) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(forecast.hours.prefix(12).enumerated()), id: \.offset) { _, hour in
                        VStack(spacing: 4) {
                            Text(ForkWeatherLogic.hourLabel(hour.hour, french: french))
                                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                            Image(systemName: ForkWeatherLogic.symbol(code: hour.code, isDay: hour.isDay))
                                .font(.system(size: 14)).symbolRenderingMode(.multicolor)
                                .foregroundStyle(forkWeatherTint(hour.code, isDay: hour.isDay))
                                .frame(height: 16)
                            Text(ForkWeatherLogic.degrees(hour.celsius))
                                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            VStack(spacing: 5) {
                ForEach(Array(forecast.days.prefix(6).enumerated()), id: \.offset) { index, day in
                    HStack(spacing: 10) {
                        Text(ForkWeatherLogic.dayLabel(day.date, index: index, french: french))
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 84, alignment: .leading)
                        Image(systemName: ForkWeatherLogic.symbol(code: day.code, isDay: true))
                            .font(.system(size: 13)).symbolRenderingMode(.multicolor)
                            .foregroundStyle(forkWeatherTint(day.code, isDay: true))
                            .frame(width: 20)
                        Text(day.rain >= 20 ? "\(day.rain) %" : "")
                            .font(.system(size: 10.5)).monospacedDigit()
                            .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1))
                            .frame(width: 36, alignment: .leading)
                        Spacer(minLength: 0)
                        Text(ForkWeatherLogic.degrees(day.low)).foregroundStyle(.white.opacity(0.6))
                        Text(ForkWeatherLogic.degrees(day.high))
                    }
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                }
            }
        }
        .padding(.leading, 42)
        .transition(.opacity)
    }

    private func adder(_ text: ForkWeatherStrings) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if weather.canAdd {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.white.opacity(0.7))
                    TextField("", text: $query, prompt: Text(text.addPlaceholder).foregroundStyle(.white.opacity(0.4)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onChange(of: query) { _, value in weather.search(value) }
                        .onSubmit { if let first = weather.suggestions.first { pick(first) } }
                    if weather.searching { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
                ForEach(weather.suggestions) { place in
                    Button { pick(place) } label: {
                        HStack(spacing: 8) {
                            Text(place.name).font(.system(size: 12.5, weight: .medium))
                            Text(place.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(text.full).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 12)
            }
        }
        .foregroundStyle(.white)
    }

    private func pick(_ place: ForkWeather.City) {
        withAnimation(motion) { weather.add(place) }
        query = ""
    }
}

// MARK: - Settings

/// The Weather page's switches, next to Todoist's and Vercel's.
struct ForkWeatherSettingsSection: View {
    @AppStorage(DefaultsKey.forkWeatherEnabled) private var enabled = true
    @AppStorage(DefaultsKey.forkWeatherShortcutEnabled) private var shortcut = true

    var body: some View {
        let text = ForkWeatherStrings.current
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.headline)
            ForkOptionRow(symbol: ForkWeatherLogic.pageSymbol, title: text.toggle, caption: text.toggleCaption) {
                Toggle(text.toggle, isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                ForkOptionRow(symbol: "command", title: text.shortcut, caption: text.shortcutCaption) {
                    Toggle(text.shortcut, isOn: $shortcut).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}
