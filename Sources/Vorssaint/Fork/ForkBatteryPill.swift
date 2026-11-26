// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Lot 8, Juicy's alert pills: a dark capsule whose outline lights up to the
/// level in the alert's colour and breathes, an icon, a title and a line
/// under it. Shown at the top or in the middle of the screen the pointer is
/// on, stacked when several come at once, gone after a few seconds or on a
/// click (the ones set to stay wait for the click). Main thread only.
final class ForkBatteryPillPresenter {
    static let shared = ForkBatteryPillPresenter()
    typealias Rules = ForkBatteryAlertRules

    private final class Entry {
        let panel: NSPanel
        let model: ForkBatteryPillModel
        let position: Rules.Position
        let host: NSView
        init(panel: NSPanel, model: ForkBatteryPillModel, position: Rules.Position, host: NSView) {
            self.panel = panel
            self.model = model
            self.position = position
            self.host = host
        }
    }

    private var entries: [Entry] = []

    private init() {}

    func show(_ pill: Rules.Pill, on screen: NSScreen) {
        // One pill at a time: a new one replaces what is showing.
        entries.forEach(dismiss)
        let words = ForkBatteryStrings.current.pillText(pill.message)
        let size = Rules.PillSize(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.forkBatteryPillSize) ?? "") ?? .standard
        let model = ForkBatteryPillModel(pill: pill, title: words.title, subtitle: words.subtitle)
        var entry: Entry?
        let view = ForkBatteryPillView(scale: size.scale, model: model) { [weak self] in
            if let entry { self?.dismiss(entry) }
        }
        let host = NSHostingView(rootView: view)
        let fitting = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: fitting),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = host

        let stacked = entries.filter { $0.position == pill.position && $0.panel.screen == screen }
        let below = stacked.reduce(CGFloat(0)) { $0 + $1.panel.frame.height * 0.82 }
        let x = screen.frame.midX - fitting.width / 2
        let y: CGFloat
        switch pill.position {
        case .top: y = screen.visibleFrame.maxY - fitting.height + 18 - below
        case .center: y = screen.frame.midY - fitting.height / 2 - below
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()

        let created = Entry(panel: panel, model: model, position: pill.position, host: host)
        entry = created
        entries.append(created)
        if !pill.sticky {
            DispatchQueue.main.asyncAfter(deadline: .now() + Rules.pillDuration) { [weak self, weak created] in
                if let created { self?.dismiss(created) }
            }
        }
    }

    /// Updates the pill showing when it is still the same alert (the
    /// charger's watts once agreed): its words and outline change in place.
    func refresh(_ pill: Rules.Pill) {
        guard let entry = entries.last, Self.sameAlert(entry.model.pill.message, pill.message) else { return }
        let words = ForkBatteryStrings.current.pillText(pill.message)
        withAnimation(.easeInOut(duration: 0.25)) {
            entry.model.pill = pill
            entry.model.title = words.title
            entry.model.subtitle = words.subtitle
        }
        DispatchQueue.main.async {
            let fitting = entry.host.fittingSize
            let frame = entry.panel.frame
            entry.panel.setFrame(NSRect(x: frame.midX - fitting.width / 2, y: frame.maxY - fitting.height,
                                        width: fitting.width, height: fitting.height), display: true)
        }
    }

    private static func sameAlert(_ a: Rules.Message, _ b: Rules.Message) -> Bool {
        switch (a, b) {
        case (.plugged, .plugged), (.unplugged, .unplugged): return true
        default: return false
        }
    }

    private func dismiss(_ entry: Entry) {
        guard entries.contains(where: { $0 === entry }) else { return }
        entries.removeAll { $0 === entry }
        withAnimation(.easeIn(duration: 0.25)) { entry.model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { entry.panel.orderOut(nil) }
    }
}

final class ForkBatteryPillModel: ObservableObject {
    @Published var visible = false
    @Published var pill: ForkBatteryAlertRules.Pill
    @Published var title: String
    @Published var subtitle: String?

    init(pill: ForkBatteryAlertRules.Pill, title: String, subtitle: String?) {
        self.pill = pill
        self.title = title
        self.subtitle = subtitle
    }
}

/// The colours of the alerts, as macOS draws its own.
enum ForkBatteryTintPalette {
    static func color(_ tint: ForkBatteryAlertRules.Tint) -> Color {
        Color(nsColor: nsColor(tint))
    }

    static func nsColor(_ tint: ForkBatteryAlertRules.Tint) -> NSColor {
        switch tint {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        }
    }
}

/// One pill: comes in with a spring, its outline lights up to the level,
/// the light breathes; a click closes it.
struct ForkBatteryPillView: View {
    typealias Rules = ForkBatteryAlertRules

    let scale: CGFloat
    @ObservedObject var model: ForkBatteryPillModel
    let onClose: () -> Void
    @State private var lit: CGFloat = 0
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pill: Rules.Pill { model.pill }
    private var title: String { model.title }
    private var subtitle: String? { model.subtitle }

    var body: some View {
        let s = scale
        let tint = ForkBatteryTintPalette.color(pill.tint)
        HStack(spacing: 14 * s) {
            ForkBatteryPillIcon(icon: pill.icon, tint: tint, scale: s)
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(title)
                    .font(.system(size: 18 * s, weight: .bold, design: .rounded))
                    .foregroundStyle(titleColor(tint))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13 * s, weight: .medium))
                        .foregroundStyle(isCritical ? tint.opacity(0.9) : Color.white.opacity(0.62))
                }
            }
            .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.leading, 24 * s)
        .padding(.trailing, 34 * s)
        .frame(minWidth: 300 * s, minHeight: 66 * s)
        .background {
            ZStack {
                if isCritical { Capsule().fill(tint.opacity(0.35)).blur(radius: 18 * s) }
                Capsule().fill(Color(red: 0.09, green: 0.09, blue: 0.10).opacity(0.97))
                Capsule().inset(by: 4 * s).strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            }
        }
        .overlay {
            ZStack {
                ForkPillOutline().stroke(Color(white: 0.22), lineWidth: 4.5 * s)
                ForkPillOutline()
                    .trim(from: 0, to: lit)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4.5 * s, lineCap: .round))
                    .shadow(color: tint.opacity(breathing ? 0.95 : 0.5), radius: (breathing ? 10 : 5) * s)
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 16 * s, y: 8 * s)
        .scaleEffect(model.visible ? 1 : 0.86)
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible ? 0 : -16 * s)
        .padding(30 * s)
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .onChange(of: pill.outline) { _, next in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { lit = next }
        }
        .onAppear {
            if reduceMotion {
                model.visible = true
                lit = pill.outline
                return
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { model.visible = true }
            withAnimation(.easeOut(duration: 1.0).delay(0.15)) { lit = pill.outline }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(0.4)) { breathing = true }
        }
        .accessibilityElement(children: .combine)
    }

    private var isCritical: Bool {
        if case .critical = pill.message { return true }
        return false
    }

    private func titleColor(_ tint: Color) -> Color {
        switch pill.message {
        case .critical, .charged, .plugged, .deviceCharged: return tint
        case .low, .unplugged, .deviceLow, .appDrift: return .white
        }
    }
}

/// The capsule's outline, starting at the bottom of its left end and going
/// up over it, then along the top: the part a level lights first.
struct ForkPillOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.height / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addRelativeArc(center: CGPoint(x: rect.minX + radius, y: rect.midY), radius: radius,
                            startAngle: .degrees(90), delta: .degrees(180))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addRelativeArc(center: CGPoint(x: rect.maxX - radius, y: rect.midY), radius: radius,
                            startAngle: .degrees(270), delta: .degrees(180))
        path.closeSubpath()
        return path
    }
}

/// The pill's icon: a small battery filled to the level, a bolt, a plug, or
/// the device's symbol, in the alert's colour.
struct ForkBatteryPillIcon: View {
    let icon: ForkBatteryAlertRules.Icon
    let tint: Color
    let scale: CGFloat

    var body: some View {
        let s = scale
        switch icon {
        case .battery(let percent):
            HStack(spacing: 1.5 * s) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5 * s, style: .continuous).strokeBorder(tint, lineWidth: 2.2 * s)
                    RoundedRectangle(cornerRadius: 2.5 * s, style: .continuous)
                        .fill(tint)
                        .frame(width: max(3 * s, 25 * s * CGFloat(max(0, min(100, percent))) / 100), height: 10 * s)
                        .padding(.leading, 3.5 * s)
                }
                .frame(width: 34 * s, height: 18 * s)
                RoundedRectangle(cornerRadius: 1 * s).fill(tint).frame(width: 2.5 * s, height: 7 * s)
            }
            .frame(width: 40 * s)
        case .bolt:
            symbol("bolt.fill", s)
        case .plug:
            symbol("powerplug.fill", s)
        case .device(let name):
            symbol(name, s)
        }
    }

    private func symbol(_ name: String, _ s: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: 24 * s, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 40 * s)
    }
}
