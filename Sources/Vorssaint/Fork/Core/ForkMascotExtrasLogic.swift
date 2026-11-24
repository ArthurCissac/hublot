// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The companion's extras: rare little speech bubbles
/// (`forkMascotBubbles`), a mini keyboard when the user types fast
/// (`forkMascotTyping`, from the rhythm only, never a key), and the
/// weather of a chosen city (`forkMascotWeather`, from Open-Meteo, free and
/// without an account). Pure: what it says and when, when typing counts as
/// fast, and how the weather is asked for and read.
enum ForkMascotExtrasLogic {
    // MARK: - Bubbles

    enum Bubble: Equatable {
        case hello, bravo, done, pause, late(Int), bedtime, rain

        /// At most ten characters, to fit beside it in the closed island.
        func text(french: Bool) -> String {
            switch self {
            case .hello: return french ? "Bonjour !" : "Hello!"
            case .bravo: return french ? "Bravo !" : "Nice!"
            case .done: return french ? "Fini !" : "All done!"
            case .pause: return french ? "Pause ?" : "Break?"
            case .late(let count): return french ? "\(min(count, 99)) tâches" : "\(min(count, 99)) tasks"
            case .bedtime: return french ? "Dodo ?" : "Bedtime?"
            case .rain: return french ? "Il pleut" : "Rain!"
            }
        }
    }

    static let maximumBubbleLength = 10
    /// One bubble every ten minutes at most, so they stay rare.
    static let bubbleSpacing: TimeInterval = 600
    static let bubbleDuration: TimeInterval = 2.6

    static func canSpeak(now: TimeInterval, last: TimeInterval?) -> Bool {
        guard let last else { return true }
        return now - last >= bubbleSpacing
    }

    // MARK: - Typing

    /// Fast means at least this many keys a second, kept up this long.
    static let typingRate: Double = 3
    static let typingSpan: TimeInterval = 5
    /// It stops this long after the last key.
    static let typingPause: TimeInterval = 1.5

    /// Only the times of the last keys are kept, never what they were.
    static func trimmed(_ times: [TimeInterval], now: TimeInterval) -> [TimeInterval] {
        times.filter { now - $0 <= typingSpan }
    }

    /// Whether the keys pressed at `times` make fast typing at `now`.
    static func typesFast(_ times: [TimeInterval], now: TimeInterval) -> Bool {
        let recent = trimmed(times, now: now)
        guard let first = recent.first, let last = recent.last, now - last <= typingPause else { return false }
        return now - first >= typingSpan - 1 && Double(recent.count) >= typingRate * typingSpan
    }

    // MARK: - Weather

    enum Sky: String, Equatable {
        case clear, cloudy, rain, snow, storm
    }

    struct Weather: Equatable {
        var sky: Sky
        var isDay: Bool
        var celsius: Double?

        /// Sunglasses when the sun is out.
        var sunny: Bool { sky == .clear && isDay }
        /// The umbrella under rain or a storm.
        var wet: Bool { sky == .rain || sky == .storm }
    }

    /// WMO weather codes, as Open-Meteo gives them.
    static func sky(code: Int) -> Sky {
        switch code {
        case 0, 1: return .clear
        case 51...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .storm
        default: return .cloudy
        }
    }

    static let maximumSize = 1 << 18
    /// It is looked up once an hour.
    static let refreshInterval: TimeInterval = 3600

    static func refreshDue(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= refreshInterval || now < last
    }

    static func cleanCity(_ text: String) -> String? {
        let city = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty, city.count <= 80 else { return nil }
        return city
    }

    /// The first place by this name, in the user's language.
    static func geocodingURL(city: String, french: Bool) -> URL? {
        guard let city = cleanCity(city) else { return nil }
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        parts?.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"),
                             URLQueryItem(name: "language", value: french ? "fr" : "en"),
                             URLQueryItem(name: "format", value: "json")]
        return parts?.url
    }

    static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        // A dot for decimals whatever the Mac's region: the address is read by a server.
        let posix = Locale(identifier: "en_US_POSIX")
        parts?.queryItems = [URLQueryItem(name: "latitude", value: String(format: "%.3f", locale: posix, latitude)),
                             URLQueryItem(name: "longitude", value: String(format: "%.3f", locale: posix, longitude)),
                             URLQueryItem(name: "current", value: "weather_code,is_day,temperature_2m")]
        return parts?.url
    }

    struct Place: Equatable, Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
    }

    static func place(from data: Data?) -> Place? {
        struct Answer: Decodable { let results: [Place]? }
        guard let data, data.count <= maximumSize else { return nil }
        return (try? JSONDecoder().decode(Answer.self, from: data))?.results?.first
    }

    static func weather(from data: Data?) -> Weather? {
        struct Current: Decodable {
            let weather_code: Int
            let is_day: Int?
            let temperature_2m: Double?
        }
        struct Answer: Decodable { let current: Current }
        guard let data, data.count <= maximumSize,
              let current = (try? JSONDecoder().decode(Answer.self, from: data))?.current else { return nil }
        return Weather(sky: sky(code: current.weather_code), isDay: (current.is_day ?? 1) != 0,
                       celsius: current.temperature_2m)
    }

    /// Rain has just begun: worth a word.
    static func startsRaining(from previous: Weather?, to current: Weather?) -> Bool {
        current?.wet == true && previous?.wet != true && previous != nil
    }
}
