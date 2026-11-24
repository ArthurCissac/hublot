// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit

/// The scrolling capture's live preview: a column beside the area showing the
/// picture assembled so far (see `ForkScrollingPreviewLayout`). It comes and
/// goes with the capture's controls (`ForkScrollingControls`), takes no
/// clicks, and is kept out of the picture with them.
///
/// Upstream's capture loop sends every picture it has kept through
/// `ForkScrollingPreviewFeed`. Each new strip is shrunk on a queue of its
/// own, so the capture never waits for the preview; the column is laid out
/// and drawn on the main thread. Down captures only: sideways ones show none.
final class ForkScrollingPreview {
    static let shared = ForkScrollingPreview()

    private var panel: NSPanel?
    private let view = PreviewView()
    private var slot = CGRect.zero
    /// Bumped at each show and hide, so a strip shrunk for an earlier capture is dropped.
    private var generation = 0
    private let queue = DispatchQueue(label: "agency.nexflow.hublot.scrolling-preview", qos: .userInitiated)

    /// What the queue keeps: the strips received and their shrunk copies.
    private struct Strips {
        var sources: [ObjectIdentifier] = []
        var thumbnails: [CGImage] = []
        var content = CGSize.zero
    }

    private var strips = Strips()

    private init() {}

    /// The column's window, for the capture engine to leave out.
    var windowIDs: Set<CGWindowID> {
        guard let panel, panel.isVisible, panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    /// Shown with the capture's controls, before its first picture: on screen
    /// already, so the capture leaves it out from the start.
    func show(region: RecorderSupport.Region) {
        hide()
        guard !ForkScrollingDirection.isArmedHorizontal() else { return }
        let area = region.anchorRect
        let screen = NSScreen.screens.max {
            $0.frame.intersection(area).width * $0.frame.intersection(area).height
                < $1.frame.intersection(area).width * $1.frame.intersection(area).height
        } ?? NSScreen.main
        slot = ForkScrollingPreviewLayout.slot(area: area, screen: screen?.visibleFrame ?? area)
        let panel = self.panel ?? Self.makePanel(view: view)
        self.panel = panel
        view.strips = []
        layout(content: .zero)
        panel.orderFrontRegardless()

        generation += 1
        let shown = generation
        queue.async { [weak self] in self?.strips = Strips() }
        ForkScrollingPreviewFeed.setReceiver { [weak self] slices in
            self?.queue.async { self?.receive(slices, generation: shown) }
        }
    }

    func hide() {
        ForkScrollingPreviewFeed.setReceiver(nil)
        generation += 1
        panel?.orderOut(nil)
        view.strips = []
    }

    // MARK: - Strips (on the queue)

    /// The pictures kept so far: only new or replaced ones are shrunk. The
    /// first picture is replaced once, cropped, when the capture finds what
    /// stays still at the bottom.
    private func receive(_ slices: [CGImage], generation shown: Int) {
        var changed = false
        for (index, slice) in slices.enumerated() {
            let id = ObjectIdentifier(slice)
            if index < strips.sources.count, strips.sources[index] == id { continue }
            guard let thumbnail = Self.shrunk(slice) else { continue }
            if index < strips.sources.count {
                strips.sources[index] = id
                strips.thumbnails[index] = thumbnail
            } else {
                strips.sources.append(id)
                strips.thumbnails.append(thumbnail)
            }
            changed = true
        }
        guard changed, let width = slices.first?.width else { return }
        strips.content = CGSize(width: width, height: slices.reduce(0) { $0 + $1.height })
        let thumbnails = strips.thumbnails, content = strips.content
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == shown else { return }
            self.view.strips = thumbnails
            self.layout(content: content)
        }
    }

    /// A strip at the column's width on a Retina display: a picture tens of
    /// thousands of pixels long stays a few megabytes.
    private static func shrunk(_ image: CGImage) -> CGImage? {
        let width = Int(ForkScrollingPreviewLayout.width * 2)
        guard image.width > 0, image.height > 0 else { return nil }
        let height = max(1, Int((CGFloat(image.height) * CGFloat(width) / CGFloat(image.width)).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Window

    private func layout(content: CGSize) {
        let frames = ForkScrollingPreviewLayout.frames(content: content, slot: slot)
        view.imageRect = frames.image
        panel?.setFrame(frames.column, display: true)
        view.needsDisplay = true
    }

    private static func makePanel(view: PreviewView) -> NSPanel {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = view
        return panel
    }

    /// The column: a dark rounded card, the strips stacked from the top.
    private final class PreviewView: NSView {
        var strips: [CGImage] = [] { didSet { needsDisplay = true } }
        /// Where the picture goes, from the bottom left.
        var imageRect = CGRect.zero

        override func draw(_ dirtyRect: NSRect) {
            let card = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
            NSColor.black.withAlphaComponent(0.78).setFill()
            card.fill()
            guard !strips.isEmpty, imageRect.width > 0, imageRect.height > 0,
                  let context = NSGraphicsContext.current?.cgContext else { return }
            let heights = ForkScrollingPreviewLayout.stripHeights(strips.map { CGFloat($0.height) },
                                                                  filling: imageRect.height)
            context.saveGState()
            context.interpolationQuality = .medium
            // From the top down; CoreGraphics draws from the bottom up, as this view does.
            var top = imageRect.maxY
            for (strip, height) in zip(strips, heights) {
                context.draw(strip, in: CGRect(x: imageRect.minX, y: top - height, width: imageRect.width, height: height))
                top -= height
            }
            context.restoreGState()
            NSColor.white.withAlphaComponent(0.25).setStroke()
            NSBezierPath(rect: imageRect.insetBy(dx: -0.5, dy: -0.5)).stroke()
        }
    }
}
