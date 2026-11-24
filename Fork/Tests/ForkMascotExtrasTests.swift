// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The companion's extras: short and rare bubbles, fast typing told from
/// the rhythm alone, and the weather asked for and read.
enum ForkMascotExtrasTests {
    typealias Logic = ForkMascotExtrasLogic

    static func run(_ suite: TestSuite) {
        let bubbles: [Logic.Bubble] = [.hello, .bravo, .done, .pause, .late(3), .late(250), .bedtime, .rain]
        suite.expect(bubbles.allSatisfy { $0.text(french: true).count <= Logic.maximumBubbleLength
            && $0.text(french: false).count <= Logic.maximumBubbleLength && !$0.text(french: true).isEmpty },
                     "every bubble fits in ten characters, in French and English")
        suite.expect(Logic.Bubble.late(3).text(french: true) == "3 tâches" && Logic.Bubble.late(250).text(french: true) == "99 tâches",
                     "late tasks are counted, up to 99")
        suite.expect(Logic.canSpeak(now: 100, last: nil) && !Logic.canSpeak(now: 699, last: 100) && Logic.canSpeak(now: 700, last: 100),
                     "one bubble every ten minutes at most")

        let steady = stride(from: 0.0, to: 5.0, by: 0.25).map { 1000 + $0 }
        suite.expect(Logic.typesFast(steady, now: 1004.9) && !Logic.typesFast(Array(steady.prefix(8)), now: 1002)
            && !Logic.typesFast(steady, now: 1007) && !Logic.typesFast(stride(from: 0.0, to: 5.0, by: 0.5).map { 1000 + $0 }, now: 1004.6),
                     "fast is four keys a second kept up five seconds; it stops a moment after the last key")
        suite.expect(Logic.trimmed([1, 2, 996, 999], now: 1000) == [996, 999],
                     "only the last five seconds of key times are kept")

        suite.expect(Logic.sky(code: 0) == .clear && Logic.sky(code: 3) == .cloudy && Logic.sky(code: 61) == .rain
            && Logic.sky(code: 81) == .rain && Logic.sky(code: 73) == .snow && Logic.sky(code: 95) == .storm,
                     "the weather codes read as clear, cloudy, rain, snow or storm")
        let url = Logic.geocodingURL(city: " Saint-Étienne ", french: true)?.absoluteString ?? ""
        suite.expect(url.hasPrefix("https://geocoding-api.open-meteo.com/v1/search?") && url.contains("name=Saint-%C3%89tienne")
            && url.contains("language=fr") && Logic.geocodingURL(city: "  ", french: true) == nil
            && Logic.geocodingURL(city: String(repeating: "a", count: 81), french: false) == nil,
                     "the city is looked up by its name, cleaned and encoded")
        suite.expect(Logic.forecastURL(latitude: 48.8566, longitude: 2.3522)?.absoluteString
            == "https://api.open-meteo.com/v1/forecast?latitude=48.857&longitude=2.352&current=weather_code,is_day,temperature_2m"
            && Logic.forecastURL(latitude: 120, longitude: 0) == nil,
                     "the sky is asked for at the place found, rounded")
        let place = Logic.place(from: Data(#"{"results":[{"name":"Paris","latitude":48.85,"longitude":2.35,"country":"France"}]}"#.utf8))
        suite.expect(place?.name == "Paris" && place?.country == "France" && Logic.place(from: Data(#"{"generationtime_ms":1}"#.utf8)) == nil,
                     "a found place is read; no result is no place")
        let rain = Logic.weather(from: Data(#"{"current":{"weather_code":63,"is_day":1,"temperature_2m":9.5}}"#.utf8))
        let night = Logic.weather(from: Data(#"{"current":{"weather_code":0,"is_day":0}}"#.utf8))
        suite.expect(rain?.wet == true && rain?.celsius == 9.5 && night?.sunny == false && night?.sky == .clear
            && Logic.weather(from: Data("{}".utf8)) == nil && Logic.weather(from: Data(repeating: 32, count: Logic.maximumSize + 1)) == nil,
                     "the current sky is read; clear at night is not sunny")
        suite.expect(Logic.startsRaining(from: night, to: rain) && !Logic.startsRaining(from: rain, to: rain)
            && !Logic.startsRaining(from: nil, to: rain),
                     "a word when rain begins, not at the first look")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        suite.expect(Logic.refreshDue(last: nil, now: now) && !Logic.refreshDue(last: now.addingTimeInterval(-1800), now: now)
            && Logic.refreshDue(last: now.addingTimeInterval(-3600), now: now),
                     "the weather is looked up once an hour")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 15)) ?? now
        let sunny = Logic.Weather(sky: .clear, isDay: true, celsius: 14)
        let wet = Logic.Weather(sky: .rain, isDay: true, celsius: 8)
        suite.expect(ForkMascotDayLogic.outfit(at: afternoon, focused: false, weather: wet, calendar: calendar).extras == [.umbrella]
            && ForkMascotDayLogic.outfit(at: afternoon, focused: false, weather: sunny, calendar: calendar).extras == [.sunglasses]
            && ForkMascotDayLogic.outfit(at: afternoon, focused: false, weather: nil, calendar: calendar).extras.isEmpty,
                     "an umbrella in the rain, sunglasses in the sun")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkMascotBubbles] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkMascotTyping] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkMascotWeatherCity] as? String == "",
                     "bubbles and typing on by default; no city until one is typed")
    }
}
