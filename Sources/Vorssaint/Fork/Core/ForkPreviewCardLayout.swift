// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics

/// Where the card-style capture previews go on screen.
///
/// The figures were measured on the reference app at its medium size (see
/// docs/reference/cleanshot-x.md): a fixed card whatever the capture's shape,
/// hugging the left edge of the pointer's display, the newest card on top of
/// the stack. Pure geometry, in AppKit coordinates (origin at the bottom left).
enum ForkPreviewCardLayout {
    static let cardSize = CGSize(width: 210, height: 150)
    static let cornerRadius: CGFloat = 12
    /// From the display's left edge to the card.
    static let edgeMargin: CGFloat = 40
    /// From the display's bottom edge to the lowest card.
    static let bottomMargin: CGFloat = 100
    /// Between two stacked cards.
    static let spacing: CGFloat = 10
    /// Kept free at the top of the display, above the highest card.
    static let topReserve: CGFloat = 30

    /// The display the previews belong on: the one under the pointer. A
    /// pointer that sits on no display (a seam, or a display unplugged a
    /// moment ago) gets the nearest one. Nil only when there is no display.
    static func screenFrame(pointer: CGPoint, screenFrames: [CGRect]) -> CGRect? {
        if let containing = screenFrames.first(where: { $0.contains(pointer) }) {
            return containing
        }
        return screenFrames.min { distance(from: pointer, to: $0) < distance(from: pointer, to: $1) }
    }

    /// The frame of the card at `index` in the stack; 0 is the oldest card,
    /// at the bottom, and each newer one sits above it.
    static func cardFrame(index: Int, in screenFrame: CGRect) -> CGRect {
        let step = cardSize.height + spacing
        return CGRect(x: screenFrame.minX + edgeMargin,
                      y: screenFrame.minY + bottomMargin + CGFloat(max(0, index)) * step,
                      width: cardSize.width,
                      height: cardSize.height)
    }

    /// How many cards a display can stack before the top one would leave it.
    /// Never less than one: a capture always gets its preview.
    static func capacity(in screenFrame: CGRect) -> Int {
        let room = screenFrame.height - bottomMargin - topReserve + spacing
        return max(1, Int((room / (cardSize.height + spacing)).rounded(.down)))
    }

    /// How many of the oldest cards have to leave for `count` cards to fit.
    static func overflow(count: Int, capacity: Int) -> Int {
        max(0, count - max(1, capacity))
    }

    /// Where a card starts from when it appears and leaves to when it closes:
    /// the same spot, nudged toward the display's edge.
    static func restingOffsetFrame(for frame: CGRect) -> CGRect {
        frame.offsetBy(dx: -edgeMargin / 2, dy: 0)
    }

    // MARK: - Controls on the card

    /// What a hovered card offers. The card never takes the keyboard, so its
    /// controls are plain rectangles the card's own view hit-tests: the same
    /// frames place the drawing and decide what a click means.
    enum Control: CaseIterable {
        case close, pin, edit, discard, copy, save
    }

    static let cornerControlSize: CGFloat = 22
    static let cornerControlInset: CGFloat = 8
    static let pillSize = CGSize(width: 104, height: 26)
    static let pillSpacing: CGFloat = 8

    /// A control's frame inside the card, origin at the card's top left.
    static func controlFrame(_ control: Control) -> CGRect {
        let side = cornerControlSize
        let near = cornerControlInset
        let farX = cardSize.width - cornerControlInset - side
        let farY = cardSize.height - cornerControlInset - side
        let pillX = (cardSize.width - pillSize.width) / 2
        let pillsTop = (cardSize.height - 2 * pillSize.height - pillSpacing) / 2
        switch control {
        case .close: return CGRect(x: near, y: near, width: side, height: side)
        case .pin: return CGRect(x: farX, y: near, width: side, height: side)
        case .edit: return CGRect(x: near, y: farY, width: side, height: side)
        case .discard: return CGRect(x: farX, y: farY, width: side, height: side)
        case .copy: return CGRect(origin: CGPoint(x: pillX, y: pillsTop), size: pillSize)
        case .save:
            return CGRect(origin: CGPoint(x: pillX, y: pillsTop + pillSize.height + pillSpacing), size: pillSize)
        }
    }

    /// The control under a point of the card, with a few points of slack
    /// around each one so a small target is not missed by a hair.
    static func control(at point: CGPoint, slack: CGFloat = 3) -> Control? {
        Control.allCases.first { controlFrame($0).insetBy(dx: -slack, dy: -slack).contains(point) }
    }

    /// What a click on the card means: one of its controls, or the picture
    /// itself, which opens the capture in the editor. The controls only count
    /// while they are drawn, so a click on a card that is not hovered can never
    /// land on a button nobody saw.
    enum ClickTarget: Equatable {
        case control(Control)
        case picture
    }

    static func clickTarget(at point: CGPoint, controlsVisible: Bool) -> ClickTarget {
        guard controlsVisible, let control = control(at: point) else { return .picture }
        return .control(control)
    }

    /// Where a picture of `imageSize` is drawn so it fills `container`, cropped
    /// evenly on the two sides that overflow.
    static func fillRect(imageSize: CGSize, in container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let scale = max(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: container.midX - size.width / 2, y: container.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Past this distance a press on the card is a drag of the capture, not a click.
    static let dragThreshold: CGFloat = 4

    static func isDrag(from start: CGPoint, to point: CGPoint) -> Bool {
        let dx = point.x - start.x, dy = point.y - start.y
        return (dx * dx + dy * dy).squareRoot() >= dragThreshold
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
