// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Lots 9e and 9h: the pieces the fork's cleaning tools share (see
/// `ForkCareLogic` and `ForkCareMotion`). One step per screen: a floating
/// symbol, a title, one sentence and a single round button that breathes;
/// the work under way turns a ring around it; a summary closes it, its tick
/// drawing itself. Everything here is drawn by the fork; nothing comes from
/// another app. Every loop stops with Reduce Motion.

/// A tool's window: light or dark with the system, its title bar
/// see-through over the background, and its size its own. The hosting view's sizing options stay empty, as
/// for upstream's Settings window, or SwiftUI's minimum size of the content,
/// measured at its narrowest, would stretch the window (lot 9d's maintenance
/// window once opened 8,599 points high).
enum ForkCareWindow {
    static func make<Content: View>(title: String, size: NSSize, minSize: NSSize, content: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        window.contentView = host
        window.minSize = minSize
        window.center()
        return window
    }
}

/// Which tool a view belongs to, for the button's colours and its light.
private struct ForkCareToolKey: EnvironmentKey {
    static let defaultValue = ForkCareLogic.Tool.smartScan
}

extension EnvironmentValues {
    var forkCareTool: ForkCareLogic.Tool {
        get { self[ForkCareToolKey.self] }
        set { self[ForkCareToolKey.self] = newValue }
    }
}

extension Color {
    init(care colour: ForkCareLogic.RGB) {
        self.init(red: colour.red, green: colour.green, blue: colour.blue)
    }

    /// A colour that follows the window's appearance, light or dark.
    static func care(dark: ForkCareLogic.RGB, darkOpacity: Double = 1,
                     light: ForkCareLogic.RGB, lightOpacity: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let colour = isDark ? dark : light
            return NSColor(srgbRed: colour.red, green: colour.green, blue: colour.blue,
                           alpha: isDark ? darkOpacity : lightOpacity)
        })
    }

    /// Text on a tool's background and its cards: white on dark, near-black
    /// on light; the secondary one dimmer. Contrast checked in the tests.
    static let carePrimary = care(dark: .white, light: ForkCareLogic.lightPrimary)
    static let careSecondary = care(dark: .white, darkOpacity: ForkCareLogic.secondaryOpacity,
                                    light: ForkCareLogic.lightSecondary)

    /// An edge or a hairline: white on dark, a touch of near-black on light.
    static func careVeil(_ opacity: Double) -> Color {
        care(dark: .white, darkOpacity: opacity, light: ForkCareLogic.lightPrimary, lightOpacity: opacity * 0.6)
    }

    /// A card's or a tile's fill: white at `opacity` on dark; on light, white
    /// from the cards' tested opacity up, so a chosen tile still stands out.
    static func careFill(_ opacity: Double) -> Color {
        let light = min(1, ForkCareLogic.lightCardOpacity + (opacity - ForkCareLogic.cardOpacity) * 2.5)
        return care(dark: .white, darkOpacity: opacity, light: .white, lightOpacity: max(0.4, light))
    }

    static func careAccent(_ category: ForkCareLogic.Category) -> Color {
        care(dark: ForkCareLogic.accent(category), light: ForkCareLogic.lightAccent(category))
    }

    /// The tool's hue for a symbol or a figure, readable on either background.
    static func careTint(_ tool: ForkCareLogic.Tool) -> Color {
        care(dark: ForkCareLogic.tint(tool, dark: true), light: ForkCareLogic.tint(tool, dark: false))
    }
}

/// The tool's gradient, with a faint light drifting slowly across the top.
struct ForkCareBackground: View {
    let tool: ForkCareLogic.Tool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.forkInCareHub) private var inCareHub
    @Environment(\.forkCareHubWorking) private var working
    @State private var drifted = false

    var body: some View {
        if inCareHub {
            // Lot 9j: the tool's animated picture inside the Care window.
            ForkCareHubBackdrop(module: ForkCareHubLogic.Module(tool: tool), working: working)
        } else {
            gradient
        }
    }

    @ViewBuilder private var gradient: some View {
        let dark = scheme == .dark
        let stops = dark ? ForkCareLogic.gradient(tool) : ForkCareLogic.lightGradient(tool)
        LinearGradient(colors: [Color(care: stops.top), Color(care: stops.bottom)], startPoint: .top, endPoint: .bottom)
            .overlay(
                RadialGradient(colors: [Color(care: ForkCareLogic.glow(tool)).opacity(dark ? 0.16 : 0.24), .clear],
                               center: UnitPoint(x: drifted ? 0.75 : 0.25, y: drifted ? 0.12 : 0),
                               startRadius: 0, endRadius: 480)
            )
            .overlay(RadialGradient(colors: [Color.white.opacity(dark ? 0.06 : 0.4), .clear], center: .top,
                                    startRadius: 0, endRadius: 420))
            .ignoresSafeArea()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: ForkCareMotion.drift).repeatForever(autoreverses: true)) { drifted = true }
            }
    }
}

/// The large symbol, the title and the sentence that open each screen. The
/// symbol floats gently in its circle of light.
struct ForkCareHero: View {
    let symbol: String
    let title: String
    let subtitle: String
    var tint: Color = .carePrimary
    @Environment(\.forkCareTool) private var tool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        let glow = Color(care: ForkCareLogic.glow(tool))
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 108, height: 108)
                .background(
                    Circle().fill(RadialGradient(colors: [glow.opacity(0.35), Color.white.opacity(0.06)],
                                                 center: .center, startRadius: 4, endRadius: 60))
                )
                .overlay(Circle().stroke(Color.careVeil(0.16), lineWidth: 1))
                .shadow(color: glow.opacity(0.35), radius: 18)
                .offset(y: floating ? -4 : 4)
                .accessibilityHidden(true)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: ForkCareMotion.float / 2).repeatForever(autoreverses: true)) {
                        floating = true
                    }
                }
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.carePrimary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Color.careSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The single round button of a screen: a bright gradient of the tool's hue
/// whose light breathes while it waits. While work runs, a ring goes round
/// it, filled to `progress` when the length is known, turning with a trail
/// otherwise, and pulses leave it.
struct ForkCareRoundButton: View {
    let title: String
    var working = false
    var progress: Double?
    var enabled = true
    /// 128 points in the windows; smaller where room is short, as in a panel.
    var diameter: CGFloat = 128
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: max(13, 17 * diameter / 128), weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(diameter / 9)
                .frame(width: diameter, height: diameter)
        }
        .buttonStyle(ForkCareRoundStyle(working: working, progress: progress))
        .disabled(!enabled || working)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(title)
        .accessibilityValue(progress.map { "\(Int(($0 * 100).rounded())) %" } ?? "")
    }
}

private struct ForkCareRoundStyle: ButtonStyle {
    let working: Bool
    let progress: Double?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forkCareTool) private var tool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var breathing = false

    func makeBody(configuration: Configuration) -> some View {
        let fill = ForkCareLogic.buttonGradient(tool)
        let glow = Color(care: ForkCareLogic.glow(tool))
        let active = isEnabled || working
        return configuration.label
            .background(
                ZStack {
                    // The waiting light, behind the button.
                    Circle()
                        .fill(glow.opacity(active ? 0.62 : 0.15))
                        .blur(radius: 26)
                        .scaleEffect(working ? 1.0 : (breathing ? 1.2 : 0.95))
                    if working { ForkCarePulses(glow: glow) }
                    Circle()
                        .fill(LinearGradient(colors: [Color(care: fill.top), Color(care: fill.bottom)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .opacity(working ? 0.6 : 1)
                    Circle()
                        .fill(LinearGradient(colors: [Color.white.opacity(hovered ? 0.22 : 0.14), .clear],
                                             startPoint: .top, endPoint: .center))
                    Circle().stroke(glow.opacity(0.8), lineWidth: 1.5)
                    if working { ForkCareRing(progress: progress, glow: glow) }
                }
            )
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            .opacity(active ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.95 : (hovered && isEnabled ? 1.04 : 1))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.18), value: hovered)
            .contentShape(Circle())
            .onHover { hovered = $0 }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: ForkCareMotion.breathe / 2).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

/// Rings of light leaving the working button, one after the other.
private struct ForkCarePulses: View {
    let glow: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spreading = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .stroke(glow.opacity(spreading ? 0 : 0.55), lineWidth: 2)
                        .scaleEffect(spreading ? 1.7 : 1)
                        .animation(.easeOut(duration: ForkCareMotion.pulse)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * ForkCareMotion.pulse / 2),
                                   value: spreading)
                }
            }
        }
        .onAppear { spreading = true }
    }
}

private struct ForkCareRing: View {
    let progress: Double?
    let glow: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        let trail = AngularGradient(colors: [glow.opacity(0), glow.opacity(0.9), .white], center: .center)
        ZStack {
            // Busy: a trail of light orbits just outside the button.
            Circle()
                .trim(from: 0, to: 0.62)
                .stroke(trail, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
                .shadow(color: glow.opacity(0.9), radius: 6)
                .padding(-9)
            // How far: the arc on the button's edge, when the length is known.
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 5)
            if let progress, progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(LinearGradient(colors: [glow, .white], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: glow.opacity(0.8), radius: 5)
                    .animation(.easeOut(duration: 0.3), value: progress)
            }
        }
        .padding(3)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: ForkCareMotion.turn).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}

/// A figure counting up to its value when it appears, then following it.
struct ForkCareCountingText: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}

/// Counts from zero to `target` once shown (at once with Reduce Motion).
struct ForkCareCountUp: View {
    let target: Double
    let format: (Double) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        ForkCareCountingText(value: shown, format: format)
            .onAppear {
                guard !reduceMotion else { shown = target; return }
                withAnimation(.easeOut(duration: ForkCareMotion.countUp)) { shown = target }
            }
            .onChange(of: target) { _, new in shown = new }
            .accessibilityLabel(format(target))
    }
}

/// Arrives sliding up and fading in, `index` steps after the first.
private struct ForkCareAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                let delay = ForkCareMotion.delay(index: index)
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2).delay(delay)) { shown = true }
                } else {
                    withAnimation(.spring(response: ForkCareMotion.appear, dampingFraction: 0.82).delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    func forkCareAppear(index: Int = 0) -> some View {
        modifier(ForkCareAppear(index: index))
    }
}

/// The closing tick: the circle, then the tick drawn stroke by stroke, and a
/// wave of colour leaving it once.
struct ForkCareCheckmark: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var waved = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(waved ? 0 : 0.6), lineWidth: 3)
                .scaleEffect(waved ? 1.6 : 1)
            Circle()
                .fill(tint.opacity(0.18))
            Circle()
                .trim(from: 0, to: drawn)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            ForkCareTickShape()
                .trim(from: 0, to: drawn)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .padding(18)
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { drawn = 1; return }
            withAnimation(.easeOut(duration: ForkCareMotion.check)) { drawn = 1 }
            withAnimation(.easeOut(duration: 0.9).delay(ForkCareMotion.check * 0.8)) { waved = true }
        }
    }
}

private struct ForkCareTickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

/// A discreet text button under the round one, for what most people never need.
struct ForkCareLink: View {
    let title: String
    var symbol: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(hovered ? Color.carePrimary : Color.careSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// A small filled capsule for the one action a card asks for, such as installing.
struct ForkCareActionChip: View {
    let title: String
    let tint: Color
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                // On light, the deep tint itself carries the white title.
                .background(tint.opacity(scheme == .dark ? (hovered ? 0.45 : 0.32) : (hovered ? 1 : 0.88)), in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(0.7), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// The closing screen's large result. A success draws its tick; anything
/// else shows its symbol in its colour.
struct ForkCareSummary: View {
    let symbol: String
    let tint: Color
    let headline: String
    let detail: String?
    var success = false

    var body: some View {
        VStack(spacing: 12) {
            if success {
                ForkCareCheckmark(tint: tint)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 54, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(headline)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.carePrimary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.careSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .forkCareAppear()
    }
}

/// A translucent panel for lists and results on a tool's background; with
/// `hoverable`, it rises slightly and its edge lights up under the pointer.
struct ForkCareCard<Content: View>: View {
    var hoverable = false
    @ViewBuilder let content: Content
    @State private var hovered = false

    var body: some View {
        let lit = hoverable && hovered
        content
            .background(Color.careFill(lit ? 0.10 : ForkCareLogic.cardOpacity),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.careVeil(lit ? 0.24 : 0.10), lineWidth: 1))
            .scaleEffect(lit ? 1.015 : 1)
            .shadow(color: .black.opacity(lit ? 0.25 : 0), radius: 14, y: 6)
            .animation(.easeOut(duration: 0.18), value: lit)
            .onHover { hovered = $0 }
    }
}

/// An orange line for something that went wrong, said in words, not by colour alone.
struct ForkCareNotice: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(Color.careAccent(.warning))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 440)
    }
}
