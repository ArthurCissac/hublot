// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// A picture laid over a recording, placed by hand. Upstream offers nine
/// places; the fork adds a center the picture can be dragged to on the
/// editor's stage, and corner handles for its size. A picture that was never
/// dragged has no such center and sits exactly where upstream puts it.
///
/// Centers are in the finished frame's own 0...1 space, with a top-left
/// origin, so a change of quality or of shape keeps the picture in place.
/// Pure geometry: the export and the stage read the same numbers.
enum ForkRecorderImagePlacement {
    /// The widest a picture may be asked to be, as a share of the frame's
    /// width. Upstream stops at 0.6.
    static let largestSize: Double = 1

    /// The picture's bottom-left corner on the canvas, in Core Image's space:
    /// from its hand-placed center when it has one, from upstream's nine
    /// places otherwise.
    static func origin(of overlay: RecorderImageOverlay, drawn: CGSize, in canvas: CGSize) -> CGPoint {
        guard let center = overlay.forkCenter else { return overlay.anchor.origin(of: drawn, in: canvas) }
        let held = clamped(center)
        let left = held.x * canvas.width - drawn.width / 2
        let top = held.y * canvas.height - drawn.height / 2
        return CGPoint(x: left.rounded(), y: (canvas.height - top - drawn.height).rounded())
    }

    /// The picture's center: where it was placed by hand, or where its anchor
    /// puts it. A drag starts from here.
    static func center(of overlay: RecorderImageOverlay, drawn: CGSize, in canvas: CGSize) -> CGPoint {
        if let center = overlay.forkCenter { return clamped(center) }
        guard canvas.width > 0, canvas.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let origin = overlay.anchor.origin(of: drawn, in: canvas)
        return clamped(CGPoint(x: (origin.x + drawn.width / 2) / canvas.width,
                               y: (canvas.height - origin.y - drawn.height / 2) / canvas.height))
    }

    /// The part of the stage the finished frame is shown in: fitted whole,
    /// centered, as the player shows it.
    static func shownRect(canvas: CGSize, in stage: CGSize) -> CGRect? {
        guard canvas.width > 0, canvas.height > 0, stage.width > 0, stage.height > 0 else { return nil }
        let fit = min(stage.width / canvas.width, stage.height / canvas.height)
        let shown = CGSize(width: canvas.width * fit, height: canvas.height * fit)
        return CGRect(x: (stage.width - shown.width) / 2, y: (stage.height - shown.height) / 2,
                      width: shown.width, height: shown.height)
    }

    /// The picture's frame on the stage, origin at the stage's top left.
    /// `source` is the picture's own size, which gives its proportions.
    static func frame(of overlay: RecorderImageOverlay, source: CGSize, canvas: CGSize, stage: CGSize) -> CGRect? {
        guard let shown = shownRect(canvas: canvas, in: stage),
              let drawn = RecorderImageOverlay.drawnSize(source: source, size: overlay.size, canvas: canvas)
        else { return nil }
        let scale = shown.width / canvas.width
        let center = center(of: overlay, drawn: drawn, in: canvas)
        let size = CGSize(width: drawn.width * scale, height: drawn.height * scale)
        return CGRect(x: shown.minX + center.x * shown.width - size.width / 2,
                      y: shown.minY + center.y * shown.height - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The center after a drag of `translation` points on the stage. It stays
    /// on the frame: a picture can hang over an edge, never leave entirely.
    static func moved(_ center: CGPoint, by translation: CGSize, shown: CGSize) -> CGPoint {
        guard shown.width > 0, shown.height > 0 else { return clamped(center) }
        return clamped(CGPoint(x: center.x + translation.width / shown.width,
                               y: center.y + translation.height / shown.height))
    }

    /// The size after a corner was dragged from `start` to `current` points
    /// away from the picture's center: the corner stays under the pointer.
    static func resized(_ size: Double, from start: CGFloat, to current: CGFloat,
                        source: CGSize, canvas: CGSize) -> Double {
        guard start > 1, size.isFinite, current.isFinite else { return size }
        let wanted = size * Double(current / start)
        return min(max(wanted, RecorderImageOverlay.sizeRange.lowerBound),
                   largestUsefulSize(source: source, canvas: canvas))
    }

    /// Past this, asking for more draws nothing larger: upstream holds a
    /// picture inside the frame's margins, on both axes.
    static func largestUsefulSize(source: CGSize, canvas: CGSize) -> Double {
        let range = RecorderImageOverlay.sizeRange
        guard source.width > 0, source.height > 0, canvas.width > 0, canvas.height > 0 else {
            return range.upperBound
        }
        let margin = min(canvas.width, canvas.height) * 0.05
        let byWidth = (canvas.width - 2 * margin) / canvas.width
        let byHeight = (canvas.height - 2 * margin) * source.width / source.height / canvas.width
        return max(range.lowerBound, min(range.upperBound, Double(min(byWidth, byHeight))))
    }

    /// Where to put the playhead so a picture being edited is seen whole. A
    /// picture fades in from its first moment, and one is added exactly at
    /// the playhead: left there, the stage shows a frame where it is not yet
    /// drawn at all. Nil when the picture is already fully shown at `time`.
    static func visibleMoment(of overlay: RecorderImageOverlay, at time: Double) -> Double? {
        let duration = overlay.end - overlay.start
        guard duration > 0, time.isFinite else { return nil }
        let ramp = min(RecorderImageOverlay.fade, duration / 2)
        let first = overlay.start + ramp
        let last = overlay.end - ramp
        // A picture too short to be shown whole is seen best in its middle.
        guard first <= last else { return abs(time - (overlay.start + duration / 2)) < 0.001 ? nil : overlay.start + duration / 2 }
        if time >= first && time <= last { return nil }
        return min(max(time, first), last)
    }

    static func clamped(_ center: CGPoint) -> CGPoint {
        guard center.x.isFinite, center.y.isFinite else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: min(max(center.x, 0), 1), y: min(max(center.y, 0), 1))
    }
}
