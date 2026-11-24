// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import QuartzCore
import SwiftUI

/// The livelier companion (see `ForkMascotLifeLogic`), drawn the way
/// upstream draws it: Core Animation layers, each motion computed once and
/// played by the render server, nothing ticking in the app. Its props sit
/// in a layer on the body's tilting layer, so they follow every hop, squash
/// and tilt. One switch turns it all off.
enum ForkMascotLife {
    typealias Logic = ForkMascotLifeLogic

    static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.forkMascotLively)
    }

    // MARK: Mood

    static func affection(now: Date = Date()) -> Double {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: DefaultsKey.forkMascotAffection) as? Double ?? 50
        return Logic.affection(stored, since: defaults.object(forKey: DefaultsKey.forkMascotAffectionDate) as? Date, now: now)
    }

    static func notePetted() {
        guard isOn() else { return }
        let defaults = UserDefaults.standard
        defaults.set(Logic.petted(affection()), forKey: DefaultsKey.forkMascotAffection)
        defaults.set(Date(), forKey: DefaultsKey.forkMascotAffectionDate)
    }

    static func restingMood(base: NotchMascotMood) -> NotchMascotMood {
        let day = ForkMascotDay.restingMood(base: base)
        return isOn() ? Logic.restingMood(base: day, affection: affection()) : day
    }

    // MARK: Visits

    /// A stroll or a crossing reshaped to one of the fork's ways; every
    /// other visit, and the island's timing, as upstream has them.
    static func path(for visit: NotchMascotVisit?, base: NotchMascotPath, track: NotchMascotTrack) -> NotchMascotPath {
        guard isOn(), let visit else { return base }
        let roundTrip: Bool
        switch visit.kind {
        case .lap: roundTrip = true
        case .pass: roundTrip = false
        default: return base
        }
        let style = Logic.visitStyle(id: visit.id, roundTrip: roundTrip)
        return Logic.reshape(base, style: style, size: track.size, rest: track.rest)
    }
}

// MARK: - Props and activities

/// One per companion: a layer of props on its body, the idle activities
/// and the Zzz of a doze.
final class ForkMascotDecor {
    typealias Logic = ForkMascotLifeLogic
    typealias Activity = Logic.Activity

    private weak var rig: NotchMascotRig?
    private weak var hopper: CALayer?
    private weak var squasher: CALayer?
    private weak var tilter: CALayer?
    private var flash: (NotchMascotMood, TimeInterval) -> Void = { _, _ in }
    private let decor = CALayer()
    private var size: CGFloat = 0
    private var scale: CGFloat = 2
    private var last: TimeInterval?
    private var recent: [Activity] = []
    private let snore = CALayer()
    private let wardrobe = ForkMascotWardrobe()
    private let skin = ForkMascotVariantSkin()
    private let chatter = ForkMascotChatter()

    /// A settings preview's own variant (cat, ghost, pixel, blob).
    var variantOverride: ForkMascotVariantLogic.Variant? {
        get { skin.override }
        set { skin.override = newValue }
    }

    func connect(rig: NotchMascotRig, hopper: CALayer, squasher: CALayer, tilter: CALayer,
                 body: CALayer, outline: CAShapeLayer,
                 flash: @escaping (NotchMascotMood, TimeInterval) -> Void) {
        self.rig = rig
        self.hopper = hopper
        self.squasher = squasher
        self.tilter = tilter
        self.flash = flash
        decor.actions = ["position": NSNull(), "bounds": NSNull(), "sublayers": NSNull(), "contents": NSNull()]
        decor.masksToBounds = false
        tilter.addSublayer(decor)
        decor.addSublayer(snore)
        wardrobe.connect(rig: rig, under: decor)
        skin.connect(rig: rig, hopper: hopper, squasher: squasher, tilter: tilter, body: body, outline: outline, under: decor)
        chatter.connect(rig: rig, hopper: hopper, above: decor)
    }

    func configure(size: CGFloat, scale: CGFloat) {
        self.size = size
        self.scale = scale
        decor.frame = CGRect(x: 0, y: 0, width: size, height: size)
        decor.contentsScale = scale
        snore.frame = decor.bounds
        wardrobe.configure(size: size, scale: scale)
        skin.configure(size: size, scale: scale)
        chatter.configure(size: size, scale: scale)
    }

    /// A reaction began: the cheer for the day's last task throws confetti.
    func reacted(_ reaction: NotchMascotReaction) {
        skin.reacted(reaction)
        chatter.reacted(reaction)
        if reaction == .celebrate, ForkMascotDay.shared.takesParty() { wardrobe.celebrate() }
    }

    /// The Zzz of a doze, rising now and then while it sleeps.
    func moodChanged(_ mood: NotchMascotMood) {
        skin.moodChanged(mood)
        snore.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard mood == .sleepy, ForkMascotLife.isOn(), size > 0, rig?.reduceMotion == false else { return }
        for index in 0..<2 {
            let z = text("z", size: size * (index == 0 ? 0.34 : 0.26))
            z.position = CGPoint(x: size * 0.9, y: size * 0.2)
            z.opacity = 0
            let rise = CAKeyframeAnimation(keyPath: "position")
            rise.values = [CGPoint(x: size * 0.85, y: size * 0.25), CGPoint(x: size * 1.05, y: -size * 0.05),
                           CGPoint(x: size * 1.2, y: -size * 0.35)].map { NSValue(point: $0) }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.9, 0]
            let group = CAAnimationGroup()
            group.animations = [rise, fade]
            group.duration = 2.4
            group.repeatCount = .infinity
            group.timeOffset = Double(index) * 1.2
            z.add(group, forKey: "forkSnore")
            snore.addSublayer(z)
        }
    }

    /// After a blink at rest: maybe an activity, its length when one starts.
    func idleBeat() -> TimeInterval? {
        skin.heal()
        guard ForkMascotLife.isOn(), size > 0 else { return nil }
        let now = CACurrentMediaTime()
        guard let activity = Logic.nextActivity(now: now, last: last, recent: recent,
                                                random: Double.random(in: 0..<1), pick: Double.random(in: 0..<1))
        else { return nil }
        last = now
        recent = Array((recent + [activity]).suffix(Logic.memory))
        play(activity)
        return activity.duration
    }

    // MARK: Drawing

    private func text(_ string: String, size font: CGFloat) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = string
        layer.fontSize = font
        layer.font = NSFont.systemFont(ofSize: font, weight: .bold)
        layer.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer.alignmentMode = .center
        layer.contentsScale = scale
        layer.bounds = CGRect(x: 0, y: 0, width: font * 1.4, height: font * 1.4)
        layer.actions = ["position": NSNull(), "opacity": NSNull(), "contents": NSNull()]
        return layer
    }

    /// A prop shown for `duration`, then taken away.
    private func show(_ layer: CALayer, for duration: TimeInterval, animations: [CAAnimation]) {
        decor.addSublayer(layer)
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        layer.add(group, forKey: "forkProp")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { layer.removeFromSuperlayer() }
    }

    private func additive(_ keyPath: String, _ values: [CGFloat], times: [NSNumber]? = nil, duration: TimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.duration = duration
        animation.isAdditive = true
        animation.calculationMode = .cubic
        return animation
    }

    private func play(_ activity: Activity) {
        let s = size, d = activity.duration
        switch activity {
        case .stretch:
            flash(.happy, d)
            squasher?.add(additive("transform.scale.y", [0, 0.2, 0.2, 0], times: [0, 0.3, 0.7, 1], duration: d), forKey: "forkStretchY")
            squasher?.add(additive("transform.scale.x", [0, -0.1, -0.1, 0], times: [0, 0.3, 0.7, 1], duration: d), forKey: "forkStretchX")
        case .yawn:
            flash(.sleepy, d)
            tilter?.add(additive("transform.rotation.z", [0, -0.14, -0.14, 0], times: [0, 0.25, 0.75, 1], duration: d), forKey: "forkYawn")
        case .pushUps:
            flash(.determined, d)
            let down = s * 0.12
            hopper?.add(additive("position.y", [0, down, 0, down, 0, down, 0], duration: d), forKey: "forkPushUps")
        case .lookAround:
            rig?.attend(to: CGPoint(x: -0.16, y: 0), hold: 0.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak rig] in
                rig?.attend(to: CGPoint(x: 0.16, y: 0), hold: 0.5)
            }
        case .whistle:
            flash(.happy, d)
            for index in 0..<2 {
                let note = text(index == 0 ? "♪" : "♫", size: s * 0.36)
                note.opacity = 0
                let rise = CAKeyframeAnimation(keyPath: "position")
                rise.values = [CGPoint(x: s * 0.95, y: s * 0.35), CGPoint(x: s * 1.2, y: -s * 0.1)].map { NSValue(point: $0) }
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 1, 0]
                let delay = Double(index) * 0.7
                for animation in [rise, fade] {
                    animation.beginTime = delay
                    animation.duration = d - delay
                    animation.fillMode = .both
                }
                show(note, for: d, animations: [rise, fade])
            }
        case .bubble:
            flash(.happy, d)
            let bubble = CAShapeLayer()
            let radius = s * 0.18
            bubble.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
            bubble.fillColor = NSColor.white.withAlphaComponent(0.15).cgColor
            bubble.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
            bubble.lineWidth = max(0.6, s * 0.05)
            bubble.position = CGPoint(x: s * 0.5, y: s * 0.72)
            bubble.contentsScale = scale
            bubble.actions = ["position": NSNull(), "transform": NSNull(), "opacity": NSNull()]
            let grow = CAKeyframeAnimation(keyPath: "transform.scale")
            grow.values = [0.1, 1, 1.15, 1.6]
            grow.keyTimes = [0, 0.7, 0.85, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.1, 0.85, 1]
            show(bubble, for: d, animations: [grow, fade])
        case .book:
            rig?.attend(to: CGPoint(x: 0, y: 0.12), hold: d - 0.5)
            let book = CAShapeLayer()
            let width = s * 0.56, height = s * 0.3
            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            let path = CGMutablePath()
            path.addRoundedRect(in: rect, cornerWidth: s * 0.04, cornerHeight: s * 0.04)
            path.move(to: CGPoint(x: 0, y: rect.minY))
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            book.path = path
            book.fillColor = NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.04, alpha: 1).cgColor
            book.strokeColor = NSColor(calibratedRed: 0.55, green: 0.3, blue: 0.02, alpha: 1).cgColor
            book.lineWidth = max(0.4, s * 0.03)
            book.position = CGPoint(x: s * 0.5, y: s * 0.86)
            book.contentsScale = scale
            book.actions = ["position": NSNull(), "opacity": NSNull()]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.12, 0.88, 1]
            show(book, for: d, animations: [fade])
        }
    }
}

// MARK: - Eyes on the pointer near the island

/// While the companion rests, its eyes follow the pointer around the
/// island, not only over it, and a pointer rushing at it makes it jump.
/// Only the pointer's position is read, a few times a second at most.
final class ForkMascotGaze {
    typealias Logic = ForkMascotLifeLogic
    private weak var host: NotchMascotHostView?
    private var monitors: [Any] = []
    private var following = false
    private var lastSample: (time: CFTimeInterval, distance: CGFloat)?
    private var lastStartle: CFTimeInterval = 0

    func sync(host: NotchMascotHostView, on: Bool) {
        self.host = host
        let wanted = on && ForkMascotLife.isOn()
        if wanted, monitors.isEmpty {
            if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in self?.moved() }) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
                self?.moved()
                return event
            }) { monitors.append(local) }
        } else if !wanted, !monitors.isEmpty {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            following = false
        }
    }

    deinit { monitors.forEach(NSEvent.removeMonitor) }

    private func moved() {
        let now = CACurrentMediaTime()
        if let lastSample, now - lastSample.time < 1.0 / 15 { return }
        guard let host, let window = host.window, host.mascot.size > 0, !host.mascot.isVisiting else { return }
        let point = host.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        // Over the island itself upstream already follows it.
        if host.bounds.contains(point) {
            following = false
            lastSample = nil
            return
        }
        let center = host.mascot.root.position
        let distance = hypot(point.x - center.x, point.y - center.y)
        if let lastSample {
            let speed = (lastSample.distance - distance) / CGFloat(max(0.001, now - lastSample.time))
            if Logic.startles(distance: distance, approachSpeed: speed), now - lastStartle > NotchMascotReactionGate.repeatInterval {
                lastStartle = now
                host.mascot.react(.surprised, lift: 0)
            }
        }
        lastSample = (now, distance)
        if Logic.follows(distance: distance) {
            host.mascot.attend(to: NotchMascotSupport.pointerGaze(from: center, to: point, size: host.mascot.size))
            following = true
        } else if following {
            host.mascot.lookAhead()
            following = false
        }
    }
}

// MARK: - Settings

/// Under the companion's settings: the fork's additions, on or off.
struct ForkMascotSettingsRows: View {
    @AppStorage(DefaultsKey.forkMascotLively) private var lively = true

    var body: some View {
        let text = ForkMascotStrings.current
        ForkOptionRow(symbol: "sparkles", title: text.lively, caption: text.livelyCaption) {
            Toggle(text.lively, isOn: $lively).labelsHidden().toggleStyle(.switch)
        }
        ForkMascotDaySettingsRow()
        ForkMascotExtrasRows()
    }
}
