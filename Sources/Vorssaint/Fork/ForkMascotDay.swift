// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import Combine
import QuartzCore
import SwiftUI

/// The companion follows the day (see `ForkMascotDayLogic`). Nothing ticks:
/// one timer waits for the next hour that matters, and the background sound,
/// the island's timer and Todoist are listened to only while this is on.
final class ForkMascotDay {
    typealias Logic = ForkMascotDayLogic

    static let shared = ForkMascotDay()
    /// Posted on the main queue when what it wears may have changed.
    static let changed = Notification.Name("ForkMascotDayChanged")

    private var started = false
    private var preferences: AnyCancellable?
    private var listeners: Set<AnyCancellable> = []
    private var clock: Timer?
    private var clockObservers: [NSObjectProtocol] = []
    private var listening = false
    private(set) var focus: Logic.Focus = .none
    private var partyUntil: CFTimeInterval = 0

    static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        NotchMascotSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.forkMascotDay)
    }

    /// From the first companion drawn; does nothing more after.
    func start() {
        guard !started else { return }
        started = true
        preferences = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
        // Asked first while the island draws: tell it nothing until that is done.
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    /// Listens while on; stops everything when switched off.
    private func sync() {
        let on = Self.isOn()
        guard on != listening else { return }
        listening = on
        if on {
            listen()
        } else {
            listeners.removeAll()
            clock?.invalidate(); clock = nil
            clockObservers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
            clockObservers = []
            focus = .none
        }
        announce()
    }

    private func listen() {
        let sound = ForkAmbientPlayer.shared
        // A @Published value is sent before it is stored: read what is sent.
        sound.$playing.combineLatest(sound.$phase, NotchTimerService.shared.$session)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing, phase, session in
                self?.focusChanged(Logic.focus(soundPlaying: playing, soundPhase: phase,
                                               timerRunning: session.isRunning && !session.isPaused,
                                               timerPhase: session.phase))
            }
            .store(in: &listeners)
        ForkTodoist.shared.$tasks
            .map { Logic.overdueCount($0, today: ForkTodoistLogic.dayString(Date())) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { _ in NotchService.shared.objectWillChange.send() }
            .store(in: &listeners)
        clockObservers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.hourChanged()
        })
        clockObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.hourChanged()
        })
        scheduleClock()
        // Once the island has settled after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.dayWords() }
    }

    private func scheduleClock() {
        clock?.invalidate()
        let timer = Timer(fire: Logic.nextChange(after: Date()), interval: 0, repeats: false) { [weak self] _ in
            self?.hourChanged()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private func hourChanged() {
        guard listening else { return }
        scheduleClock()
        announce()
        dayWords()
    }

    private func focusChanged(_ now: Logic.Focus) {
        let previous = focus
        guard now != previous else { return }
        focus = now
        announce()
        if Logic.startsBreak(from: previous, to: now) {
            ForkMascotChat.say(.pause, reaction: .wakeUp)
        }
    }

    /// What it wears changes, and so may its face at rest.
    private func announce() {
        NotificationCenter.default.post(name: Self.changed, object: nil)
        NotchService.shared.objectWillChange.send()
    }

    // MARK: What the companion asks

    var outfit: Logic.Outfit {
        guard Self.isOn() else { return .none }
        return Logic.outfit(at: Date(), focused: focus == .working, weather: ForkMascotWeather.shared.current)
    }

    /// The weather changed where the user is: an umbrella or sunglasses,
    /// and a word when rain begins.
    func weatherChanged(from previous: ForkMascotExtrasLogic.Weather?, to current: ForkMascotExtrasLogic.Weather?) {
        announce()
        if Self.isOn(), ForkMascotChat.isOn(), ForkMascotExtrasLogic.startsRaining(from: previous, to: current) {
            ForkMascotChat.say(.rain, reaction: .perk)
        }
    }

    private var lateSaid: String?
    private var bedtimeSaid: String?

    /// A word for the day's moments: hello in the morning (once a day),
    /// late tasks in the evening, bedtime late at night.
    private func dayWords(now: Date = Date()) {
        guard listening, ForkMascotChat.isOn() else { return }
        let defaults = UserDefaults.standard
        let today = ForkTodoistLogic.dayString(now)
        let hour = Calendar.current.component(.hour, from: now)
        if (6..<12).contains(hour), defaults.string(forKey: DefaultsKey.forkMascotGreetedDay) != today {
            defaults.set(today, forKey: DefaultsKey.forkMascotGreetedDay)
            return ForkMascotChat.say(.hello, reaction: .perk)
        }
        if hour >= Logic.sleepFrom, bedtimeSaid != today {
            bedtimeSaid = today
            return ForkMascotChat.say(.bedtime, reaction: .yawn)
        }
        let overdue = Logic.overdueCount(ForkTodoist.shared.tasks, today: today)
        if Logic.worries(at: now, overdue: overdue), lateSaid != today {
            lateSaid = today
            ForkMascotChat.say(.late(overdue), reaction: .confused)
        }
    }

    /// Its face at rest: asleep late at night, worried in the evening about
    /// late tasks.
    static func restingMood(base: NotchMascotMood) -> NotchMascotMood {
        guard isOn() else { return base }
        shared.start()
        let overdue = Logic.overdueCount(ForkTodoist.shared.tasks, today: ForkTodoistLogic.dayString(Date()))
        return Logic.restingMood(base: base, at: Date(), overdue: overdue)
    }

    // MARK: Todoist

    /// A task was ticked off in Hublot: it cheers, and throws confetti when
    /// that was the day's last.
    func taskCompleted(remaining: Int) {
        guard Self.isOn() else { return }
        let party = Logic.cheer(remaining: remaining) == .party
        if party { partyUntil = CACurrentMediaTime() + 20 }
        ForkMascotChat.say(party ? .done : .bravo, reaction: .celebrate)
    }

    /// Whether this cheer is the day's last task: once only.
    func takesParty() -> Bool {
        guard CACurrentMediaTime() < partyUntil else { return false }
        partyUntil = 0
        return true
    }
}

// MARK: - What it wears, drawn

/// The props of the day on the companion's body: small shapes drawn by
/// Hublot at its size (12 to 20 points), redrawn only when they change.
final class ForkMascotWardrobe {
    typealias Logic = ForkMascotDayLogic

    private weak var rig: NotchMascotRig?
    private let wear = CALayer()
    private var size: CGFloat = 0
    private var scale: CGFloat = 2
    private var shown: (Logic.Outfit, NotchMascotLook, NotchMascotSide, CGFloat)?
    private var observer: NSObjectProtocol?

    func connect(rig: NotchMascotRig, under decor: CALayer) {
        self.rig = rig
        wear.actions = ["position": NSNull(), "bounds": NSNull(), "sublayers": NSNull(), "contents": NSNull()]
        wear.masksToBounds = false
        decor.insertSublayer(wear, at: 0)
        ForkMascotDay.shared.start()
        observer = NotificationCenter.default.addObserver(forName: ForkMascotDay.changed, object: nil, queue: .main) { [weak self] _ in
            self?.dress()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func configure(size: CGFloat, scale: CGFloat) {
        self.size = size
        self.scale = scale
        wear.frame = CGRect(x: 0, y: 0, width: size, height: size)
        wear.contentsScale = scale
        dress()
    }

    /// Puts on what the day calls for, if that changed.
    func dress() {
        guard size > 0, let rig else { return }
        let outfit = ForkMascotDay.shared.outfit
        let side = NotchMascotSupport.side()
        if let shown, shown.0 == outfit, shown.1 == rig.look, shown.2 == side, shown.3 == size { return }
        shown = (outfit, rig.look, side, size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wear.sublayers?.forEach { $0.removeFromSuperlayer() }
        for layer in Self.layers(for: outfit, size: size, look: rig.look, outward: side == .left ? -1 : 1,
                                 scale: scale, moving: !rig.reduceMotion) {
            wear.addSublayer(layer)
        }
        CATransaction.commit()
    }

    /// The day's last task: a burst of confetti over it.
    func celebrate() {
        guard size > 0, let rig, !rig.reduceMotion else { return }
        let s = size
        let colors: [NSColor] = [.systemPink, .systemYellow, .systemTeal, .systemOrange, .systemPurple, .systemGreen]
        for index in 0..<10 {
            let bit = CALayer()
            let side = s * (index.isMultiple(of: 3) ? 0.12 : 0.09)
            bit.bounds = CGRect(x: 0, y: 0, width: side, height: side * 0.6)
            bit.backgroundColor = colors[index % colors.count].cgColor
            bit.cornerRadius = side * 0.15
            bit.position = CGPoint(x: s * 0.5, y: s * 0.1)
            bit.opacity = 0
            bit.actions = ["position": NSNull(), "opacity": NSNull(), "transform": NSNull()]
            let angle = Double(index) / 10 * 2 * Double.pi
            let reach = s * (0.6 + 0.25 * CGFloat(index % 3))
            let out = CGPoint(x: s * 0.5 + CGFloat(cos(angle)) * reach, y: s * 0.1 - CGFloat(abs(sin(angle))) * reach * 0.6)
            let fall = CGPoint(x: out.x + CGFloat(cos(angle)) * s * 0.2, y: s * 1.1)
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = [bit.position, out, fall].map { NSValue(point: $0) }
            move.keyTimes = [0, 0.35, 1]
            move.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.toValue = (index.isMultiple(of: 2) ? 1 : -1) * Double.pi * 3
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.08, 0.75, 1]
            let group = CAAnimationGroup()
            group.animations = [move, spin, fade]
            group.duration = 1.7
            group.beginTime = CACurrentMediaTime() + Double(index % 4) * 0.05
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            bit.add(group, forKey: "forkConfetti")
            wear.addSublayer(bit)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { bit.removeFromSuperlayer() }
        }
    }

    // MARK: Drawing

    /// The props for `outfit`, in the companion's own square (y downward).
    /// `outward` is the side away from the camera: -1 left, 1 right.
    static func layers(for outfit: Logic.Outfit, size s: CGFloat, look: NotchMascotLook, outward: CGFloat,
                       scale: CGFloat, moving: Bool) -> [CALayer] {
        var layers: [CALayer] = []
        // On the ground first, so the body's props stay in front.
        if outfit.extras.contains(.pumpkin) { layers += pumpkin(s, outward: outward, scale: scale) }
        if outfit.extras.contains(.sunglasses) { layers += sunglasses(s, face: look.face, scale: scale) }
        switch outfit.head {
        case .partyHat?: layers += partyHat(s, outward: outward, scale: scale)
        case .headset?: layers += headset(s, scale: scale)
        case .nightcap?: layers += nightcap(s, outward: outward, scale: scale, moving: moving)
        case .beanie?: layers += beanie(s, scale: scale)
        case nil: break
        }
        if outfit.extras.contains(.coffee) { layers += coffee(s, outward: outward, scale: scale, moving: moving) }
        if outfit.extras.contains(.umbrella) { layers += umbrella(s, outward: outward, scale: scale) }
        return layers
    }

    private static func shape(_ path: CGPath, fill: NSColor?, stroke: NSColor? = nil, line: CGFloat = 0,
                              scale: CGFloat) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = fill?.cgColor
        layer.strokeColor = stroke?.cgColor
        layer.lineWidth = line
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.contentsScale = scale
        layer.actions = ["path": NSNull(), "position": NSNull(), "opacity": NSNull()]
        return layer
    }

    private static func dot(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func outline(_ s: CGFloat) -> CGFloat { max(0.5, s * 0.035) }

    /// Drawn leaning right; mirrored to lean away from the camera.
    private static func lean(_ path: CGPath, _ s: CGFloat, outward: CGFloat) -> CGPath {
        guard outward < 0 else { return path }
        var mirror = CGAffineTransform(translationX: s, y: 0).scaledBy(x: -1, y: 1)
        return path.copy(using: &mirror) ?? path
    }

    /// A soft cap flopping to one side, a white band and a pompom.
    private static func nightcap(_ s: CGFloat, outward: CGFloat, scale: CGFloat, moving: Bool) -> [CALayer] {
        let cap = CGMutablePath()
        cap.move(to: CGPoint(x: s * 0.18, y: s * 0.3))
        cap.addCurve(to: CGPoint(x: s * 1.02, y: s * 0.08), control1: CGPoint(x: s * 0.22, y: -s * 0.12),
                     control2: CGPoint(x: s * 0.78, y: -s * 0.2))
        cap.addCurve(to: CGPoint(x: s * 0.82, y: s * 0.3), control1: CGPoint(x: s * 0.86, y: s * 0.02),
                     control2: CGPoint(x: s * 0.8, y: s * 0.14))
        cap.closeSubpath()
        let blue = rgb(0.33, 0.42, 0.86)
        let band = CGPath(roundedRect: CGRect(x: s * 0.15, y: s * 0.22, width: s * 0.7, height: s * 0.11),
                          cornerWidth: s * 0.05, cornerHeight: s * 0.05, transform: nil)
        let pompom = shape(dot(.zero, s * 0.085), fill: .white, scale: scale)
        pompom.position = CGPoint(x: s * (0.5 + 0.53 * (outward < 0 ? -1 : 1)), y: s * 0.1)
        if moving {
            // It sways a little, as a pompom on a soft cap does.
            let sway = CAKeyframeAnimation(keyPath: "position.y")
            sway.values = [0, s * 0.03, 0]
            sway.isAdditive = true
            sway.duration = 3.2
            sway.repeatCount = .infinity
            sway.calculationMode = .cubic
            pompom.add(sway, forKey: "forkSway")
        }
        return [shape(lean(cap, s, outward: outward), fill: blue, stroke: rgb(0.2, 0.27, 0.6), line: outline(s), scale: scale),
                shape(band, fill: rgb(0.97, 0.97, 1), scale: scale), pompom]
    }

    /// A knitted beanie over the top of its head.
    private static func beanie(_ s: CGFloat, scale: CGFloat) -> [CALayer] {
        let dome = CGMutablePath()
        dome.move(to: CGPoint(x: s * 0.17, y: s * 0.3))
        dome.addCurve(to: CGPoint(x: s * 0.83, y: s * 0.3), control1: CGPoint(x: s * 0.17, y: -s * 0.07),
                      control2: CGPoint(x: s * 0.83, y: -s * 0.07))
        dome.closeSubpath()
        let red = rgb(0.86, 0.22, 0.27)
        let band = CGPath(roundedRect: CGRect(x: s * 0.13, y: s * 0.23, width: s * 0.74, height: s * 0.12),
                          cornerWidth: s * 0.05, cornerHeight: s * 0.05, transform: nil)
        let ribs = CGMutablePath()
        for x in [0.3, 0.42, 0.58, 0.7] {
            ribs.move(to: CGPoint(x: s * CGFloat(x), y: s * 0.25))
            ribs.addLine(to: CGPoint(x: s * CGFloat(x), y: s * 0.33))
        }
        return [shape(dome, fill: red, stroke: rgb(0.6, 0.12, 0.16), line: outline(s), scale: scale),
                shape(band, fill: rgb(0.96, 0.93, 0.9), scale: scale),
                shape(ribs, fill: nil, stroke: rgb(0.82, 0.76, 0.72), line: max(0.4, s * 0.025), scale: scale),
                shape(dot(CGPoint(x: s * 0.5, y: s * 0.01), s * 0.09), fill: rgb(0.96, 0.93, 0.9), scale: scale)]
    }

    /// A paper cone, a little tilted, with a pompom.
    private static func partyHat(_ s: CGFloat, outward: CGFloat, scale: CGFloat) -> [CALayer] {
        let cone = CGMutablePath()
        cone.move(to: CGPoint(x: s * 0.34, y: s * 0.27))
        cone.addLine(to: CGPoint(x: s * 0.58, y: -s * 0.16))
        cone.addLine(to: CGPoint(x: s * 0.72, y: s * 0.25))
        cone.addQuadCurve(to: CGPoint(x: s * 0.34, y: s * 0.27), control: CGPoint(x: s * 0.53, y: s * 0.32))
        cone.closeSubpath()
        let stripes = CGMutablePath()
        stripes.move(to: CGPoint(x: s * 0.43, y: s * 0.12)); stripes.addLine(to: CGPoint(x: s * 0.67, y: s * 0.08))
        stripes.move(to: CGPoint(x: s * 0.5, y: -s * 0.01)); stripes.addLine(to: CGPoint(x: s * 0.63, y: -s * 0.04))
        return [shape(lean(cone, s, outward: outward), fill: rgb(1, 0.78, 0.18), stroke: rgb(0.78, 0.55, 0.05), line: outline(s), scale: scale),
                shape(lean(stripes, s, outward: outward), fill: nil, stroke: rgb(0.95, 0.3, 0.55), line: max(0.5, s * 0.05), scale: scale),
                shape(lean(dot(CGPoint(x: s * 0.58, y: -s * 0.17), s * 0.075), s, outward: outward), fill: rgb(0.95, 0.3, 0.55), scale: scale)]
    }

    /// A band over its head and a cup on each side.
    private static func headset(_ s: CGFloat, scale: CGFloat) -> [CALayer] {
        let band = CGMutablePath()
        band.move(to: CGPoint(x: s * 0.1, y: s * 0.5))
        band.addCurve(to: CGPoint(x: s * 0.9, y: s * 0.5), control1: CGPoint(x: s * 0.06, y: -s * 0.08),
                      control2: CGPoint(x: s * 0.94, y: -s * 0.08))
        let cups = CGMutablePath()
        for x in [-0.02, 0.86] {
            cups.addRoundedRect(in: CGRect(x: s * CGFloat(x), y: s * 0.4, width: s * 0.16, height: s * 0.3),
                                cornerWidth: s * 0.07, cornerHeight: s * 0.07)
        }
        return [shape(band, fill: nil, stroke: rgb(0.16, 0.17, 0.2), line: max(0.8, s * 0.08), scale: scale),
                shape(cups, fill: rgb(0.98, 0.42, 0.36), stroke: rgb(0.16, 0.17, 0.2), line: outline(s), scale: scale)]
    }

    /// Dark lenses over its eyes, wherever its face puts them.
    private static func sunglasses(_ s: CGFloat, face: NotchMascotFaceLayout, scale: CGFloat) -> [CALayer] {
        let lenses = CGMutablePath()
        let width = s * 0.27, height = s * 0.19
        for eye in [face.leftEye, face.rightEye] {
            lenses.addRoundedRect(in: CGRect(x: eye.x * s - width / 2, y: eye.y * s - height / 2, width: width, height: height),
                                  cornerWidth: s * 0.07, cornerHeight: s * 0.07)
        }
        let bridge = CGMutablePath()
        bridge.move(to: CGPoint(x: face.leftEye.x * s + width / 2, y: face.leftEye.y * s - height * 0.2))
        bridge.addLine(to: CGPoint(x: face.rightEye.x * s - width / 2, y: face.rightEye.y * s - height * 0.2))
        let glint = CGMutablePath()
        for eye in [face.leftEye, face.rightEye] {
            glint.move(to: CGPoint(x: eye.x * s - width * 0.25, y: eye.y * s - height * 0.15))
            glint.addLine(to: CGPoint(x: eye.x * s - width * 0.05, y: eye.y * s - height * 0.15))
        }
        return [shape(bridge, fill: nil, stroke: rgb(0.1, 0.1, 0.12), line: max(0.5, s * 0.04), scale: scale),
                shape(lenses, fill: rgb(0.08, 0.08, 0.1, 0.94), scale: scale),
                shape(glint, fill: nil, stroke: NSColor.white.withAlphaComponent(0.7), line: max(0.4, s * 0.03), scale: scale)]
    }

    /// A small mug held low on the side away from the camera, steaming.
    private static func coffee(_ s: CGFloat, outward: CGFloat, scale: CGFloat, moving: Bool) -> [CALayer] {
        let center = CGPoint(x: s * (0.5 + outward * 0.38), y: s * 0.8)
        let width = s * 0.24, height = s * 0.22
        let body = CGPath(roundedRect: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
                          cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil)
        let handle = CGMutablePath()
        let hx = center.x + outward * width / 2
        handle.move(to: CGPoint(x: hx, y: center.y - height * 0.25))
        handle.addQuadCurve(to: CGPoint(x: hx, y: center.y + height * 0.2),
                            control: CGPoint(x: hx + outward * width * 0.6, y: center.y))
        let brew = CGPath(roundedRect: CGRect(x: center.x - width * 0.38, y: center.y - height * 0.42, width: width * 0.76, height: height * 0.2),
                          cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil)
        var layers: [CALayer] = [
            shape(handle, fill: nil, stroke: rgb(0.62, 0.5, 0.38), line: max(0.6, s * 0.05), scale: scale),
            shape(body, fill: rgb(0.96, 0.93, 0.86), stroke: rgb(0.62, 0.5, 0.38), line: outline(s), scale: scale),
            shape(brew, fill: rgb(0.45, 0.27, 0.13), scale: scale),
        ]
        guard moving else { return layers }
        for index in 0..<2 {
            let wisp = CGMutablePath()
            let x = center.x + (index == 0 ? -1 : 1) * width * 0.18
            wisp.move(to: CGPoint(x: x, y: center.y - height * 0.6))
            wisp.addCurve(to: CGPoint(x: x, y: center.y - height * 1.5),
                          control1: CGPoint(x: x + s * 0.06, y: center.y - height * 0.9),
                          control2: CGPoint(x: x - s * 0.06, y: center.y - height * 1.2))
            let steam = shape(wisp, fill: nil, stroke: NSColor.white.withAlphaComponent(0.75), line: max(0.4, s * 0.03), scale: scale)
            steam.opacity = 0
            let rise = CAKeyframeAnimation(keyPath: "position.y")
            rise.values = [s * 0.04, -s * 0.1]
            rise.isAdditive = true
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.9, 0]
            let group = CAAnimationGroup()
            group.animations = [rise, fade]
            group.duration = 2.2
            group.repeatCount = .infinity
            group.timeOffset = Double(index) * 1.1
            steam.add(group, forKey: "forkSteam")
            layers.append(steam)
        }
        return layers
    }

    /// An umbrella held over its head, its handle on the side away from the camera.
    private static func umbrella(_ s: CGFloat, outward: CGFloat, scale: CGFloat) -> [CALayer] {
        let pole = s * (0.5 + outward * 0.46)
        let center = CGPoint(x: s * (0.5 + outward * 0.16), y: s * 0.1)
        let radius = s * 0.32
        let canopy = CGMutablePath()
        canopy.move(to: CGPoint(x: center.x - radius, y: center.y))
        canopy.addArc(center: center, radius: radius, startAngle: .pi, endAngle: 0, clockwise: false)
        // Scalloped edge, three small waves back to the start.
        let step = radius * 2 / 3
        for index in 0..<3 {
            let x = center.x + radius - step * CGFloat(index)
            canopy.addQuadCurve(to: CGPoint(x: x - step, y: center.y), control: CGPoint(x: x - step / 2, y: center.y - s * 0.07))
        }
        canopy.closeSubpath()
        let ribs = CGMutablePath()
        ribs.move(to: CGPoint(x: center.x, y: center.y - radius))
        ribs.addLine(to: CGPoint(x: center.x, y: center.y - s * 0.04))
        let handle = CGMutablePath()
        handle.move(to: CGPoint(x: center.x, y: center.y - radius))
        handle.addLine(to: CGPoint(x: center.x, y: center.y - radius - s * 0.06))
        handle.move(to: CGPoint(x: center.x, y: center.y))
        handle.addLine(to: CGPoint(x: pole, y: s * 0.62))
        handle.addQuadCurve(to: CGPoint(x: pole - outward * s * 0.1, y: s * 0.66), control: CGPoint(x: pole, y: s * 0.72))
        return [shape(handle, fill: nil, stroke: rgb(0.32, 0.25, 0.2), line: max(0.6, s * 0.045), scale: scale),
                shape(canopy, fill: rgb(0.2, 0.56, 0.96), stroke: rgb(0.1, 0.36, 0.72), line: outline(s), scale: scale),
                shape(ribs, fill: nil, stroke: rgb(0.1, 0.36, 0.72), line: max(0.4, s * 0.03), scale: scale)]
    }

    /// A little pumpkin on the ground beside it, away from the camera.
    private static func pumpkin(_ s: CGFloat, outward: CGFloat, scale: CGFloat) -> [CALayer] {
        let center = CGPoint(x: s * (0.5 + outward * 0.62), y: s * 0.84)
        let rx = s * 0.2, ry = s * 0.15
        let body = CGPath(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2), transform: nil)
        let ridges = CGMutablePath()
        for dx in [-0.45, 0.45] {
            ridges.move(to: CGPoint(x: center.x + rx * CGFloat(dx), y: center.y - ry * 0.85))
            ridges.addQuadCurve(to: CGPoint(x: center.x + rx * CGFloat(dx), y: center.y + ry * 0.85),
                                control: CGPoint(x: center.x + rx * CGFloat(dx) * 1.5, y: center.y))
        }
        let stem = CGMutablePath()
        stem.move(to: CGPoint(x: center.x, y: center.y - ry * 0.9))
        stem.addQuadCurve(to: CGPoint(x: center.x + outward * rx * 0.35, y: center.y - ry * 1.55),
                          control: CGPoint(x: center.x, y: center.y - ry * 1.4))
        return [shape(body, fill: rgb(0.98, 0.55, 0.12), stroke: rgb(0.72, 0.33, 0.05), line: outline(s), scale: scale),
                shape(ridges, fill: nil, stroke: rgb(0.8, 0.38, 0.06), line: max(0.4, s * 0.03), scale: scale),
                shape(stem, fill: nil, stroke: rgb(0.3, 0.58, 0.22), line: max(0.6, s * 0.05), scale: scale)]
    }
}

// MARK: - Settings

/// Under the companion's settings, next to the livelier companion.
struct ForkMascotDaySettingsRow: View {
    @AppStorage(DefaultsKey.forkMascotDay) private var day = true

    var body: some View {
        let text = ForkMascotStrings.current
        ForkOptionRow(symbol: "sun.horizon", title: text.day, caption: text.dayCaption) {
            Toggle(text.day, isOn: $day).labelsHidden().toggleStyle(.switch)
        }
    }
}
