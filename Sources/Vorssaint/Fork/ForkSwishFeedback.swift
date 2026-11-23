// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// What the action bubble shows: an icon, a name, and how close the gesture
/// is to acting (a pinch fades in as it closes).
struct ForkSwishBubbleItem: Equatable {
    enum Icon: Equatable {
        case close, quit, minimize, unminimize, fullScreen
        case cycle(forward: Bool)
        /// A place on the screen, as fractions of it from the top left.
        case region(CGRect)
        case display(ForkTitleBarGestureLogic.Direction)
    }

    var icon: Icon
    var title: String
    var progress: Double = 1
}

/// Swish-style feedback during a gesture: a bubble by the pointer that says
/// what the gesture will do, with icons recreated from system symbols in the
/// colors of the window buttons, and, when the window does not glide, a
/// translucent frame that slides to where it will go.
///
/// One borderless panel over the display under the pointer, set once when a
/// gesture starts and never resized during it: the bubble and the frame move
/// inside it, animated by Core Animation and SwiftUI. It never takes a click
/// or the focus.
final class ForkSwishFeedback {
    static let shared = ForkSwishFeedback()

    /// The space the bubble may take, beside the pointer.
    private static let bubbleSize = CGSize(width: 380, height: 64)

    private var panel: NSPanel?
    private var outline: CALayer?
    private var hosting: NSHostingView<ForkSwishBubbleView>?
    private var screen = CGRect.zero
    private var pointer = CGPoint.zero
    private var item: ForkSwishBubbleItem?
    private var outlineTarget: CGRect?
    private var generation = 0

    /// A gesture starts with the pointer here and, for a window, that window's
    /// frame (both window-list coordinates, top-left origin).
    func begin(pointer location: CGPoint, window: CGRect?) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: location.x, y: primaryHeight - location.y)
        guard let display = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        generation += 1
        pointer = point
        screen = display.frame
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(screen, display: false)
        item = nil
        outlineTarget = nil
        if let outline {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let window { outline.frame = local(ForkSwishDisplays.accessibilityRect(window, primaryHeight: primaryHeight)) }
            outline.opacity = 0
            CATransaction.commit()
        }
        render()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// What the gesture would do now, and where the frame goes (AppKit
    /// coordinates; nil hides it).
    func update(item: ForkSwishBubbleItem?, outline target: CGRect?) {
        guard panel != nil else { return }
        if item != self.item {
            self.item = item
            render()
        }
        guard target != outlineTarget, let outline else { return }
        outlineTarget = target
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        if let target {
            outline.frame = local(target)
            outline.opacity = 1
        } else {
            outline.opacity = 0
        }
        CATransaction.commit()
    }

    /// The gesture is over: everything fades out.
    func end() {
        guard let panel, panel.isVisible else { return }
        let ending = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // A new gesture may have started while this one faded.
            guard let self, self.generation == ending else { return }
            panel.orderOut(nil)
            self.item = nil
            self.render()
        })
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -screen.minX, dy: -screen.minY)
    }

    private func render() {
        guard let hosting else { return }
        let size = Self.bubbleSize
        let origin = ForkSwishMotion.bubbleOrigin(pointer: pointer, size: size, screen: screen)
        hosting.rootView = ForkSwishBubbleView(item: item, trailing: origin.x < pointer.x)
        hosting.frame = CGRect(origin: CGPoint(x: origin.x - screen.minX, y: origin.y - screen.minY), size: size)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let content = NSView()
        content.wantsLayer = true
        let outline = CALayer()
        outline.cornerRadius = 12
        outline.borderWidth = 2
        outline.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        outline.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        outline.opacity = 0
        content.layer?.addSublayer(outline)
        let hosting = NSHostingView(rootView: ForkSwishBubbleView(item: nil, trailing: false))
        content.addSubview(hosting)
        panel.contentView = content
        self.outline = outline
        self.hosting = hosting
        return panel
    }
}

/// The bubble: icon and name in a capsule, Liquid Glass on macOS 26 and later.
struct ForkSwishBubbleView: View {
    let item: ForkSwishBubbleItem?
    let trailing: Bool

    var body: some View {
        ZStack(alignment: trailing ? .bottomTrailing : .bottomLeading) {
            Color.clear
            if let item {
                HStack(spacing: 10) {
                    ForkSwishActionIcon(icon: item.icon)
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.leading, 9)
                .padding(.trailing, 15)
                .padding(.vertical, 8)
                .modifier(BubbleBackground())
                .opacity(0.4 + 0.6 * item.progress)
                .scaleEffect(0.86 + 0.14 * item.progress, anchor: trailing ? .bottomTrailing : .bottomLeading)
                .transition(.scale(scale: 0.6, anchor: trailing ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: item)
    }

    private struct BubbleBackground: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: Capsule())
            } else {
                content
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            }
        }
    }
}

/// The action's icon: a ring in the window buttons' colors with a symbol, a
/// filled red circle to quit, or the screen with the place filled in.
struct ForkSwishActionIcon: View {
    let icon: ForkSwishBubbleItem.Icon

    var body: some View {
        switch icon {
        case .close: ring(Color(nsColor: .systemRed), "xmark")
        case .quit: filled(Color(nsColor: .systemRed), "xmark")
        case .minimize: ring(Color(nsColor: .systemYellow), "minus")
        case .unminimize: ring(Color(nsColor: .systemYellow), "plus")
        case .fullScreen: ring(Color(nsColor: .systemGreen), "arrow.up.left.and.arrow.down.right")
        case .cycle(let forward): ring(.accentColor, forward ? "arrow.right" : "arrow.left")
        case .display(let direction): ring(.accentColor, arrow(direction))
        case .region(let region): screen(region)
        }
    }

    private func ring(_ color: Color, _ symbol: String) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.2))
            Circle().strokeBorder(color, lineWidth: 2.5)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(color)
        }
        .frame(width: 32, height: 32)
    }

    private func filled(_ color: Color, _ symbol: String) -> some View {
        ZStack {
            Circle().fill(color)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.62))
        }
        .frame(width: 32, height: 32)
    }

    private func screen(_ region: CGRect) -> some View {
        let size = CGSize(width: 44, height: 30), inset: CGFloat = 3
        let inner = CGSize(width: size.width - 2 * inset, height: size.height - 2 * inset)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.accentColor)
                .frame(width: max(3, region.width * inner.width), height: max(3, region.height * inner.height))
                .offset(x: inset + region.minX * inner.width, y: inset + region.minY * inner.height)
        }
        .frame(width: size.width, height: size.height)
    }

    private func arrow(_ direction: ForkTitleBarGestureLogic.Direction) -> String {
        switch direction {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        default: return "arrow.down"
        }
    }
}
