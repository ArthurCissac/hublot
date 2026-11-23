// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// macOS opens Mission Control, with its "add a desktop" button, when a drag
/// rests against the top edge of a display, even where another display lies
/// above it. A dragged file then never reaches the display above, nor the
/// island's shelf. Two answers, by edge:
///
/// - where a display lies above, a drag moving up past the edge is carried
///   straight onto it: it never rests on the edge;
/// - where nothing lies above, the drag is kept one point under the edge,
///   the way upstream already keeps a dragged window away from it.
///
/// Displays here are in window-list coordinates: origin at the top left of
/// the primary display, y downward.
enum ForkDragTopGuardLogic {
    /// How close to the top a drag has to come before it is checked at all.
    static let band: CGFloat = 40
    /// How far past a guarded edge a quick drag is still caught.
    static let crossing: CGFloat = 60
    /// Where a carried drag lands on the display above, under its bottom edge.
    static let landing: CGFloat = 3

    /// A stretch of a display's top edge, and what a drag does there.
    struct Edge: Equatable {
        enum Kind: Equatable {
            /// Nothing above: kept one point under the edge.
            case hold
            /// A display above: carried onto it.
            case cross
        }

        let y: CGFloat
        let minX: CGFloat
        let maxX: CGFloat
        let kind: Kind
    }

    /// Each display's top edge, split where a display lies above part of it.
    static func edges(displays: [CGRect]) -> [Edge] {
        var edges: [Edge] = []
        for display in displays {
            // The stretches of this top edge that a display above covers.
            let above = displays
                .filter { $0 != display && abs($0.maxY - display.minY) < 1 && $0.minX < display.maxX && $0.maxX > display.minX }
                .map { (max($0.minX, display.minX), min($0.maxX, display.maxX)) }
                .sorted { $0.0 < $1.0 }
            var x = display.minX
            for (start, end) in above {
                if start > x { edges.append(Edge(y: display.minY, minX: x, maxX: start, kind: .hold)) }
                edges.append(Edge(y: display.minY, minX: max(start, x), maxX: end, kind: .cross))
                x = max(x, end)
            }
            if x < display.maxX { edges.append(Edge(y: display.minY, minX: x, maxX: display.maxX, kind: .hold)) }
        }
        return edges
    }

    /// The edge the point is near: over its stretch, from a little past it to
    /// `band` under it. Displays stacked on top of each other have edges over
    /// the same x; the height tells them apart.
    private static func edge(near point: CGPoint, in edges: [Edge], kind: Edge.Kind? = nil) -> Edge? {
        edges.first {
            (kind == nil || $0.kind == kind) && point.x >= $0.minX && point.x < $0.maxX
                && point.y >= $0.y - crossing && point.y < $0.y + band
        }
    }

    /// Whether the point is coming near a top edge.
    static func isNearTop(_ point: CGPoint, edges: [Edge]) -> Bool {
        edge(near: point, in: edges) != nil
    }

    /// Where a drag moving up (`deltaY` below zero) that reaches an edge with
    /// a display above lands on that display; nil otherwise. Coming down, the
    /// drag is left alone.
    static func carried(_ point: CGPoint, deltaY: CGFloat, edges: [Edge]) -> CGPoint? {
        guard deltaY < 0, let edge = edge(near: point, in: edges, kind: .cross), point.y < edge.y + 1,
              point.y > edge.y - landing
        else { return nil }
        return CGPoint(x: point.x, y: edge.y - landing)
    }

    /// The point kept one point under an edge with nothing above; nil when it
    /// is lower already, or under no such edge.
    static func kept(_ point: CGPoint, edges: [Edge]) -> CGPoint? {
        guard let edge = edge(near: point, in: edges, kind: .hold), point.y < edge.y + 1 else { return nil }
        return CGPoint(x: point.x, y: edge.y + 1)
    }

    /// How far under the edge the pointer has to come back before it is let go.
    static let releaseDepth: CGFloat = 4

    /// One step of a held drag: the cursor is held at `held`, one point under
    /// the edge at `edgeY`, and the mouse moved by `delta`. Where the cursor
    /// goes, and whether it is still held: let go once it comes back down, or
    /// leaves the held stretch sideways (toward a display above, say).
    static func heldStep(from held: CGPoint, delta: CGVector, edgeY: CGFloat,
                         edges: [Edge]) -> (point: CGPoint, held: Bool) {
        let next = CGPoint(x: held.x + delta.dx, y: held.y + delta.dy)
        let overHeld = edges.contains {
            $0.kind == .hold && abs($0.y - edgeY) < 0.5 && next.x >= $0.minX && next.x < $0.maxX
        }
        if next.y > edgeY + 1 + releaseDepth || !overHeld { return (next, false) }
        return (CGPoint(x: next.x, y: max(next.y, edgeY + 1)), true)
    }
}
