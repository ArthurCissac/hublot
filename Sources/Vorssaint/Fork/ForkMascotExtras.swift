// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine
import QuartzCore
import SwiftUI

/// The companion's extras (see `ForkMascotExtrasLogic`): rare bubbles, a
/// mini keyboard while the user types fast, and the weather of a city.
/// Each listens only while its switch is on.

// MARK: - Bubbles

/// What the companion has to say, handed to it with a reaction so it is out
/// to say it; one bubble every ten minutes at most.
enum ForkMascotChat {
    typealias Logic = ForkMascotExtrasLogic

    private static var last: TimeInterval?
    private static var pending: (bubble: Logic.Bubble, until: TimeInterval)?

    static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        NotchMascotSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.forkMascotBubbles)
    }

    /// It reacts, and says `bubble` as it does if it may speak now.
    static func say(_ bubble: Logic.Bubble, reaction: NotchMascotReaction) {
        let now = CACurrentMediaTime()
        if isOn(), Logic.canSpeak(now: now, last: last) {
            pending = (bubble, now + 15)
            last = now
        }
        NotchService.shared.reactMascot(reaction)
    }

    /// The words waiting for the reaction that has just begun, once.
    static func take() -> String? {
        guard let pending, CACurrentMediaTime() < pending.until else { return nil }
        self.pending = nil
        return pending.bubble.text(french: L10n.shared.language == .fr)
    }
}

// MARK: - Typing

/// Counts key presses while the user types, never which keys: only the
/// moment each one came. Listening only (a global monitor), and only
/// while the switch is on.
final class ForkMascotTyping {
    typealias Logic = ForkMascotExtrasLogic

    static let shared = ForkMascotTyping()
    static let changed = Notification.Name("ForkMascotTypingChanged")

    private(set) var fast = false
    private var times: [TimeInterval] = []
    private var monitor: Any?
    private var check: Timer?
    private var preferences: AnyCancellable?

    static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        NotchMascotSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.forkMascotTyping)
    }

    func start() {
        guard preferences == nil else { return }
        preferences = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    private func sync() {
        let on = Self.isOn()
        if on, monitor == nil {
            // The event itself is not read: only that a key went down.
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                DispatchQueue.main.async { self?.pressed() }
            }
        } else if !on, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            times = []
            check?.invalidate(); check = nil
            set(false)
        }
    }

    private func pressed() {
        let now = CACurrentMediaTime()
        times = Logic.trimmed(times + [now], now: now)
        if !fast, Logic.typesFast(times, now: now) {
            set(true)
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.recheck() }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            check = timer
        }
    }

    private func recheck() {
        let now = CACurrentMediaTime()
        times = Logic.trimmed(times, now: now)
        guard let last = times.last, now - last <= Logic.typingPause else {
            check?.invalidate(); check = nil
            set(false)
            return
        }
    }

    private func set(_ value: Bool) {
        guard value != fast else { return }
        fast = value
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

// MARK: - Weather

/// The weather where the user is, from Open-Meteo (free, no account): the
/// city typed in Settings is looked up once, then the sky once an hour.
/// Nothing is asked while the switch is off or no city is set.
final class ForkMascotWeather: ObservableObject {
    typealias Logic = ForkMascotExtrasLogic

    static let shared = ForkMascotWeather()

    @Published private(set) var current: Logic.Weather?
    /// The place found for the city, as shown in Settings.
    @Published private(set) var placeName: String?
    @Published private(set) var notFound = false

    private var place: Logic.Place?
    private var placeCity: String?
    private var lastFetch: Date?
    private var fetching = false
    private var timer: Timer?
    private var preferences: AnyCancellable?
    private var wake: NSObjectProtocol?

    static var city: String? {
        Logic.cleanCity(UserDefaults.standard.string(forKey: DefaultsKey.forkMascotWeatherCity) ?? "")
    }

    static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        NotchMascotSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.forkMascotWeather) && city != nil
    }

    func start() {
        guard preferences == nil else { return }
        preferences = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
        wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                                 queue: .main) { [weak self] _ in self?.refreshIfDue() }
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    private func sync() {
        guard Self.isOn() else {
            timer?.invalidate(); timer = nil
            if current != nil { set(nil) }
            return
        }
        if placeCity != Self.city {
            place = nil
            placeName = nil
            notFound = false
            lastFetch = nil
        }
        if timer == nil {
            let timer = Timer(timeInterval: 600, repeats: true) { [weak self] _ in self?.refreshIfDue() }
            timer.tolerance = 60
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        refreshIfDue()
    }

    private func refreshIfDue() {
        guard Self.isOn(), !fetching, Logic.refreshDue(last: lastFetch, now: Date()) else { return }
        fetching = true
        if let place { return forecast(place) }
        guard let city = Self.city, let url = Logic.geocodingURL(city: city, french: L10n.shared.language == .fr) else {
            fetching = false
            return
        }
        _ = ForkSpotifyHTTP.send(URLRequest(url: url, timeoutInterval: 10), maximumBytes: Logic.maximumSize) { [weak self] status, data in
            guard let self else { return }
            guard (200...299).contains(status ?? 0), let found = Logic.place(from: data) else {
                self.fetching = false
                // A city that does not exist is said once, then not asked again until it changes.
                if (200...299).contains(status ?? 0) {
                    self.notFound = true
                    self.lastFetch = Date()
                    self.placeCity = city
                }
                return
            }
            self.place = found
            self.placeCity = city
            self.notFound = false
            self.placeName = [found.name, found.country].compactMap { $0 }.joined(separator: ", ")
            self.forecast(found)
        }
    }

    private func forecast(_ place: Logic.Place) {
        guard let url = Logic.forecastURL(latitude: place.latitude, longitude: place.longitude) else {
            fetching = false
            return
        }
        _ = ForkSpotifyHTTP.send(URLRequest(url: url, timeoutInterval: 10), maximumBytes: Logic.maximumSize) { [weak self] status, data in
            guard let self else { return }
            self.fetching = false
            guard (200...299).contains(status ?? 0), let weather = Logic.weather(from: data) else { return }
            self.lastFetch = Date()
            self.set(weather)
        }
    }

    private func set(_ weather: Logic.Weather?) {
        let previous = current
        guard weather != previous else { return }
        current = weather
        ForkMascotDay.shared.weatherChanged(from: previous, to: weather)
    }
}

// MARK: - Drawn on the companion

/// One per companion: the bubble beside it and the mini keyboard in front.
final class ForkMascotChatter {
    private weak var rig: NotchMascotRig?
    private weak var hopper: CALayer?
    private let layer = CALayer()
    private var size: CGFloat = 0
    private var scale: CGFloat = 2
    private var keyboard: CALayer?
    private var observer: NSObjectProtocol?

    func connect(rig: NotchMascotRig, hopper: CALayer, above decor: CALayer) {
        self.rig = rig
        self.hopper = hopper
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "sublayers": NSNull()]
        layer.masksToBounds = false
        decor.addSublayer(layer)
        ForkMascotTyping.shared.start()
        ForkMascotWeather.shared.start()
        observer = NotificationCenter.default.addObserver(forName: ForkMascotTyping.changed, object: nil, queue: .main) { [weak self] _ in
            self?.typingChanged()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func configure(size: CGFloat, scale: CGFloat) {
        self.size = size
        self.scale = scale
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.contentsScale = scale
        keyboard?.removeFromSuperlayer(); keyboard = nil
        typingChanged()
    }

    /// A reaction began: words waiting for it come out in a bubble.
    func reacted(_ reaction: NotchMascotReaction) {
        guard size > 0, let words = ForkMascotChat.take() else { return }
        say(words)
    }

    private func say(_ words: String) {
        let s = size
        let font = NSFont.systemFont(ofSize: max(7, s * 0.42), weight: .semibold)
        let width = ceil((words as NSString).size(withAttributes: [.font: font]).width) + s * 0.5
        let height = font.pointSize + s * 0.32
        let outward: CGFloat = NotchMascotSupport.side() == .left ? -1 : 1
        let bubble = CALayer()
        bubble.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        bubble.anchorPoint = CGPoint(x: outward < 0 ? 1 : 0, y: 0.5)
        bubble.position = CGPoint(x: outward < 0 ? -s * 0.08 : s * 1.08, y: s * 0.38)
        bubble.backgroundColor = NSColor.white.withAlphaComponent(0.94).cgColor
        bubble.cornerRadius = height / 2
        bubble.actions = ["position": NSNull(), "opacity": NSNull(), "transform": NSNull()]
        let text = CATextLayer()
        text.string = NSAttributedString(string: words, attributes: [.font: font, .foregroundColor: NSColor.black])
        text.alignmentMode = .center
        text.contentsScale = scale
        text.frame = CGRect(x: 0, y: (height - font.pointSize * 1.25) / 2, width: width, height: font.pointSize * 1.25)
        text.actions = ["contents": NSNull(), "position": NSNull()]
        bubble.addSublayer(text)
        layer.addSublayer(bubble)
        let duration = ForkMascotExtrasLogic.bubbleDuration
        let moving = rig?.reduceMotion == false
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = moving ? [0.5, 1.08, 1, 1, 0.9] : [1, 1, 1, 1, 1]
        grow.keyTimes = [0, 0.08, 0.14, 0.88, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.08, 0.88, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        bubble.add(group, forKey: "forkBubble")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { bubble.removeFromSuperlayer() }
    }

    /// While the user types fast, it taps away at a little keyboard.
    private func typingChanged() {
        let typing = ForkMascotTyping.shared.fast && ForkMascotTyping.isOn()
        guard size > 0, typing != (keyboard != nil) else { return }
        guard typing else {
            keyboard?.removeFromSuperlayer(); keyboard = nil
            hopper?.removeAnimation(forKey: "forkTyping")
            return
        }
        let s = size
        let board = CALayer()
        board.frame = CGRect(x: s * 0.16, y: s * 0.78, width: s * 0.68, height: s * 0.2)
        board.backgroundColor = CGColor(red: 0.2, green: 0.21, blue: 0.24, alpha: 1)
        board.cornerRadius = s * 0.04
        board.borderColor = CGColor(gray: 0.55, alpha: 1)
        board.borderWidth = max(0.4, s * 0.02)
        board.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull()]
        let moving = rig?.reduceMotion == false
        let columns = 5, rows = 2
        let keyWidth = board.bounds.width / CGFloat(columns + 1), keyHeight = board.bounds.height / CGFloat(rows + 1)
        for row in 0..<rows {
            for column in 0..<columns {
                let key = CALayer()
                key.frame = CGRect(x: keyWidth * (CGFloat(column) + 0.6), y: keyHeight * (CGFloat(row) + 0.55),
                                   width: keyWidth * 0.75, height: keyHeight * 0.7)
                key.backgroundColor = CGColor(gray: 0.85, alpha: 1)
                key.cornerRadius = keyWidth * 0.15
                key.actions = ["opacity": NSNull()]
                if moving {
                    // Keys light up here and there as it types.
                    let blink = CAKeyframeAnimation(keyPath: "opacity")
                    blink.values = [1, 0.35, 1]
                    blink.duration = 0.32 + Double((row * columns + column) % 3) * 0.07
                    blink.timeOffset = Double((column * 7 + row * 3) % 5) * 0.06
                    blink.repeatCount = .infinity
                    key.add(blink, forKey: "forkKey")
                }
                board.addSublayer(key)
            }
        }
        layer.addSublayer(board)
        keyboard = board
        if moving {
            let tap = CAKeyframeAnimation(keyPath: "position.y")
            tap.values = [0, s * 0.035, 0]
            tap.isAdditive = true
            tap.duration = 0.22
            tap.repeatCount = .infinity
            hopper?.add(tap, forKey: "forkTyping")
        }
    }
}

// MARK: - Settings

/// Under the companion's settings: bubbles, typing and weather.
struct ForkMascotExtrasRows: View {
    @AppStorage(DefaultsKey.forkMascotBubbles) private var bubbles = true
    @AppStorage(DefaultsKey.forkMascotTyping) private var typing = true
    @AppStorage(DefaultsKey.forkMascotWeather) private var weather = true
    @AppStorage(DefaultsKey.forkMascotWeatherCity) private var city = ""
    @ObservedObject private var forecast = ForkMascotWeather.shared
    @State private var draft = ""

    var body: some View {
        let text = ForkMascotStrings.current
        ForkOptionRow(symbol: "bubble.left", title: text.bubbles, caption: text.bubblesCaption) {
            Toggle(text.bubbles, isOn: $bubbles).labelsHidden().toggleStyle(.switch)
        }
        ForkOptionRow(symbol: "keyboard", title: text.typing, caption: text.typingCaption) {
            Toggle(text.typing, isOn: $typing).labelsHidden().toggleStyle(.switch)
        }
        ForkOptionRow(symbol: "cloud.sun", title: text.weather, caption: weatherCaption(text)) {
            Toggle(text.weather, isOn: $weather).labelsHidden().toggleStyle(.switch)
        }
        if weather {
            HStack(spacing: 8) {
                TextField(text.city, text: $draft, prompt: Text(text.cityPrompt))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit { city = draft }
                Button(text.save) { city = draft }
                    .disabled(draft.trimmingCharacters(in: .whitespaces) == city)
            }
            .padding(.leading, settingsRowTextInset)
            .onAppear { draft = city }
        }
    }

    private func weatherCaption(_ text: ForkMascotStrings) -> String {
        if forecast.notFound { return text.cityNotFound }
        if let name = forecast.placeName { return text.weatherFor(name) }
        return text.weatherCaption
    }
}
