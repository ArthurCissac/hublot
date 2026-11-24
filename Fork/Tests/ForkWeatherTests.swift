// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The Weather page: cities kept and limited, addresses asked, the forecast
/// read from the current hour, the next rain, and the words shown.
enum ForkWeatherTests {
    typealias Logic = ForkWeatherLogic

    private static let paris = Logic.City(name: "Paris", region: "Île-de-France", country: "France", latitude: 48.85341, longitude: 2.3488)
    private static let lyon = Logic.City(name: "Lyon", region: "Auvergne-Rhône-Alpes", country: "France", latitude: 45.74846, longitude: 4.84671)

    private static let sample = """
    {"current": {"time": "2026-11-23T17:15", "temperature_2m": 9.6, "weather_code": 3, "is_day": 0},
     "hourly": {"time": ["2026-11-23T16:00", "2026-11-23T17:00", "2026-11-23T18:00", "2026-11-23T19:00", "2026-11-23T20:00"],
                "temperature_2m": [10.1, 9.6, 9.0, null, 8.2], "weather_code": [3, 3, 61, 63, 61],
                "precipitation_probability": [10, 20, 40, 70, 80], "is_day": [1, 0, 0, 0, 0]},
     "daily": {"time": ["2026-11-23", "2026-11-24"], "weather_code": [61, 0],
               "temperature_2m_max": [11.2, 8.4], "temperature_2m_min": [6.1, -1.6], "precipitation_probability_max": [80, 5]}}
    """

    static func run(_ suite: TestSuite) {
        var cities: [Logic.City] = []
        for index in 0..<8 {
            cities = Logic.adding(Logic.City(name: "C\(index)", region: nil, country: nil, latitude: Double(index), longitude: 1), to: cities)
        }
        suite.expect(cities.count == Logic.maximumCities && Logic.adding(paris, to: [paris]).count == 1,
                     "six cities at most, each once")
        let kept = Logic.cities(from: Logic.stored([paris, lyon]))
        suite.expect(kept == [paris, lyon] && Logic.cities(from: "nonsense").isEmpty && Logic.cities(from: nil).isEmpty
            && Logic.removing(paris.id, from: kept) == [lyon],
                     "cities are stored, read back and removed")
        suite.expect(paris.id == "48.853,2.349" && paris.detail == "Île-de-France, France",
                     "a city is known by its place and shown with its region")

        let search = Logic.searchURL(" Saint-Étienne ", french: true)?.absoluteString ?? ""
        suite.expect(search.contains("name=Saint-%C3%89tienne") && search.contains("count=5")
            && Logic.searchURL("a", french: true) == nil,
                     "suggestions are asked from two letters, by name")
        let places = Logic.places(from: Data(#"{"results":[{"name":"Lyon","latitude":45.75,"longitude":4.85,"admin1":"Auvergne-Rhône-Alpes","country":"France"}]}"#.utf8))
        suite.expect(places.first?.name == "Lyon" && places.first?.region == "Auvergne-Rhône-Alpes"
            && Logic.places(from: Data("{}".utf8)).isEmpty,
                     "suggestions are read with their region")
        let forecastURL = Logic.forecastURL(paris)?.absoluteString ?? ""
        suite.expect(forecastURL.hasPrefix("https://api.open-meteo.com/v1/forecast?latitude=48.853&longitude=2.349")
            && forecastURL.contains("timezone=auto") && forecastURL.contains("forecast_days=6")
            && Logic.forecastURL(Logic.City(name: "x", region: nil, country: nil, latitude: 99, longitude: 0)) == nil,
                     "the forecast is asked at the city's place, in its own time")

        let forecast = Logic.forecast(from: Data(sample.utf8))
        suite.expect(forecast?.celsius == 9.6 && forecast?.isDay == false && forecast?.hours.first?.hour == 17
            && forecast?.hours.count == 3 && forecast?.days.count == 2 && forecast?.days.last?.low == -1.6,
                     "the forecast starts at the current hour, skipping hours with a missing value")
        suite.expect(forecast.flatMap(Logic.nextRain) == 20 && Logic.forecast(from: Data("{}".utf8)) == nil
            && Logic.forecast(from: Data(repeating: 32, count: Logic.maximumSize + 1)) == nil,
                     "the next rain is the first likely wet hour; anything else is refused")
        suite.expect(Logic.symbol(code: 0, isDay: true) == "sun.max.fill" && Logic.symbol(code: 0, isDay: false) == "moon.stars.fill"
            && Logic.symbol(code: 63, isDay: true) == "cloud.rain.fill" && Logic.symbol(code: 75, isDay: true) == "cloud.snow.fill"
            && Logic.sky(code: 95, french: true) == "Orage" && Logic.sky(code: 3, french: false) == "Overcast",
                     "each sky has its symbol and its words")
        suite.expect(Logic.degrees(9.6) == "10°" && Logic.degrees(-1.6) == "−2°" && Logic.degrees(-0.2) == "0°",
                     "temperatures are rounded, with a true minus sign")
        suite.expect(Logic.hourLabel(15, french: true) == "15 h" && Logic.hourLabel(15, french: false) == "3 PM"
            && Logic.hourLabel(0, french: false) == "12 AM",
                     "hours read the user's way")
        suite.expect(Logic.dayLabel("2026-11-23", index: 0, french: true) == "Aujourd’hui"
            && Logic.dayLabel("2026-11-24", index: 1, french: true).lowercased().hasPrefix("mar")
            && Logic.dayLabel("2026-11-24", index: 1, french: false) == "Tue",
                     "today, then short weekday names")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        suite.expect(Logic.refreshDue(last: nil, now: now) && !Logic.refreshDue(last: now.addingTimeInterval(-300), now: now)
            && Logic.refreshDue(last: now.addingTimeInterval(-601), now: now),
                     "opening the page asks again after ten minutes")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkWeatherEnabled] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkWeatherCities] as? String == "[]",
                     "the page is there by default, with no city of its own")
    }
}
