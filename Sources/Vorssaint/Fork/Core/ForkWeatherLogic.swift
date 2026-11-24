// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The island's Weather page (`forkWeatherEnabled`): the user's own city
/// (the companion's) first, then up to six more, each with its sky, its
/// temperature, today's range, the next rain, and on a click the coming
/// hours and days. From Open-Meteo, free and without an account; asked only
/// while the page is open. Pure: addresses, answers, cities and words.
enum ForkWeatherLogic {
    static let maximumSize = 1 << 19
    static let maximumCities = 6
    /// Opening the page asks again after this long; open, every half hour.
    static let freshFor: TimeInterval = 600
    static let refreshWhileOpen: TimeInterval = 1800

    // MARK: - Cities

    struct City: Codable, Equatable, Identifiable {
        var name: String
        var region: String?
        var country: String?
        var latitude: Double
        var longitude: Double

        var id: String { String(format: "%.3f,%.3f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude) }

        /// « Lyon, Auvergne-Rhône-Alpes, France » in suggestions.
        var detail: String { [region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }
    }

    static func cities(from stored: String?) -> [City] {
        guard let stored, let data = stored.data(using: .utf8),
              let cities = try? JSONDecoder().decode([City].self, from: data) else { return [] }
        return Array(cities.prefix(maximumCities))
    }

    static func stored(_ cities: [City]) -> String {
        guard let data = try? JSONEncoder().encode(Array(cities.prefix(maximumCities))) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Added at the end, once, and only while there is room.
    static func adding(_ city: City, to cities: [City]) -> [City] {
        guard cities.count < maximumCities, !cities.contains(where: { $0.id == city.id }) else { return cities }
        return cities + [city]
    }

    static func removing(_ id: String, from cities: [City]) -> [City] { cities.filter { $0.id != id } }

    // MARK: - Addresses

    /// Up to five places matching what is typed, for suggestions.
    static func searchURL(_ text: String, french: Bool) -> URL? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, query.count <= 80 else { return nil }
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        parts?.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "5"),
                             URLQueryItem(name: "language", value: french ? "fr" : "en"),
                             URLQueryItem(name: "format", value: "json")]
        return parts?.url
    }

    static func places(from data: Data?) -> [City] {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let admin1: String?
            let country: String?
        }
        struct Answer: Decodable { let results: [Result]? }
        guard let data, data.count <= maximumSize,
              let results = (try? JSONDecoder().decode(Answer.self, from: data))?.results else { return [] }
        return results.prefix(5).map { City(name: $0.name, region: $0.admin1, country: $0.country,
                                            latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Now, the coming hours and the coming days, in the place's own time.
    static func forecastURL(_ city: City) -> URL? {
        guard (-90...90).contains(city.latitude), (-180...180).contains(city.longitude) else { return nil }
        let posix = Locale(identifier: "en_US_POSIX")
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        parts?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", locale: posix, city.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", locale: posix, city.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6"),
        ]
        return parts?.url
    }

    // MARK: - The forecast

    struct Hour: Equatable {
        let hour: Int
        let celsius: Double
        let code: Int
        let rain: Int
        let isDay: Bool
    }

    struct Day: Equatable {
        let date: String
        let code: Int
        let low: Double
        let high: Double
        let rain: Int
    }

    struct Forecast: Equatable {
        let celsius: Double
        let code: Int
        let isDay: Bool
        /// From the current hour on.
        let hours: [Hour]
        /// Today first.
        let days: [Day]
    }

    static func forecast(from data: Data?) -> Forecast? {
        struct Current: Decodable {
            let time: String
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int?
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]
            let weather_code: [Int?]
            let precipitation_probability: [Int?]?
            let is_day: [Int?]?
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Int?]?
        }
        struct Answer: Decodable {
            let current: Current
            let hourly: Hourly?
            let daily: Daily?
        }
        guard let data, data.count <= maximumSize,
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
        // « 2026-11-23T17:15 »: the hour this one belongs to.
        let currentHour = String(answer.current.time.prefix(13))
        var hours: [Hour] = []
        if let hourly = answer.hourly {
            let start = hourly.time.firstIndex { $0.prefix(13) >= currentHour } ?? hourly.time.count
            for index in start..<hourly.time.count where hours.count < 13 {
                guard index < hourly.temperature_2m.count, index < hourly.weather_code.count,
                      let celsius = hourly.temperature_2m[index], let code = hourly.weather_code[index],
                      let hour = Int(hourly.time[index].dropFirst(11).prefix(2)) else { continue }
                let rain = hourly.precipitation_probability.flatMap { index < $0.count ? $0[index] : nil } ?? 0
                let isDay = (hourly.is_day.flatMap { index < $0.count ? $0[index] : nil } ?? 1) != 0
                hours.append(Hour(hour: hour, celsius: celsius, code: code, rain: rain, isDay: isDay))
            }
        }
        var days: [Day] = []
        if let daily = answer.daily {
            for index in daily.time.indices where days.count < 6 {
                guard index < daily.weather_code.count, index < daily.temperature_2m_max.count,
                      index < daily.temperature_2m_min.count,
                      let code = daily.weather_code[index], let high = daily.temperature_2m_max[index],
                      let low = daily.temperature_2m_min[index] else { continue }
                let rain = daily.precipitation_probability_max.flatMap { index < $0.count ? $0[index] : nil } ?? 0
                days.append(Day(date: daily.time[index], code: code, low: low, high: high, rain: rain))
            }
        }
        return Forecast(celsius: answer.current.temperature_2m, code: answer.current.weather_code,
                        isDay: (answer.current.is_day ?? 1) != 0, hours: hours, days: days)
    }

    /// The first coming hour, within twelve, likely to bring rain.
    static func nextRain(_ forecast: Forecast) -> Int? {
        forecast.hours.prefix(12).first { $0.rain >= 50 && wet(code: $0.code) }?.hour
    }

    static func wet(code: Int) -> Bool { (51...67).contains(code) || (80...82).contains(code) || (95...99).contains(code) }

    static func refreshDue(last: Date?, now: Date, interval: TimeInterval = freshFor) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval || now < last
    }

    // MARK: - Words and symbols

    /// SF Symbols for WMO weather codes, by day or night.
    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61, 63, 80, 81: return "cloud.rain.fill"
        case 65, 66, 67, 82: return "cloud.heavyrain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func sky(code: Int, french: Bool) -> String {
        switch code {
        case 0: return french ? "Ciel dégagé" : "Clear"
        case 1, 2: return french ? "Éclaircies" : "Partly cloudy"
        case 3: return french ? "Couvert" : "Overcast"
        case 45, 48: return french ? "Brouillard" : "Fog"
        case 51...57: return french ? "Bruine" : "Drizzle"
        case 61, 63, 80, 81: return french ? "Pluie" : "Rain"
        case 65, 66, 67, 82: return french ? "Forte pluie" : "Heavy rain"
        case 71...77, 85, 86: return french ? "Neige" : "Snow"
        case 95...99: return french ? "Orage" : "Thunderstorm"
        default: return french ? "Nuageux" : "Cloudy"
        }
    }

    /// « 12° », rounded, with a true minus sign below zero.
    static func degrees(_ celsius: Double) -> String {
        let value = Int(celsius.rounded())
        return value < 0 ? "−\(-value)°" : "\(value)°"
    }

    static func hourLabel(_ hour: Int, french: Bool) -> String {
        french ? "\(hour) h" : (hour == 0 ? "12 AM" : hour < 12 ? "\(hour) AM" : hour == 12 ? "12 PM" : "\(hour - 12) PM")
    }

    /// « Aujourd'hui », then short weekday names, from « 2026-11-24 ».
    static func dayLabel(_ date: String, index: Int, french: Bool) -> String {
        if index == 0 { return french ? "Aujourd’hui" : "Today" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: french ? "fr_FR" : "en_US")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: day).capitalized
    }

    static func title(french: Bool) -> String { french ? "Météo" : "Weather" }

    static let pageSymbol = "cloud.sun.fill"

    static func pageAvailable(in defaults: UserDefaults) -> Bool { defaults.bool(forKey: DefaultsKey.forkWeatherEnabled) }

    static func pageSummary(french: Bool) -> String {
        french ? "La météo de votre ville et d’autres villes : ciel, température, pluie, heures et jours à venir."
            : "The weather for your city and others: sky, temperature, rain, the coming hours and days."
    }
}
