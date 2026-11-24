// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import QuartzCore
import SwiftUI

/// The minimal companion as a cat, a ghost, a pixel one or a blob (see
/// `ForkMascotVariantLogic`). One per companion, on its own layers: it
/// swaps the body's outline, adds the cat's parts, and starts the few
/// motions that loop in the render server. The classic one puts all back.
final class ForkMascotVariantSkin {
    typealias Logic = ForkMascotVariantLogic
    typealias Variant = Logic.Variant

    private weak var rig: NotchMascotRig?
    private weak var hopper: CALayer?
    private weak var squasher: CALayer?
    private weak var tilter: CALayer?
    private weak var body: CALayer?
    private weak var outline: CAShapeLayer?
    private let parts = CALayer()
    private var size: CGFloat = 0
    private var scale: CGFloat = 2
    private var applied: (Variant, NotchMascotLook, CGFloat, NotchMascotSide, Bool)?
    private var sleeping = false
    private var observer: NSObjectProtocol?

    /// A settings preview's own variant, over the user's choice.
    var override: Variant? {
        didSet { if override != oldValue { apply() } }
    }

    func connect(rig: NotchMascotRig, hopper: CALayer, squasher: CALayer, tilter: CALayer,
                 body: CALayer, outline: CAShapeLayer, under decor: CALayer) {
        self.rig = rig
        self.hopper = hopper
        self.squasher = squasher
        self.tilter = tilter
        self.body = body
        self.outline = outline
        parts.actions = ["position": NSNull(), "bounds": NSNull(), "sublayers": NSNull(), "contents": NSNull()]
        parts.masksToBounds = false
        decor.insertSublayer(parts, at: 0)
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.apply() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func configure(size: CGFloat, scale: CGFloat) {
        self.size = size
        self.scale = scale
        parts.frame = CGRect(x: 0, y: 0, width: size, height: size)
        parts.contentsScale = scale
        applied = nil
        apply()
    }

    var variant: Variant {
        let chosen = override ?? Logic.variant(UserDefaults.standard.string(forKey: DefaultsKey.forkMascotVariant))
        return Logic.effective(chosen, minimal: rig?.look.style == .minimal)
    }

    func moodChanged(_ mood: NotchMascotMood) {
        let asleep = mood == .sleepy
        guard asleep != sleeping else { return heal() }
        sleeping = asleep
        applied = nil
        apply()
    }

    /// Something took every motion off (the island resets the companion):
    /// put the looping ones back.
    func heal() {
        guard let rig, !rig.reduceMotion else { return }
        switch variant {
        case .ghost where hopper?.animation(forKey: "forkGhostFloat") == nil: startFloat()
        case .blob where squasher?.animation(forKey: "forkBlobWobble") == nil: startWobble()
        default: break
        }
    }

    /// A reaction makes the blob splat a little harder.
    func reacted(_ reaction: NotchMascotReaction) {
        guard variant == .blob, let rig, !rig.reduceMotion, size > 0 else { return }
        squasher?.add(wobble(Logic.blobSplat, duration: 0.7, repeats: false), forKey: "forkBlobSplat")
    }

    // MARK: Applying

    private func apply() {
        guard size > 0, let rig else { return }
        let variant = self.variant
        let side = NotchMascotSupport.side()
        if let applied, applied.0 == variant, applied.1 == rig.look, applied.2 == size, applied.3 == side,
           applied.4 == rig.reduceMotion { return }
        applied = (variant, rig.look, size, side, rig.reduceMotion)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        // Back to the island's own companion first.
        parts.sublayers?.forEach { $0.removeFromSuperlayer() }
        hopper?.removeAnimation(forKey: "forkGhostFloat")
        squasher?.removeAnimation(forKey: "forkBlobWobble")
        body?.opacity = 1
        if let tilter {
            tilter.shouldRasterize = false
            tilter.rasterizationScale = scale
            tilter.magnificationFilter = .linear
            tilter.minificationFilter = .linear
        }
        guard rig.look.style == .minimal else { return }
        let shape = NotchMascotGeometry.body(rig.look.shape, size: size)
        outline?.path = shape
        switch variant {
        case .classic:
            break
        case .cat:
            dressCat(top: shape.boundingBoxOfPath.minY / size, outward: side == .left ? -1 : 1)
        case .ghost:
            outline?.path = Logic.ghostBody(size: size)
            body?.opacity = Logic.ghostOpacity
            if !rig.reduceMotion { startFloat() }
        case .pixel:
            outline?.path = Logic.pixelated(shape, size: size)
            if let tilter {
                tilter.shouldRasterize = true
                tilter.rasterizationScale = Logic.rasterScale(size: size)
                tilter.magnificationFilter = .nearest
                tilter.minificationFilter = .nearest
            }
        case .blob:
            outline?.path = Logic.blobBody(size: size)
            if !rig.reduceMotion { startWobble() }
        }
    }

    private func startFloat() {
        let float = CAKeyframeAnimation(keyPath: "position.y")
        float.values = [0, -size * Logic.ghostFloat, 0]
        float.isAdditive = true
        float.calculationMode = .cubic
        float.duration = 2.8
        float.repeatCount = .infinity
        hopper?.add(float, forKey: "forkGhostFloat")
    }

    private func startWobble() {
        squasher?.add(wobble(Logic.blobWobble, duration: 2.4, repeats: true), forKey: "forkBlobWobble")
    }

    private func wobble(_ values: [CGFloat], duration: TimeInterval, repeats: Bool) -> CAAnimationGroup {
        let wide = CAKeyframeAnimation(keyPath: "transform.scale.x")
        wide.values = values
        let tall = CAKeyframeAnimation(keyPath: "transform.scale.y")
        tall.values = values.map { -$0 }
        let group = CAAnimationGroup()
        for animation in [wide, tall] {
            animation.isAdditive = true
            animation.calculationMode = .cubic
            animation.duration = duration
        }
        group.animations = [wide, tall]
        group.duration = duration
        if repeats { group.repeatCount = .infinity }
        return group
    }

    // MARK: The cat

    private func dressCat(top: CGFloat, outward: CGFloat) {
        guard let rig else { return }
        let s = size
        let palette = rig.look.palette
        let moving = !rig.reduceMotion
        // The tail first, under everything else.
        let tail = shape(Logic.tail(outward: outward, curled: sleeping, size: s), fill: nil,
                         stroke: palette.shade.cgColor, line: max(1, s * 0.1))
        let base = Logic.tailBase(outward: outward, size: s)
        pivot(tail, at: base)
        if moving, !sleeping {
            let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            sway.values = [0, outward * Logic.tailSway, 0, -outward * Logic.tailSway * 0.5, 0]
            sway.calculationMode = .cubic
            sway.duration = 1.8
            sway.repeatCount = .infinity
            tail.add(sway, forKey: "forkTailSway")
        }
        parts.addSublayer(tail)
        for left in [true, false] {
            let ear = CALayer()
            ear.frame = CGRect(x: 0, y: 0, width: s, height: s)
            ear.actions = ["position": NSNull(), "transform": NSNull(), "anchorPoint": NSNull()]
            ear.addSublayer(shape(Logic.ear(left: left, top: top, size: s), fill: palette.light.cgColor))
            ear.addSublayer(shape(Logic.ear(left: left, top: top, size: s, inner: true),
                                  fill: CGColor(red: 0.98, green: 0.62, blue: 0.68, alpha: 1)))
            pivot(ear, at: Logic.earPivot(left: left, top: top, size: s))
            if moving {
                // A quick twitch now and then, each ear on its own beat.
                let twitch = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                let turn: CGFloat = left ? -0.3 : 0.3
                twitch.values = [0, turn, -turn * 0.4, 0, 0]
                twitch.keyTimes = [0, 0.015, 0.03, 0.045, 1]
                twitch.duration = left ? 7.3 : 9.1
                twitch.timeOffset = left ? 2 : 5
                twitch.repeatCount = .infinity
                ear.add(twitch, forKey: "forkEarTwitch")
            }
            parts.addSublayer(ear)
        }
        let eyeY = rig.look.face.leftEye.y
        parts.addSublayer(shape(Logic.whiskers(eyeY: eyeY, size: s), fill: nil,
                                stroke: NotchMascotColor.ink.cgColor.copy(alpha: 0.55), line: max(0.4, s * 0.025)))
        parts.addSublayer(shape(Logic.nose(eyeY: eyeY, size: s), fill: CGColor(red: 0.95, green: 0.5, blue: 0.58, alpha: 1)))
    }

    private func shape(_ path: CGPath, fill: CGColor?, stroke: CGColor? = nil, line: CGFloat = 0) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.path = path
        layer.fillColor = fill
        layer.strokeColor = stroke
        layer.lineWidth = line
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.contentsScale = scale
        layer.actions = ["path": NSNull(), "position": NSNull(), "transform": NSNull(), "anchorPoint": NSNull()]
        return layer
    }

    /// Turns `layer` (the companion's square) around `point` instead of its middle.
    private func pivot(_ layer: CALayer, at point: CGPoint) {
        guard size > 0 else { return }
        layer.anchorPoint = CGPoint(x: point.x / size, y: point.y / size)
        layer.position = point
    }
}

// MARK: - A preview's own variant

private struct ForkMascotVariantKey: EnvironmentKey {
    static let defaultValue: ForkMascotVariantLogic.Variant? = nil
}

extension EnvironmentValues {
    /// Set on a settings preview to draw that variant whatever is chosen.
    var forkMascotVariant: ForkMascotVariantLogic.Variant? {
        get { self[ForkMascotVariantKey.self] }
        set { self[ForkMascotVariantKey.self] = newValue }
    }
}

// MARK: - Settings

/// « More styles » under the style tiles, for the minimal companion.
struct ForkMascotVariantPicker: View {
    typealias Variant = ForkMascotVariantLogic.Variant
    let look: NotchMascotLook
    @AppStorage(DefaultsKey.forkMascotVariant) private var chosen = Variant.classic.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var showsShapes: Bool {
        ForkMascotVariantLogic.variant(UserDefaults.standard.string(forKey: DefaultsKey.forkMascotVariant)).keepsShape
    }

    var body: some View {
        if look.style == .minimal {
            let text = ForkMascotStrings.current
            VStack(alignment: .leading, spacing: 8) {
                Text(text.variants).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Variant.allCases, id: \.self) { tile($0, text: text) }
                }
            }
            .padding(.leading, settingsRowTextInset)
            .transition(.opacity)
        }
    }

    private func tile(_ variant: Variant, text: ForkMascotStrings) -> some View {
        let selected = ForkMascotVariantLogic.variant(chosen) == variant
        let name = text.variantName(variant)
        return Button { chosen = variant.rawValue } label: {
            VStack(spacing: 6) {
                NotchMascotView(look: look, size: 24, idles: !reduceMotion)
                    .environment(\.forkMascotVariant, variant)
                    .frame(width: 24, height: 24)
                    .frame(width: 52, height: 38)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
    }
}
