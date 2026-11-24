// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Lot 9j: each tool of the Care window over a picture of what it does,
/// brought to life by motion drawn on top of it: the radar sweeps and its
/// three checks orbit, dust drifts and a wave clears it, a scan line crosses
/// the shield, light streams through the gauge, a tile dissolves, blocks of
/// the disk light up. Calm at rest, livelier while the tool works. The
/// pictures were made for Hublot (Fork/Resources/Care); the motion is drawn
/// here. Still with Reduce Motion, paused while the window is hidden. The
/// numbers are `ForkCareMotionLogic`'s.
enum ForkCareHubArt {
    private static var cache: [ForkCareHubLogic.Module: NSImage] = [:]

    static func image(_ module: ForkCareHubLogic.Module) -> NSImage? {
        if let cached = cache[module] { return cached }
        guard let url = Bundle.main.url(forResource: module.rawValue, withExtension: "jpg", subdirectory: "ForkCare"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[module] = image
        return image
    }
}

private struct ForkCareHubWorkingKey: EnvironmentKey { static let defaultValue = false }
private struct ForkCareHubVisibleKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// The tool shown in the Care window is working: its background livens up.
    var forkCareHubWorking: Bool {
        get { self[ForkCareHubWorkingKey.self] }
        set { self[ForkCareHubWorkingKey.self] = newValue }
    }

    /// The Care window can be seen: its backgrounds move only then.
    var forkCareHubVisible: Bool {
        get { self[ForkCareHubVisibleKey.self] }
        set { self[ForkCareHubVisibleKey.self] = newValue }
    }
}

extension ForkCareHubLogic.Module {
    init(tool: ForkCareLogic.Tool) {
        switch tool {
        case .smartScan: self = .smartScan
        case .antivirus: self = .protection
        case .maintenance: self = .performance
        case .diskMap: self = .diskMap
        case .ambient: self = .smartScan
        }
    }
}

/// The motion's clock lives across frames; a class so the drawing can move it on.
private final class ForkCareHubClockBox {
    var clock = ForkCareMotionLogic.Clock()
}

struct ForkCareHubBackdrop: View {
    let module: ForkCareHubLogic.Module
    let working: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.forkCareHubVisible) private var visible
    @State private var box = ForkCareHubClockBox()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !visible)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                if !reduceMotion { box.clock.advance(to: now, working: working) }
                let phase = box.clock.phase
                let energy = box.clock.energy
                ForkCareHubPainter.picture(module, context, size, time: reduceMotion ? 0 : now)
                guard !reduceMotion else { return }
                ForkCareHubPainter.motion(module, context, size, phase: phase, energy: energy)
            }
        }
        .overlay(
            // Keeps the tool's white text readable over the brightest parts.
            RadialGradient(colors: [.black.opacity(0.18), .black.opacity(0.42)], center: .center, startRadius: 120, endRadius: 760)
        )
        .background(Color(care: ForkCareLogic.gradient(module.tool ?? .smartScan).bottom))
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A band of the tool's picture above upstream's pages (Cleanup, Applications),
/// whose lists need a plain background to stay readable.
struct ForkCareHubBanner: View {
    let module: ForkCareHubLogic.Module
    let working: Bool

    var body: some View {
        let text = ForkCareHubStrings.current
        ZStack(alignment: .bottomLeading) {
            ForkCareHubBackdrop(module: module, working: working)
            LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(text.name(module)).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                Text(text.purpose(module)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.82))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
        }
        .frame(height: 168)
        .clipped()
    }
}

// MARK: - Drawing

private enum ForkCareHubPainter {
    typealias Logic = ForkCareMotionLogic
    typealias Module = ForkCareHubLogic.Module

    static func rgb(_ hex: UInt32, _ opacity: Double) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: max(0, min(1, opacity)))
    }

    /// The picture, slightly larger than the window and drifting slowly.
    static func picture(_ module: Module, _ context: GraphicsContext, _ size: CGSize, time: Double) {
        guard let image = ForkCareHubArt.image(module) else { return }
        let rect = Logic.fillRect(in: size)
        let scale = 1.05
        let drift = CGSize(width: sin(time * 0.05) * 10, height: cos(time * 0.04) * 6)
        let drawn = CGRect(x: rect.midX - rect.width * scale / 2 + drift.width,
                           y: rect.midY - rect.height * scale / 2 + drift.height,
                           width: rect.width * scale, height: rect.height * scale)
        context.draw(Image(nsImage: image), in: drawn)
    }

    static func motion(_ module: Module, _ context: GraphicsContext, _ size: CGSize, phase: Double, energy: Double) {
        let rect = Logic.fillRect(in: size)
        switch module {
        case .smartScan: radar(context, size, rect, phase, energy)
        case .cleanup: cleaning(context, size, phase, energy)
        case .protection: shield(context, size, rect, phase, energy)
        case .performance: flow(context, size, rect, phase, energy)
        case .applications: dissolve(context, size, rect, phase, energy)
        case .diskMap: blocks(context, size, phase, energy)
        }
    }

    // The radar sweeps; the three checks (cleaning, protection, performance) orbit.
    private static func radar(_ context: GraphicsContext, _ size: CGSize, _ rect: CGRect, _ phase: Double, _ energy: Double) {
        let centre = Logic.point(CGPoint(x: 0.5, y: 0.47), in: rect)
        let radius = rect.height * 0.41
        let angle = phase * 0.9
        let slices = 22
        for index in 0..<slices {
            let end = angle - Double(index) * 0.04
            var wedge = Path()
            wedge.move(to: centre)
            wedge.addArc(center: centre, radius: radius, startAngle: .radians(end - 0.04), endAngle: .radians(end), clockwise: false)
            wedge.closeSubpath()
            let fade = 1 - Double(index) / Double(slices)
            context.fill(wedge, with: .color(rgb(0x22D3EE, 0.20 * fade * fade * (0.55 + 0.45 * energy))))
        }
        var edge = Path()
        edge.move(to: centre)
        edge.addLine(to: CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius))
        context.stroke(edge, with: .color(rgb(0x67E8F9, 0.55)), lineWidth: 1.2)

        let orbits: [(rx: Double, ry: Double, speed: Double, colour: UInt32, offset: Double)] = [
            (0.98, 0.44, 0.42, 0xF472B6, 0.4), (0.74, 0.31, -0.31, 0x34D399, 2.1), (1.14, 0.56, 0.24, 0x60A5FA, 4.0),
        ]
        for orbit in orbits {
            let rx = radius * orbit.rx, ry = radius * orbit.ry
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - rx, y: centre.y - ry, width: rx * 2, height: ry * 2)),
                           with: .color(rgb(orbit.colour, 0.10)), lineWidth: 1)
            let a = phase * orbit.speed + orbit.offset
            let spot = CGPoint(x: centre.x + cos(a) * rx, y: centre.y + sin(a) * ry)
            glow(context, at: spot, radius: 7, colour: orbit.colour, strength: 0.75)
        }
        particles(context, size, count: 46, colour: 0xA5F3FC, phase: phase, rise: 6, seed: 10)
    }

    // Dust and bubbles drift; a wave of light crosses and clears the dust behind it.
    private static func cleaning(_ context: GraphicsContext, _ size: CGSize, _ phase: Double, _ energy: Double) {
        let period = 9 - 5 * energy
        let sweep = Logic.sweep(phase: phase, period: period, crossing: 3)
        let bandX = sweep.map { -0.2 * size.width + $0 * 1.4 * size.width }
        for index in 0..<110 {
            let n1 = Logic.noise(index), n2 = Logic.noise(index + 500), n3 = Logic.noise(index + 900)
            let x = n1 * size.width + sin(phase * 0.3 + Double(index)) * 14
            var y = n2 * size.height - phase * 9 * (0.4 + n3)
            y = y.truncatingRemainder(dividingBy: size.height)
            if y < 0 { y += size.height }
            var alpha = 0.22 + 0.5 * n3
            if let bandX {
                let behind = bandX - x
                if behind > 0 { alpha *= max(0.08, 1 - behind / (size.width * 0.35)) }
                if abs(behind) < 40 { alpha = min(1, alpha + 0.5) }
            }
            let r = 0.8 + n3 * 1.8
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(rgb(0xFBCFE8, alpha)))
        }
        for index in 0..<11 {
            let n1 = Logic.noise(index + 40), n2 = Logic.noise(index + 80)
            let r = 9 + n2 * 20
            let x = n1 * size.width + sin(phase * 0.5 + Double(index) * 1.7) * 18
            var y = (1 - n2) * size.height - phase * 14 * (0.5 + n1)
            y = y.truncatingRemainder(dividingBy: size.height + 2 * r)
            if y < -r { y += size.height + 2 * r }
            let bubble = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: bubble), with: .color(rgb(0xF9A8D4, 0.05)))
            context.stroke(Path(ellipseIn: bubble), with: .color(rgb(0xFFFFFF, 0.30)), lineWidth: 1)
            var shine = Path()
            shine.addArc(center: CGPoint(x: x, y: y), radius: r * 0.7, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
            context.stroke(shine, with: .color(rgb(0xFFFFFF, 0.55)), lineWidth: 1.4)
        }
        if let bandX {
            var layer = context
            layer.addFilter(.blur(radius: 34))
            layer.fill(Path(CGRect(x: bandX - 50, y: -40, width: 100, height: size.height + 80)),
                       with: .color(rgb(0xF472B6, 0.30 + 0.15 * energy)))
        }
    }

    // A scan line crosses the shield; cells light up as it passes.
    private static func shield(_ context: GraphicsContext, _ size: CGSize, _ rect: CGRect, _ phase: Double, _ energy: Double) {
        let travel = (phase * 0.11).truncatingRemainder(dividingBy: 1.25) - 0.1
        let lineY = rect.minY + travel * rect.height
        let cell = 34.0
        let columns = Int(size.width / (cell * 1.5)) + 2, rows = Int(size.height / (cell * 0.866)) + 2
        let tick = floor(phase * 0.6)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = Double(column) * cell * 1.5 + (row % 2 == 0 ? 0 : cell * 0.75)
                let y = Double(row) * cell * 0.866
                let id = row * 1_000 + column
                let near = max(0, 1 - abs(y - lineY) / 70)
                let lit = Logic.noise(id + Int(tick) * 7_919) > 0.965 - 0.02 * energy
                guard near > 0.05 || lit else { continue }
                let pulse = lit ? 0.5 + 0.5 * sin(phase * 2 + Double(id)) : 0
                let alpha = 0.16 * near + 0.18 * pulse
                context.fill(hexagon(CGPoint(x: x, y: y), cell * 0.47), with: .color(rgb(0x34D399, alpha)))
            }
        }
        var layer = context
        layer.addFilter(.blur(radius: 5))
        layer.fill(Path(CGRect(x: 0, y: lineY - 1.5, width: size.width, height: 3)), with: .color(rgb(0x6EE7B7, 0.85)))
        context.fill(Path(CGRect(x: 0, y: lineY - 0.5, width: size.width, height: 1)), with: .color(rgb(0xD1FAE5, 0.9)))
        particles(context, size, count: 30, colour: 0xA7F3D0, phase: phase, rise: 4, seed: 30)
    }

    // Light streams through; the gauge rises while maintenance works.
    private static func flow(_ context: GraphicsContext, _ size: CGSize, _ rect: CGRect, _ phase: Double, _ energy: Double) {
        let span = size.width + 320
        for index in 0..<52 {
            let n1 = Logic.noise(index + 300), n2 = Logic.noise(index + 600), n3 = Logic.noise(index + 700)
            let length = 70 + n3 * 200
            var head = n1 * span + phase * 140 * (0.45 + n2)
            head = head.truncatingRemainder(dividingBy: span) - 160
            let baseY = Logic.noise(index) * size.height
            let colour: UInt32 = index % 4 == 0 ? 0xE0F2FE : 0x60A5FA
            for segment in 0..<4 {
                let x0 = head - length * Double(segment + 1) / 4, x1 = head - length * Double(segment) / 4
                var path = Path()
                path.move(to: CGPoint(x: x0, y: baseY + sin(x0 / 170 + Double(index)) * 16))
                path.addLine(to: CGPoint(x: x1, y: baseY + sin(x1 / 170 + Double(index)) * 16))
                context.stroke(path, with: .color(rgb(colour, (0.42 - 0.1 * Double(segment)) * (0.6 + 0.4 * n2))),
                               lineWidth: 1 + n3 * 1.6)
            }
        }
        let centre = Logic.point(CGPoint(x: 0.5, y: 1.02), in: rect)
        let radius = rect.height * 0.25
        let fill = 0.28 + 0.6 * energy + 0.04 * sin(phase)
        var arc = Path()
        arc.addArc(center: centre, radius: radius, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * fill), clockwise: false)
        var layer = context
        layer.addFilter(.blur(radius: 6))
        layer.stroke(arc, with: .color(rgb(0x60A5FA, 0.8)), lineWidth: 7)
        context.stroke(arc, with: .color(rgb(0xBFDBFE, 0.9)), lineWidth: 2.5)
    }

    // Tiles float in the warm light; now and then one dissolves into embers.
    private static func dissolve(_ context: GraphicsContext, _ size: CGSize, _ rect: CGRect, _ phase: Double, _ energy: Double) {
        for index in 0..<9 {
            let n1 = Logic.noise(index + 120), n2 = Logic.noise(index + 160)
            let r = 40 + n2 * 70
            let spot = CGPoint(x: n1 * size.width + sin(phase * 0.12 + Double(index)) * 30,
                               y: n2 * size.height + cos(phase * 0.1 + Double(index)) * 20)
            var layer = context
            layer.addFilter(.blur(radius: 26))
            layer.fill(Path(ellipseIn: CGRect(x: spot.x - r, y: spot.y - r, width: r * 2, height: r * 2)),
                       with: .color(rgb(0xFB923C, 0.07)))
        }
        let period = 4.2 - 1.8 * energy
        let burst = Int(phase / period)
        let life = (phase.truncatingRemainder(dividingBy: period)) / period
        let column = Int(Logic.noise(burst) * 5), row = Int(Logic.noise(burst + 77) * 3)
        let tile = Logic.point(CGPoint(x: 0.135 + Double(column) * 0.18, y: 0.24 + Double(row) * 0.29), in: rect)
        for index in 0..<70 {
            let n1 = Logic.noise(burst * 100 + index), n2 = Logic.noise(burst * 100 + index + 50)
            let angle = -Double.pi / 2 + (n1 - 0.5) * 2.2
            let distance = life * (40 + n2 * 150)
            let spot = CGPoint(x: tile.x + (n1 - 0.5) * 60 + cos(angle) * distance,
                               y: tile.y + (n2 - 0.5) * 60 + sin(angle) * distance)
            let alpha = (1 - life) * (0.4 + 0.6 * n2)
            context.fill(Path(CGRect(x: spot.x, y: spot.y, width: 2.2, height: 2.2)), with: .color(rgb(0xFDBA74, alpha)))
        }
        particles(context, size, count: 26, colour: 0xFED7AA, phase: phase, rise: 10, seed: 60)
    }

    // A light passes over the map; blocks light up as they are measured.
    private static func blocks(_ context: GraphicsContext, _ size: CGSize, _ phase: Double, _ energy: Double) {
        let travel = (phase * 0.09).truncatingRemainder(dividingBy: 1.4) - 0.2
        var layer = context
        layer.addFilter(.blur(radius: 44))
        var band = Path()
        let x = travel * (size.width + size.height)
        band.move(to: CGPoint(x: x, y: -20))
        band.addLine(to: CGPoint(x: x + 140, y: -20))
        band.addLine(to: CGPoint(x: x + 140 - size.height, y: size.height + 20))
        band.addLine(to: CGPoint(x: x - size.height, y: size.height + 20))
        band.closeSubpath()
        layer.fill(band, with: .color(rgb(0xA78BFA, 0.20 + 0.10 * energy)))
        let cell = 24.0
        let tick = floor(phase * 1.1)
        for row in 0..<Int(size.height / cell) + 1 {
            for column in 0..<Int(size.width / cell) + 1 {
                let id = row * 1_000 + column
                guard Logic.noise(id + Int(tick) * 131) > 0.972 - 0.03 * energy else { continue }
                let pulse = 0.5 + 0.5 * sin(phase * 3 + Double(id))
                let square = CGRect(x: Double(column) * cell + 3, y: Double(row) * cell + 3, width: cell - 6, height: cell - 6)
                context.fill(Path(roundedRect: square, cornerRadius: 3), with: .color(rgb(0xC4B5FD, 0.12 + 0.3 * pulse)))
            }
        }
    }

    // MARK: Shared pieces

    private static func glow(_ context: GraphicsContext, at spot: CGPoint, radius: Double, colour: UInt32, strength: Double) {
        var layer = context
        layer.addFilter(.blur(radius: radius * 1.6))
        layer.fill(Path(ellipseIn: CGRect(x: spot.x - radius * 1.8, y: spot.y - radius * 1.8, width: radius * 3.6, height: radius * 3.6)),
                   with: .color(rgb(colour, strength * 0.7)))
        context.fill(Path(ellipseIn: CGRect(x: spot.x - radius * 0.6, y: spot.y - radius * 0.6, width: radius * 1.2, height: radius * 1.2)),
                     with: .color(rgb(0xFFFFFF, 0.9)))
    }

    /// Fine particles rising and twinkling.
    private static func particles(_ context: GraphicsContext, _ size: CGSize, count: Int, colour: UInt32,
                                  phase: Double, rise: Double, seed: Int) {
        for index in 0..<count {
            let n1 = Logic.noise(seed * 1_000 + index), n2 = Logic.noise(seed * 1_000 + index + 400)
            var y = n2 * size.height - phase * rise * (0.5 + n1)
            y = y.truncatingRemainder(dividingBy: size.height)
            if y < 0 { y += size.height }
            let x = n1 * size.width + sin(phase * 0.4 + Double(index)) * 8
            let twinkle = 0.25 + 0.55 * (0.5 + 0.5 * sin(phase * 2.3 + Double(index) * 1.3))
            context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(rgb(colour, twinkle)))
        }
    }

    private static func hexagon(_ centre: CGPoint, _ radius: Double) -> Path {
        var path = Path()
        for corner in 0..<6 {
            let angle = Double.pi / 3 * Double(corner)
            let spot = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
            if corner == 0 { path.move(to: spot) } else { path.addLine(to: spot) }
        }
        path.closeSubpath()
        return path
    }
}
