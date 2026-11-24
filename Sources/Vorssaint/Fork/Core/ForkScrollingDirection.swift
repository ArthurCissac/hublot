// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Horizontal scrolling captures. Upstream joins frames that scroll up and
/// down. A frame turned a quarter clockwise scrolls up and down when the
/// page scrolls sideways: upstream's own matching then joins it, and the
/// finished picture is turned back. Three lines of upstream's capture loop
/// call this: its first frame, each frame after it, and the joined picture.
///
/// The capture menu arms the direction just before it starts a scrolling
/// capture; the capture decides at its first frame, so a capture started any
/// other way stays vertical. Main thread and capture loop, one capture at a time.
enum ForkScrollingDirection {
    private static var armedAt: Date?
    private(set) static var isHorizontal = false
    /// The capture must start within this long of being armed.
    static let armLifetime: TimeInterval = 5

    static func armHorizontal(at date: Date = Date()) {
        armedAt = date
    }

    static func disarm() {
        armedAt = nil
    }

    /// Whether the capture about to start will go sideways, before its first frame.
    static func isArmedHorizontal(at date: Date = Date()) -> Bool {
        armedAt.map { date.timeIntervalSince($0) >= 0 && date.timeIntervalSince($0) <= armLifetime } ?? false
    }

    /// The first frame of a capture: the direction is decided here, for the whole capture.
    static func first(_ image: CGImage?, at date: Date = Date()) -> CGImage? {
        let age = armedAt.map { date.timeIntervalSince($0) }
        isHorizontal = age.map { $0 >= 0 && $0 <= armLifetime } ?? false
        armedAt = nil
        return oriented(image)
    }

    /// A frame as upstream's matching sees it.
    static func oriented(_ image: CGImage?) -> CGImage? {
        guard isHorizontal, let image else { return image }
        return rotated(image, clockwise: true)
    }

    /// The joined picture turned back the right way.
    static func restored(_ image: CGImage?) -> CGImage? {
        guard isHorizontal, let image else { return image }
        return rotated(image, clockwise: false)
    }

    /// The picture turned a quarter, clockwise or not, pixel for pixel.
    static func rotated(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let width = image.height, height = image.width
        guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        if clockwise {
            context.translateBy(x: 0, y: CGFloat(height))
            context.rotate(by: -.pi / 2)
        } else {
            context.translateBy(x: CGFloat(width), y: 0)
            context.rotate(by: .pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
