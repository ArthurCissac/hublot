// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// How a picture laid over a recording is turned: mirrored left to right, and
/// rotated by an angle in degrees, clockwise as seen on screen. Both apply
/// around the picture's own center, mirror first. A picture without a turn
/// is drawn as upstream draws it.
struct ForkRecorderImageTurn: Codable, Equatable {
    var mirrored: Bool = false
    var degrees: Double = 0

    var isIdentity: Bool { !mirrored && ForkRecorderImageTurn.normalized(degrees) == 0 }

    /// Within this many degrees of a quarter turn, a rotation settles on it.
    static let snapRange: Double = 5
    /// The step of a rotation made with Shift held.
    static let fineStep: Double = 15

    /// Any angle, as the same angle between 0 and 360.
    static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let turned = degrees.truncatingRemainder(dividingBy: 360)
        let positive = turned < 0 ? turned + 360 : turned
        return positive >= 359.9995 ? 0 : positive
    }

    /// The angle a rotation handle at `point` asks for. The handle sits
    /// straight above the center when the picture is upright; points are in
    /// the stage's own space, origin at the top left.
    static func degrees(handleAt point: CGPoint, center: CGPoint) -> Double {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        guard dx != 0 || dy != 0 else { return 0 }
        return normalized(atan2(dy, dx) * 180 / .pi + 90)
    }

    /// The angle a rotation settles on: a quarter turn when close to one, or
    /// the nearest 15 degrees with Shift held.
    static func snapped(_ degrees: Double, fine: Bool) -> Double {
        let angle = normalized(degrees)
        if fine { return normalized((angle / fineStep).rounded() * fineStep) }
        let quarter = (angle / 90).rounded() * 90
        return abs(angle - quarter) <= snapRange ? normalized(quarter) : angle
    }

    /// The width and height of what a rotated picture covers.
    static func coveredSize(of size: CGSize, degrees: Double) -> CGSize {
        let radians = normalized(degrees) * .pi / 180
        let cosine = abs(CGFloat(cos(radians)))
        let sine = abs(CGFloat(sin(radians)))
        return CGSize(width: size.width * cosine + size.height * sine,
                      height: size.width * sine + size.height * cosine)
    }

    /// Where a drawn picture of `size` goes, in Core Image's space (origin at
    /// the bottom left, y going up): mirrored and rotated around its center,
    /// then placed with its unturned bottom-left corner at `origin`.
    static func transform(_ turn: ForkRecorderImageTurn?, size: CGSize, origin: CGPoint) -> CGAffineTransform {
        let placed = CGAffineTransform(translationX: origin.x, y: origin.y)
        guard let turn, !turn.isIdentity else { return placed }
        let half = CGPoint(x: size.width / 2, y: size.height / 2)
        // Clockwise on screen is a negative angle once y goes up.
        let radians = -CGFloat(normalized(turn.degrees) * .pi / 180)
        return CGAffineTransform(translationX: -half.x, y: -half.y)
            .concatenating(CGAffineTransform(scaleX: turn.mirrored ? -1 : 1, y: 1))
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: origin.x + half.x, y: origin.y + half.y))
    }

    /// Where the small bar of the selected picture goes, origin at its top
    /// left: centered above what the picture covers, clear of its rotation
    /// handle, or under it when the stage has no room above.
    static func barOrigin(barSize: CGSize, pictureCenter: CGPoint, covered: CGSize, stage: CGSize,
                          clearance: CGFloat) -> CGPoint {
        let x = min(max(pictureCenter.x - barSize.width / 2, 4), max(4, stage.width - barSize.width - 4))
        let above = pictureCenter.y - covered.height / 2 - clearance - barSize.height
        let below = pictureCenter.y + covered.height / 2 + clearance
        let y = above >= 4 ? above : min(below, max(4, stage.height - barSize.height - 4))
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}
