// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// More styles for the minimal companion (`forkMascotVariant`): a cat, a
/// ghost, a pixel one and a blob, all drawn by Hublot, keeping its eyes,
/// faces and palette. Pure: which variant, the silhouettes and parts in
/// the companion's own square (y downward), and the sizes they move by.
enum ForkMascotVariantLogic {
    enum Variant: String, CaseIterable {
        case classic, cat, ghost, pixel, blob

        /// The cat and the pixel one keep the chosen shape; the ghost and
        /// the blob have their own.
        var keepsShape: Bool { self == .classic || self == .cat || self == .pixel }
    }

    static func variant(_ raw: String?) -> Variant { Variant(rawValue: raw ?? "") ?? .classic }

    /// Only the minimal style takes a variant; the robot stays itself.
    static func effective(_ variant: Variant, minimal: Bool) -> Variant { minimal ? variant : .classic }

    // MARK: - Silhouettes

    /// A domed head and three soft scallops at the bottom.
    static func ghostBody(size s: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        path.move(to: p(0.14, 0.52))
        path.addCurve(to: p(0.86, 0.52), control1: p(0.14, 0.04), control2: p(0.86, 0.04))
        path.addLine(to: p(0.86, 0.88))
        path.addQuadCurve(to: p(0.62, 0.88), control: p(0.74, 1.0))
        path.addQuadCurve(to: p(0.38, 0.88), control: p(0.5, 1.0))
        path.addQuadCurve(to: p(0.14, 0.88), control: p(0.26, 1.0))
        path.closeSubpath()
        return path
    }

    /// A soft, slightly lopsided drop of jelly.
    static func blobBody(size s: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        path.move(to: p(0.5, 0.15))
        path.addCurve(to: p(0.91, 0.62), control1: p(0.75, 0.15), control2: p(0.93, 0.36))
        path.addCurve(to: p(0.56, 0.95), control1: p(0.89, 0.84), control2: p(0.75, 0.95))
        path.addCurve(to: p(0.09, 0.67), control1: p(0.3, 0.95), control2: p(0.07, 0.86))
        path.addCurve(to: p(0.5, 0.15), control1: p(0.11, 0.41), control2: p(0.26, 0.15))
        path.closeSubpath()
        return path
    }

    /// How many pixels across the pixel one is drawn with, whatever its size.
    static let pixelsAcross = 12

    /// `path` as square pixels: every cell of an n × n grid whose centre
    /// lies inside it.
    static func pixelated(_ path: CGPath, size s: CGFloat, pixels n: Int = pixelsAcross) -> CGPath {
        let out = CGMutablePath()
        guard s > 0, n > 0 else { return out }
        let cell = s / CGFloat(n)
        for row in 0..<n {
            for column in 0..<n {
                let center = CGPoint(x: (CGFloat(column) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
                if path.contains(center) {
                    out.addRect(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
        }
        return out
    }

    /// Drawn at this many pixels per point, the whole companion reads as
    /// `pixelsAcross` pixels wide.
    static func rasterScale(size: CGFloat, pixels n: Int = pixelsAcross) -> CGFloat {
        size > 0 ? CGFloat(n) / size : 1
    }

    // MARK: - The cat's parts

    /// Two pointed ears standing on the head, whose top is at `top`.
    static func ear(left: Bool, top: CGFloat, size s: CGFloat, inner: Bool = false) -> CGPath {
        let path = CGMutablePath()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (left ? x : 1 - x) * s, y: y * s) }
        if inner {
            path.move(to: p(0.22, top + 0.15))
            path.addLine(to: p(0.27, top - 0.05))
            path.addLine(to: p(0.37, top + 0.08))
        } else {
            path.move(to: p(0.15, top + 0.22))
            path.addLine(to: p(0.25, top - 0.13))
            path.addLine(to: p(0.45, top + 0.07))
        }
        path.closeSubpath()
        return path
    }

    /// Where an ear turns when it twitches: the middle of its base.
    static func earPivot(left: Bool, top: CGFloat, size s: CGFloat) -> CGPoint {
        CGPoint(x: (left ? 0.3 : 0.7) * s, y: (top + 0.15) * s)
    }

    /// Two whiskers on each cheek, below the eyes at `eyeY`.
    static func whiskers(eyeY: CGFloat, size s: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for side: CGFloat in [-1, 1] {
            func x(_ v: CGFloat) -> CGFloat { (0.5 + side * v) * s }
            path.move(to: CGPoint(x: x(0.24), y: (eyeY + 0.13) * s))
            path.addLine(to: CGPoint(x: x(0.5), y: (eyeY + 0.07) * s))
            path.move(to: CGPoint(x: x(0.24), y: (eyeY + 0.18) * s))
            path.addLine(to: CGPoint(x: x(0.5), y: (eyeY + 0.21) * s))
        }
        return path
    }

    /// A little nose between the whiskers.
    static func nose(eyeY: CGFloat, size s: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.46 * s, y: (eyeY + 0.12) * s))
        path.addLine(to: CGPoint(x: 0.54 * s, y: (eyeY + 0.12) * s))
        path.addLine(to: CGPoint(x: 0.5 * s, y: (eyeY + 0.17) * s))
        path.closeSubpath()
        return path
    }

    /// Where the tail leaves the body, on the side away from the camera.
    static func tailBase(outward: CGFloat, size s: CGFloat) -> CGPoint {
        CGPoint(x: (0.5 + outward * 0.34) * s, y: 0.84 * s)
    }

    /// Raised and curving up, or wrapped round its feet while it sleeps.
    static func tail(outward o: CGFloat, curled: Bool, size s: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (0.5 + o * x) * s, y: y * s) }
        path.move(to: tailBase(outward: o, size: s))
        if curled {
            path.addCurve(to: p(-0.18, 0.95), control1: p(0.34, 1.02), control2: p(0.05, 1.0))
        } else {
            path.addCurve(to: p(0.64, 0.4), control1: p(0.62, 0.92), control2: p(0.76, 0.6))
            path.addQuadCurve(to: p(0.56, 0.34), control: p(0.6, 0.32))
        }
        return path
    }

    // MARK: - Motion

    /// The ghost floats up and down by this share of its size.
    static let ghostFloat: CGFloat = 0.06
    static let ghostOpacity: Float = 0.8
    /// The blob's jelly wobble at rest, as added scale (x and y move apart).
    static let blobWobble: [CGFloat] = [0, 0.045, -0.035, 0.025, -0.012, 0]
    /// A stronger one when it jumps for a reaction.
    static let blobSplat: [CGFloat] = [0, 0.16, -0.12, 0.07, -0.03, 0]
    /// How far the cat's tail sways each way, in radians.
    static let tailSway: CGFloat = 0.22
}
