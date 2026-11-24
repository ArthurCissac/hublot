// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// The island's mark for what plays: its little scene (`forkAmbientScenes`),
/// or the wave when scenes are off or nothing is chosen.
struct ForkAmbientMark: View {
    var color: Color
    var height: CGFloat
    var bars = ForkAmbientLogic.islandWaveBars
    @ObservedObject private var player = ForkAmbientPlayer.shared
    @AppStorage(DefaultsKey.forkAmbientScenes) private var scenes = true

    var body: some View {
        if scenes, let sound = ForkAmbientLogic.sceneSound(for: player.mix) {
            ForkAmbientScene(sound: sound, active: player.audible, height: height)
        } else {
            ForkAmbientWave(active: player.audible, bars: bars, color: color, height: height)
        }
    }
}

/// One sound's scene, drawn from paths each frame while the sound is heard;
/// still and dimmed while it holds, still with Reduce Motion. Nothing runs
/// while it is still: the timeline pauses.
struct ForkAmbientScene: View {
    typealias Logic = ForkAmbientLogic
    var sound: Logic.Sound
    var active: Bool
    var height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = active && !reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !moving)) { context in
            let time = moving ? context.date.timeIntervalSinceReferenceDate : ForkAmbientSceneArt.still
            Canvas { canvas, size in
                var canvas = canvas
                canvas.scaleBy(x: size.width / Logic.sceneCanvas.width, y: size.height / Logic.sceneCanvas.height)
                ForkAmbientSceneArt.draw(sound, in: canvas, time: time)
            }
        }
        .frame(width: Logic.sceneWidth(height: height), height: height)
        .opacity(active ? 1 : 0.5)
        .accessibilityHidden(true)
    }
}

/// The drawings, in units of a 26 × 20 box (`ForkAmbientLogic.sceneCanvas`),
/// made for the island's black. All recreated: plain shapes, no artwork.
enum ForkAmbientSceneArt {
    typealias Logic = ForkAmbientLogic

    /// The moment a still scene shows: mid-song, mid-flash, drops spread out.
    static let still: Double = 0.3

    static func draw(_ sound: Logic.Sound, in context: GraphicsContext, time t: Double) {
        var ctx = context
        let box = CGRect(origin: .zero, size: Logic.sceneCanvas)
        ctx.clip(to: Path(roundedRect: box, cornerRadius: box.height * Logic.sceneCornerShare))
        switch sound {
        case .white: television(ctx, t)
        case .pink: fan(ctx, t)
        case .brown: porthole(ctx, t)
        case .rain: rain(ctx, t)
        case .ocean: ocean(ctx, t)
        case .wind: wind(ctx, t)
        case .fire: campfire(ctx, t)
        case .forest: bird(ctx, t)
        case .stream: stream(ctx, t)
        case .thunder: storm(ctx, t)
        case .alpha: headphones(ctx, t)
        case .beta: bulb(ctx, t)
        case .gamma: atom(ctx, t)
        case .chords: vinyl(ctx, t)
        case .drone: drone(ctx, t)
        case .bowls: bowl(ctx, t)
        }
    }

    // MARK: - Nature

    /// A cloud, drops falling from it.
    private static func rain(_ ctx: GraphicsContext, _ t: Double) {
        for (index, x) in [7.5, 11, 14.5, 18, 21.5].enumerated() {
            let phase = Logic.cycle(t, period: 0.75, offset: Double(index) * 0.37)
            var drop = ctx
            drop.opacity = phase < 0.8 ? 1 : (1 - phase) / 0.2
            drop.fill(Path(roundedRect: CGRect(x: x - 0.65, y: 10 + phase * 11, width: 1.3, height: 3), cornerRadius: 0.65),
                      with: .color(rgb(0x5AB4FF)))
        }
        fill(ctx, cloud(pt(13.5, 6)), rgb(0xD5E0EE))
    }

    /// A dark cloud, slanted rain, and now and then lightning.
    private static func storm(_ ctx: GraphicsContext, _ t: Double) {
        let flash = Logic.lightning(t)
        if flash > 0 { halo(ctx, pt(13, 8), 12, rgb(0xFFE27A), 0.5 * flash) }
        for (index, x) in [8.0, 12.5, 17, 21].enumerated() {
            let phase = Logic.cycle(t, period: 0.5, offset: Double(index) * 0.29)
            let y = 10 + phase * 11
            var drop = ctx
            drop.opacity = 0.9 * (phase < 0.8 ? 1 : (1 - phase) / 0.2)
            drop.stroke(line([pt(x, y), pt(x - 1.1, y + 2.8)]), with: .color(rgb(0x7FA8D9)),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }
        if flash > 0 {
            var bolt = Path()
            bolt.addLines([pt(14.6, 8.5), pt(11.2, 13.6), pt(13.6, 13.6), pt(11.4, 19.4),
                           pt(16.6, 12.2), pt(14, 12.2), pt(16.2, 8.5)])
            bolt.closeSubpath()
            var lit = ctx
            lit.opacity = flash
            lit.fill(bolt, with: .color(rgb(0xFFD84A)))
        }
        fill(ctx, cloud(pt(13.5, 5.6)), blend(0x5D6678, 0xC9D2E3, flash * 0.6))
    }

    /// Waves rolling in, a little sailboat riding them, the sun above.
    private static func ocean(_ ctx: GraphicsContext, _ t: Double) {
        ctx.fill(dot(pt(20.5, 4.5), 2.6), with: .color(rgb(0xFFC94A)))
        let backPhase = -t * 1.6
        ctx.fill(sea(base: 11.5, amplitude: 1.3, frequency: 0.5, phase: backPhase), with: .color(rgb(0x2D7FD3)))

        let boatX = 9 + 1.2 * sin(t * 0.6)
        let boatY = 11.5 + 1.3 * sin(boatX * 0.5 + backPhase)
        var boat = ctx
        boat.translateBy(x: boatX, y: boatY)
        boat.rotate(by: .radians(atan(0.65 * cos(boatX * 0.5 + backPhase)) * 0.8))
        var hull = Path()
        hull.addLines([pt(-3.2, -1.2), pt(3.2, -1.2), pt(2.2, 0.6), pt(-2.2, 0.6)])
        hull.closeSubpath()
        boat.stroke(line([pt(-0.4, -1.2), pt(-0.4, -6.6)]), with: .color(rgb(0x8B5A2B)), lineWidth: 0.5)
        var sail = Path()
        sail.addLines([pt(-0.1, -1.7), pt(-0.1, -6.4), pt(2.7, -1.7)])
        sail.closeSubpath()
        boat.fill(sail, with: .color(.white))
        boat.fill(hull, with: .color(rgb(0xE8573F)))

        let frontPhase = -t * 2.4 + 1
        ctx.fill(sea(base: 14.5, amplitude: 1.5, frequency: 0.42, phase: frontPhase), with: .color(rgb(0x4FB3F0)))
        var foam = ctx
        foam.opacity = 0.85
        foam.stroke(crest(base: 14.5, amplitude: 1.5, frequency: 0.42, phase: frontPhase), with: .color(.white),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
    }

    /// Gusts curling as they pass, and a leaf tumbling along.
    private static func wind(_ ctx: GraphicsContext, _ t: Double) {
        let style = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
        for (index, y) in [5.5, 10.5, 15.5].enumerated() {
            let x0 = [1.0, 4.0, 0.5][index]
            var gust = Path()
            gust.move(to: pt(x0, y))
            gust.addLine(to: pt(x0 + 15, y))
            gust.addQuadCurve(to: pt(x0 + 18.5, y - 2.6), control: pt(x0 + 18.8, y))
            gust.addQuadCurve(to: pt(x0 + 15.6, y - 3.4), control: pt(x0 + 18, y - 4.8))
            // The whole gust faintly, a brighter breath running along it.
            var trace = ctx
            trace.opacity = 0.28
            trace.stroke(gust, with: .color(rgb(0xCFE6FF)), style: style)
            let head = Logic.cycle(t, period: 1.6, offset: Double(index) * 0.33) * 1.45
            let from = max(0, head - 0.45), to = min(1, head)
            guard to > from else { continue }
            var breath = ctx
            breath.opacity = min(1, (1.45 - head) * 3)
            breath.stroke(gust.trimmedPath(from: from, to: to), with: .color(.white), style: style)
        }
        var leaf = ctx
        leaf.translateBy(x: -3 + 32 * Logic.cycle(t, period: 2.8), y: 11 + 3 * sin(t * 2.6))
        leaf.rotate(by: .radians(t * 4))
        var shape = Path()
        shape.move(to: pt(-2.4, 0))
        shape.addQuadCurve(to: pt(2.4, 0), control: pt(0, -2.2))
        shape.addQuadCurve(to: pt(-2.4, 0), control: pt(0, 2.2))
        leaf.fill(shape, with: .color(rgb(0x7ED957)))
        leaf.stroke(line([pt(-2.4, 0), pt(2.4, 0)]), with: .color(rgb(0x4E9E34)), lineWidth: 0.4)
    }

    /// Two logs, flames flickering, sparks rising.
    private static func campfire(_ ctx: GraphicsContext, _ t: Double) {
        halo(ctx, pt(13, 12), 12, rgb(0xFF8A2B), 0.45 + 0.1 * sin(t * 7))
        for (angle, color) in [(-0.22, UInt32(0x8B5A2B)), (0.22, UInt32(0x7A4A22))] {
            var log = ctx
            log.translateBy(x: 13, y: 17.6)
            log.rotate(by: .radians(angle))
            log.fill(Path(roundedRect: CGRect(x: -7, y: -1.2, width: 14, height: 2.4), cornerRadius: 1.2), with: .color(rgb(color)))
            log.fill(dot(pt(angle < 0 ? -6 : 6, 0), 0.9), with: .color(rgb(0xD9A066)))
        }
        let layers: [(width: CGFloat, height: CGFloat, color: UInt32, shift: Double)] = [
            (9.5, 14, 0xFF5A1F, 0), (6.8, 10.2, 0xFF9F1C, 1.7), (3.8, 6.4, 0xFFE15A, 3.1),
        ]
        for layer in layers {
            let flicker = 1 + 0.1 * sin(t * 9 + layer.shift) + 0.05 * sin(t * 15.3 + layer.shift * 2)
            ctx.fill(flame(base: pt(13, 16.4), width: layer.width, height: layer.height * flicker,
                           sway: 0.9 * sin(t * 5.5 + layer.shift)),
                     with: .color(rgb(layer.color)))
        }
        for index in 0..<3 {
            let phase = Logic.cycle(t, period: 1.3, offset: Double(index) * 0.34)
            var spark = ctx
            spark.opacity = 1 - phase
            spark.fill(dot(pt(13 + [-2.5, 1.5, 3.5][index] + sin(phase * 7 + Double(index)) * 1.1, 9 - phase * 9.5), 0.55),
                       with: .color(rgb(0xFFD25A)))
        }
    }

    /// A round little bird on a branch, singing notes, then resting.
    private static func bird(_ ctx: GraphicsContext, _ t: Double) {
        let sings = Logic.birdSings(t)
        ctx.stroke(line([pt(0, 16.2), pt(26, 14.4)]), with: .color(rgb(0x8B5A2B)),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        for (x, y, angle) in [(3.5, 15.2, -0.6), (21.5, 13.4, 0.5), (24.2, 13.5, -0.4)] {
            var leaf = ctx
            leaf.translateBy(x: x, y: y)
            leaf.rotate(by: .radians(angle))
            leaf.fill(oval(.zero, 1.8, 0.85), with: .color(rgb(0x6CC24A)))
        }
        if sings {
            for index in 0..<2 {
                let phase = Logic.cycle(t, period: 1.4, offset: Double(index) * 0.5)
                var song = ctx
                song.opacity = Logic.trip(phase)
                note(song, at: pt(18.4 + phase * 5.5, 8 - phase * 6.5 + sin(phase * 9) * 0.6), size: 0.85, color: .white)
            }
        }
        var body = ctx
        body.translateBy(x: 0, y: sings ? -0.5 * abs(sin(t * 7)) : 0)
        let feet = rgb(0xF27A1A)
        body.stroke(line([pt(10.5, 13.8), pt(10.2, 15.5)]), with: .color(feet), lineWidth: 0.5)
        body.stroke(line([pt(12.3, 13.8), pt(12.6, 15.3)]), with: .color(feet), lineWidth: 0.5)
        var tail = Path()
        tail.addLines([pt(7.6, 11.4), pt(3.8, 9.6), pt(4.6, 12.8)])
        tail.closeSubpath()
        body.fill(tail, with: .color(rgb(0xE8901A)))
        body.fill(oval(pt(11.4, 10.6), 4.4, 3.6), with: .color(rgb(0xFFB627)))
        body.fill(oval(pt(12.2, 12), 2.6, 1.9), with: .color(rgb(0xFFE08A)))
        var wing = body
        wing.translateBy(x: 9.8, y: 10.6)
        wing.rotate(by: .radians(-0.35 + (sings ? 0.12 * sin(t * 7) : 0)))
        wing.fill(oval(.zero, 2.6, 1.6), with: .color(rgb(0xE8901A)))
        body.fill(dot(pt(13.4, 9.3), 0.8), with: .color(.black))
        body.fill(dot(pt(13.65, 9.05), 0.27), with: .color(.white))
        let open = sings ? 1.3 * abs(sin(t * 14)) : 0
        var upper = Path()
        upper.addLines([pt(15.2, 9.3), pt(17.9, 10), pt(15.4, 10.4)])
        upper.closeSubpath()
        var lower = Path()
        lower.addLines([pt(15.4, 10.4), pt(17.4, 10.6 + open * 0.8), pt(15.2, 11.2)])
        lower.closeSubpath()
        body.fill(lower, with: .color(rgb(0xE0650F)))
        body.fill(upper, with: .color(rgb(0xF27A1A)))
    }

    /// Water flowing past pebbles, reeds swaying on the bank.
    private static func stream(_ ctx: GraphicsContext, _ t: Double) {
        for (x, height) in [(3.0, 7.5), (5.2, 6.0), (22.5, 6.8)] {
            let tip = pt(x + 0.6 * sin(t * 1.6 + x), 10 - height)
            var reed = Path()
            reed.move(to: pt(x, 10.5))
            reed.addQuadCurve(to: tip, control: pt(x, 10 - height * 0.5))
            ctx.stroke(reed, with: .color(rgb(0x5DBB63)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            ctx.fill(Path(roundedRect: CGRect(x: tip.x - 0.7, y: tip.y + 0.4, width: 1.4, height: 2.6), cornerRadius: 0.7),
                     with: .color(rgb(0x8B5A2B)))
        }
        var water = Path()
        water.move(to: pt(0, 20))
        for x in stride(from: 0.0, through: 26, by: 1) { water.addLine(to: pt(x, 9.6 + 0.5 * sin(x * 0.8 - t * 4))) }
        water.addLine(to: pt(26, 20))
        water.closeSubpath()
        ctx.fill(water, with: .linearGradient(Gradient(colors: [rgb(0x4DA6F0), rgb(0x2668B8)]),
                                              startPoint: pt(0, 9), endPoint: pt(0, 20)))
        for (x, y, rx, ry, color) in [(5.0, 18.6, 2.6, 1.5, UInt32(0x9AA3AE)), (13.5, 19.2, 3.2, 1.6, UInt32(0x8A8F99)),
                                      (21.5, 18.4, 2.2, 1.3, UInt32(0xA89A8A))] {
            ctx.fill(oval(pt(x, y), rx, ry), with: .color(rgb(color)))
        }
        for index in 0..<6 {
            let phase = Logic.cycle(t, period: 2.2, offset: Double(index) * 0.17)
            let x = -5 + phase * 36, y = 11.6 + Double(index % 3) * 2.1
            var current = Path()
            current.move(to: pt(x, y))
            current.addQuadCurve(to: pt(x + 4.5, y), control: pt(x + 2.25, y - 0.9))
            var stroke = ctx
            stroke.opacity = 0.7 * Logic.trip(phase)
            stroke.stroke(current, with: .color(.white), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        }
    }

    // MARK: - Noises

    /// White noise: an old television's snow.
    private static func television(_ ctx: GraphicsContext, _ t: Double) {
        let metal = rgb(0xC7CFDB)
        ctx.stroke(line([pt(11, 4.2), pt(8, 0.9)]), with: .color(metal), lineWidth: 0.7)
        ctx.stroke(line([pt(13, 4.2), pt(16.5, 0.7)]), with: .color(metal), lineWidth: 0.7)
        ctx.fill(dot(pt(8, 0.9), 0.7), with: .color(metal))
        ctx.fill(dot(pt(16.5, 0.7), 0.7), with: .color(metal))
        ctx.fill(Path(roundedRect: CGRect(x: 2, y: 4, width: 22, height: 14.5), cornerRadius: 2.6), with: .color(rgb(0x8E9AAD)))
        let screen = CGRect(x: 3.8, y: 5.8, width: 14.2, height: 10.9)
        let glass = Path(roundedRect: screen, cornerRadius: 2)
        ctx.fill(glass, with: .color(rgb(0x1C2026)))
        var snow = ctx
        snow.clip(to: glass)
        let frame = Int((t * 12).truncatingRemainder(dividingBy: 1_000_000))
        let columns = 9, rows = 7
        let width = screen.width / CGFloat(columns), height = screen.height / CGFloat(rows)
        for column in 0..<columns {
            for row in 0..<rows {
                var grain = snow
                grain.opacity = 0.15 + 0.85 * Logic.grain(column: column, row: row, frame: frame)
                grain.fill(Path(CGRect(x: screen.minX + CGFloat(column) * width, y: screen.minY + CGFloat(row) * height,
                                       width: width, height: height).insetBy(dx: 0.15, dy: 0.15)),
                           with: .color(rgb(0xE8EDF5)))
            }
        }
        var band = snow
        band.opacity = 0.18
        band.fill(Path(CGRect(x: screen.minX, y: screen.minY - 3 + Logic.cycle(t, period: 1.8) * (screen.height + 3),
                              width: screen.width, height: 2)), with: .color(.white))
        let knob = rgb(0x5B667A)
        ctx.fill(dot(pt(21, 8.6), 1.3), with: .color(knob))
        ctx.fill(dot(pt(21, 12.4), 1.3), with: .color(knob))
        for y in [15.1, 16.2] { ctx.stroke(line([pt(19.8, y), pt(22.2, y)]), with: .color(knob), lineWidth: 0.5) }
        for x in [5.0, 18.8] {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: 18.3, width: 2.2, height: 1.4), cornerRadius: 0.5), with: .color(rgb(0x6E7A8E)))
        }
    }

    /// Pink noise: a fan turning, a breeze leaving it.
    private static func fan(_ ctx: GraphicsContext, _ t: Double) {
        let frame = rgb(0xF4A6C6)
        let center = pt(13, 8.6)
        ctx.stroke(line([pt(13, 14), pt(13, 18.2)]), with: .color(frame), lineWidth: 1.6)
        ctx.fill(oval(pt(13, 18.8), 4.6, 1.1), with: .color(frame))
        for (lag, alpha) in [(0.44, 0.15), (0.22, 0.35), (0.0, 1.0)] {
            var blades = ctx
            blades.opacity = alpha
            blades.translateBy(x: center.x, y: center.y)
            blades.rotate(by: .radians(t * 7 - lag))
            for index in 0..<3 {
                var blade = blades
                blade.rotate(by: .radians(Double(index) * 2 * .pi / 3))
                blade.fill(oval(pt(0, -3.4), 1.9, 3.1), with: .color(rgb(0xFF8FB8)))
            }
        }
        var spokes = ctx
        spokes.opacity = 0.35
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4
            spokes.stroke(line([pt(center.x + 1.8 * cos(angle), center.y + 1.8 * sin(angle)),
                                pt(center.x + 6.6 * cos(angle), center.y + 6.6 * sin(angle))]),
                          with: .color(rgb(0xFFD1E3)), lineWidth: 0.4)
        }
        ctx.stroke(dot(center, 6.6), with: .color(rgb(0xFFD1E3)), lineWidth: 0.9)
        ctx.fill(dot(center, 1.5), with: .color(.white))
        for index in 0..<2 {
            let phase = Logic.cycle(t, period: 1.2, offset: Double(index) * 0.5)
            let x = 20.5 + phase * 5, y = 6.5 + Double(index) * 4
            var breeze = ctx
            breeze.opacity = 0.8 * Logic.trip(phase)
            breeze.stroke(line([pt(x, y), pt(x + 2.2, y)]), with: .color(.white),
                          style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        }
    }

    /// Brown noise: a plane's window, clouds drifting past at sunset.
    private static func porthole(_ ctx: GraphicsContext, _ t: Double) {
        ctx.fill(Path(roundedRect: CGRect(x: 6, y: 1, width: 14, height: 18), cornerRadius: 6.5), with: .color(rgb(0xC8A27C)))
        let window = CGRect(x: 8, y: 3, width: 10, height: 14)
        let glass = Path(roundedRect: window, cornerRadius: 4.8)
        ctx.fill(glass, with: .linearGradient(Gradient(colors: [rgb(0x3E6FC0), rgb(0x8FB4E6), rgb(0xF4BE7A)]),
                                              startPoint: pt(0, window.minY), endPoint: pt(0, window.maxY)))
        var sky = ctx
        sky.clip(to: glass)
        for index in 0..<3 {
            let phase = Logic.cycle(t, period: 5.5, offset: Double(index) / 3)
            fill(sky, cloud(pt(window.maxX + 4 - phase * (window.width + 9), window.minY + [3.5, 7.5, 11.0][index]), scale: 0.33),
                 Color.white.opacity(0.9))
        }
        var wing = Path()
        wing.addLines([pt(8, 14.2), pt(18, 12.4), pt(18, 13.6), pt(8, 16.6)])
        wing.closeSubpath()
        sky.fill(wing, with: .color(rgb(0xD5DAE2)))
        sky.fill(Path(CGRect(x: window.minX, y: window.minY, width: window.width, height: 2.2)), with: .color(rgb(0xEFE3CF)))
        ctx.stroke(glass, with: .color(rgb(0x9C7752)), lineWidth: 0.8)
        var glint = ctx
        glint.opacity = 0.35
        glint.stroke(line([pt(10, 7.2), pt(11.6, 5.6)]), with: .color(.white), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
    }

    // MARK: - Binaural beats

    /// Alpha: headphones, slow calm waves leaving both sides.
    private static func headphones(_ ctx: GraphicsContext, _ t: Double) {
        var band = Path()
        band.addArc(center: pt(13, 12), radius: 7, startAngle: .degrees(195), endAngle: .degrees(345), clockwise: false)
        ctx.stroke(band, with: .color(rgb(0xA9B4FF)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        for side in [-1.0, 1.0] {
            for index in 0..<2 {
                let phase = Logic.cycle(t, period: 2.4, offset: Double(index) * 0.5)
                var wave = Path()
                wave.addArc(center: pt(13 + side * 8.6, 14), radius: 1.5 + phase * 3.6,
                            startAngle: .degrees(side < 0 ? 140 : -40), endAngle: .degrees(side < 0 ? 220 : 40), clockwise: false)
                var stroke = ctx
                stroke.opacity = 0.9 * Logic.trip(phase)
                stroke.stroke(wave, with: .color(rgb(0xC9D0FF)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            }
            let x = 13 + side * 6.6 - 1.7
            ctx.fill(Path(roundedRect: CGRect(x: x, y: 10.6, width: 3.4, height: 6.6), cornerRadius: 1.5), with: .color(rgb(0x7B88F0)))
            ctx.fill(Path(roundedRect: CGRect(x: x + (side < 0 ? 2.4 : -0.4), y: 11.4, width: 1.4, height: 5), cornerRadius: 0.6),
                     with: .color(rgb(0x5A64C8)))
        }
    }

    /// Beta: a light bulb glowing, its rays pulsing.
    private static func bulb(_ ctx: GraphicsContext, _ t: Double) {
        let pulse = 0.5 + 0.5 * sin(t * 4.2)
        let light = rgb(0xFFE27A)
        halo(ctx, pt(13, 8), 9 + 1.2 * pulse, light, 0.35 + 0.3 * pulse)
        var rays = ctx
        rays.opacity = 0.6 + 0.4 * pulse
        for index in 0..<5 {
            let angle = (200 + 35 * Double(index)) * .pi / 180
            let length = 1.4 + 0.9 * (0.5 + 0.5 * sin(t * 4.2 + Double(index) * 0.9))
            rays.stroke(line([pt(13 + 6.6 * cos(angle), 8 + 6.6 * sin(angle)),
                              pt(13 + (6.6 + length) * cos(angle), 8 + (6.6 + length) * sin(angle))]),
                        with: .color(light), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        }
        let glass = rgb(0xFFF2B0)
        ctx.fill(dot(pt(13, 8), 4.9), with: .color(glass))
        var neck = Path()
        neck.move(to: pt(9.2, 10.6))
        neck.addQuadCurve(to: pt(10.8, 13.2), control: pt(10.6, 12))
        neck.addLine(to: pt(15.2, 13.2))
        neck.addQuadCurve(to: pt(16.8, 10.6), control: pt(15.4, 12))
        neck.closeSubpath()
        ctx.fill(neck, with: .color(glass))
        var filament = Path()
        filament.addLines([pt(11.6, 12.6), pt(11.6, 9.4), pt(12.2, 8.4), pt(12.8, 9.4), pt(13.4, 8.4), pt(14, 9.4),
                           pt(14.4, 9.4), pt(14.4, 12.6)])
        ctx.stroke(filament, with: .color(rgb(0xFF9F1C).opacity(0.7 + 0.3 * pulse)), lineWidth: 0.6)
        ctx.fill(Path(roundedRect: CGRect(x: 10.6, y: 13, width: 4.8, height: 4), cornerRadius: 0.9), with: .color(rgb(0xB9BEC9)))
        for y in [14.3, 15.6] { ctx.stroke(line([pt(10.8, y), pt(15.2, y)]), with: .color(rgb(0x8B93A3)), lineWidth: 0.5) }
        ctx.fill(Path(roundedRect: CGRect(x: 12, y: 17, width: 2, height: 1.3), cornerRadius: 0.6), with: .color(rgb(0x6E7686)))
    }

    /// Gamma: an atom, quick electrons round three orbits.
    private static func atom(_ ctx: GraphicsContext, _ t: Double) {
        let center = pt(13, 10)
        let electron = rgb(0x7FE7FF)
        for (index, tilt) in [0, Double.pi / 3, 2 * Double.pi / 3].enumerated() {
            var orbit = ctx
            orbit.translateBy(x: center.x, y: center.y)
            orbit.rotate(by: .radians(tilt))
            var path = orbit
            path.opacity = 0.55
            path.stroke(oval(.zero, 9.6, 3.4), with: .color(rgb(0xB38CFF)), lineWidth: 0.8)
            let angle = t * 3.4 + Double(index) * 2.1
            for step in 1...3 {
                let behind = angle - Double(step) * 0.18
                var trail = orbit
                trail.opacity = 0.5 - 0.15 * Double(step)
                trail.fill(dot(pt(9.6 * cos(behind), 3.4 * sin(behind)), 1 - 0.18 * Double(step)), with: .color(electron))
            }
            orbit.fill(dot(pt(9.6 * cos(angle), 3.4 * sin(angle)), 1.15), with: .color(electron))
        }
        let core = rgb(0xFF7AD9)
        halo(ctx, center, 4.2, core, 0.55 + 0.25 * sin(t * 6))
        ctx.fill(dot(center, 1.9), with: .color(core))
    }

    // MARK: - Music

    /// Chords: a record turning, notes floating off it.
    private static func vinyl(_ ctx: GraphicsContext, _ t: Double) {
        let center = pt(10, 11)
        let record = rgb(0x23252B)
        ctx.fill(dot(center, 7.8), with: .color(record))
        for radius in [6.4, 5.2] { ctx.stroke(dot(center, radius), with: .color(rgb(0x3A3D45)), lineWidth: 0.45) }
        var sheen = ctx
        sheen.opacity = 0.4
        for turn in [0, Double.pi] {
            var arc = Path()
            arc.addArc(center: center, radius: 5.8, startAngle: .radians(t * 3.3 + turn),
                       endAngle: .radians(t * 3.3 + turn + 0.9), clockwise: false)
            sheen.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        }
        ctx.fill(dot(center, 2.5), with: .color(rgb(0xFF8A5B)))
        ctx.fill(dot(center, 0.5), with: .color(record))
        ctx.stroke(line([pt(24.5, 3), pt(23.2, 10), pt(17, 12.5)]), with: .color(rgb(0xC7CFDB)),
                   style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
        ctx.fill(dot(pt(24.5, 3), 1.2), with: .color(rgb(0x9AA6B8)))
        ctx.fill(Path(roundedRect: CGRect(x: 16.2, y: 11.9, width: 1.8, height: 1.2), cornerRadius: 0.4), with: .color(rgb(0x9AA6B8)))
        for index in 0..<2 {
            let phase = Logic.cycle(t, period: 2.2, offset: Double(index) * 0.5)
            var song = ctx
            song.opacity = Logic.trip(phase)
            note(song, at: pt(17.5 + phase * 4 + sin(phase * 7) * 0.9, 10 - phase * 9), size: 0.9, color: rgb(0xFFD27A))
        }
    }

    /// Drone: one long tone, a slow swelling wave and its overtone.
    private static func drone(_ ctx: GraphicsContext, _ t: Double) {
        let swell = 0.75 + 0.25 * sin(t * 0.7)
        func wave(_ amplitude: Double, _ frequency: Double, _ phase: Double) -> Path {
            var path = Path()
            for step in 0...52 {
                let x = Double(step) * 0.5
                let point = pt(x, 10 + amplitude * sin(x * frequency - phase))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            return path
        }
        let tone = rgb(0x6FE3C1)
        let main = wave(4.2 * swell, 0.36, t * 1.3)
        var glow = ctx
        glow.opacity = 0.22
        glow.stroke(main, with: .color(tone), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        var overtone = ctx
        overtone.opacity = 0.45
        overtone.stroke(wave(2.1, 0.72, t * 2 - 1), with: .color(rgb(0x9AD8FF)), lineWidth: 0.8)
        ctx.stroke(main, with: .color(tone), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        let x = Logic.cycle(t, period: 3.6) * 26
        ctx.fill(dot(pt(x, 10 + 4.2 * swell * sin(x * 0.36 - t * 1.3)), 1.1), with: .color(.white))
    }

    /// Singing bowls: a golden bowl, rings of sound rising from its rim.
    private static func bowl(_ ctx: GraphicsContext, _ t: Double) {
        let gold = rgb(0xF5CF7A)
        for index in 0..<3 {
            let phase = Logic.cycle(t, period: 2.8, offset: Double(index) / 3)
            var ring = ctx
            ring.opacity = 0.8 * (1 - phase) * min(1, phase * 6)
            ring.stroke(oval(pt(13, 12.6 - phase * 7), 7.6 + phase * 4.4, 1.5 + phase * 2.2), with: .color(gold), lineWidth: 0.85)
        }
        var bowl = Path()
        bowl.move(to: pt(4.8, 12.6))
        bowl.addCurve(to: pt(13, 19.4), control1: pt(5.2, 17), control2: pt(9, 19.4))
        bowl.addCurve(to: pt(21.2, 12.6), control1: pt(17, 19.4), control2: pt(20.8, 17))
        bowl.closeSubpath()
        ctx.fill(bowl, with: .linearGradient(Gradient(colors: [rgb(0xF0B850), rgb(0xA8742A)]),
                                             startPoint: pt(0, 12.6), endPoint: pt(0, 19.4)))
        ctx.fill(oval(pt(13, 12.6), 8.2, 1.7), with: .color(rgb(0xF7D88C)))
        ctx.fill(oval(pt(13, 12.8), 6.9, 1.1), with: .color(rgb(0x7A5320)))
        var glint = ctx
        glint.opacity = 0.45
        var shine = Path()
        shine.move(to: pt(7, 14.6))
        shine.addQuadCurve(to: pt(9, 17.4), control: pt(7.4, 16.6))
        glint.stroke(shine, with: .color(.white), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
    }

    // MARK: - Pieces

    /// An eighth note, its head at `point`.
    private static func note(_ ctx: GraphicsContext, at point: CGPoint, size: CGFloat, color: Color) {
        var glyph = ctx
        glyph.translateBy(x: point.x, y: point.y)
        glyph.scaleBy(x: size, y: size)
        var head = glyph
        head.rotate(by: .radians(-0.35))
        head.fill(oval(.zero, 1.35, 1), with: .color(color))
        glyph.stroke(line([pt(1.15, -0.3), pt(1.15, -4.6)]), with: .color(color), lineWidth: 0.6)
        var flag = Path()
        flag.move(to: pt(1.15, -4.6))
        flag.addQuadCurve(to: pt(2.9, -2.4), control: pt(2.9, -3.8))
        glyph.stroke(flag, with: .color(color), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
    }

    /// A cloud as overlapping pieces, filled one by one (an opaque colour
    /// hides the overlaps).
    private static func cloud(_ center: CGPoint, scale: CGFloat = 1) -> [Path] {
        [
            dot(pt(center.x - 5 * scale, center.y + 0.8 * scale), 3.6 * scale),
            dot(pt(center.x - 0.5 * scale, center.y - 1.6 * scale), 4.8 * scale),
            dot(pt(center.x + 4.6 * scale, center.y + 0.4 * scale), 3.9 * scale),
            Path(roundedRect: CGRect(x: center.x - 7.5 * scale, y: center.y, width: 15.5 * scale, height: 4.4 * scale),
                 cornerRadius: 2.2 * scale),
        ]
    }

    /// A band of sea under a sine wave.
    private static func sea(base: Double, amplitude: Double, frequency: Double, phase: Double) -> Path {
        var path = crest(base: base, amplitude: amplitude, frequency: frequency, phase: phase)
        path.addLine(to: pt(26, 20))
        path.addLine(to: pt(0, 20))
        path.closeSubpath()
        return path
    }

    private static func crest(base: Double, amplitude: Double, frequency: Double, phase: Double) -> Path {
        var path = Path()
        for step in 0...26 {
            let x = Double(step)
            let point = pt(x, base + amplitude * sin(x * frequency + phase))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// A flame rising from `base`, its tip swaying.
    private static func flame(base: CGPoint, width: CGFloat, height: CGFloat, sway: CGFloat) -> Path {
        let tip = pt(base.x + sway, base.y - height)
        var path = Path()
        path.move(to: pt(base.x - width / 2, base.y))
        path.addCurve(to: tip, control1: pt(base.x - width / 2, base.y - height * 0.45),
                      control2: pt(tip.x - width * 0.1, tip.y + height * 0.35))
        path.addCurve(to: pt(base.x + width / 2, base.y), control1: pt(tip.x + width * 0.1, tip.y + height * 0.35),
                      control2: pt(base.x + width / 2, base.y - height * 0.45))
        path.addQuadCurve(to: pt(base.x - width / 2, base.y), control: pt(base.x, base.y + width * 0.4))
        path.closeSubpath()
        return path
    }

    /// A soft glow fading out from `center`.
    private static func halo(_ ctx: GraphicsContext, _ center: CGPoint, _ radius: CGFloat, _ color: Color, _ strength: Double) {
        var glow = ctx
        glow.opacity = min(1, max(0, strength))
        glow.fill(dot(center, radius), with: .radialGradient(Gradient(colors: [color, color.opacity(0)]),
                                                              center: center, startRadius: 0, endRadius: radius))
    }

    private static func fill(_ ctx: GraphicsContext, _ parts: [Path], _ color: Color) {
        for part in parts { ctx.fill(part, with: .color(color)) }
    }

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static func dot(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }

    private static func oval(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: 2 * rx, height: 2 * ry))
    }

    private static func line(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    /// Between two colours, `share` of the way from the first.
    private static func blend(_ from: UInt32, _ to: UInt32, _ share: Double) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let a = Double(from >> shift & 0xFF), b = Double(to >> shift & 0xFF)
            return (a + (b - a) * min(1, max(0, share))) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0), opacity: 1)
    }
}
