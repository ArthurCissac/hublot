// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Gestures on a window's title bar, the way Swish does them: two fingers
/// swiped on the title bar lay the window out (left or right half, a corner
/// quarter, maximized, minimized, or, with Shift, onto the next display),
/// and a pinch closes it or makes it full screen. Pure choices: the events
/// come in as plain numbers.
enum ForkTitleBarGestureLogic {
    /// From a window's top edge, how far down a gesture still counts as on the
    /// title bar: a plain title bar, or one merged with a toolbar.
    static let titleBand: CGFloat = 52
    /// How far the fingers travel before a swipe counts.
    static let swipeThreshold: CGFloat = 50
    /// How much a pinch must open or close before it counts.
    static let pinchThreshold: Double = 0.35

    /// Whether a point, in screen coordinates with a top-left origin, is on
    /// the title bar of a window with this frame (same coordinates).
    static func isOnTitleBar(_ point: CGPoint, windowFrame frame: CGRect) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.minY + min(titleBand, frame.height)
    }

    /// The fingers' movement for one scroll event, x to the right and y up,
    /// whatever the scrolling direction set in System Settings.
    static func fingerMovement(scrollDeltaX: CGFloat, scrollDeltaY: CGFloat, naturalScrolling: Bool) -> CGVector {
        // With natural scrolling the content follows the fingers: a positive
        // vertical delta is content, and fingers, moving down.
        let sign: CGFloat = naturalScrolling ? 1 : -1
        return CGVector(dx: sign * scrollDeltaX, dy: -sign * scrollDeltaY)
    }

    enum Direction: Equatable, CaseIterable {
        case right, upRight, up, upLeft, left, downLeft, down, downRight
    }

    /// How far a swipe travels before it counts, for Swish's sensitivity from
    /// 1 (calm: farther) to 5 (lively: shorter).
    static func swipeThreshold(sensitivity: Int) -> CGFloat {
        let distances: [CGFloat] = [70, 60, 50, 40, 32]
        return distances[max(1, min(5, sensitivity)) - 1]
    }

    /// Whether the fingers rested long enough before lifting to call the
    /// gesture off, as Swish's cancel timeout does.
    static func rested(lastMoved: TimeInterval, now: TimeInterval, timeout: TimeInterval) -> Bool {
        timeout > 0 && now - lastMoved >= timeout
    }

    /// The direction of a whole swipe, in eight sectors of 45°, or nil when
    /// the fingers did not travel far enough.
    static func direction(of travel: CGVector, threshold: CGFloat = swipeThreshold) -> Direction? {
        let length = hypot(travel.dx, travel.dy)
        guard length >= threshold, length.isFinite else { return nil }
        var degrees = atan2(Double(travel.dy), Double(travel.dx)) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let sector = Int(((degrees + 22.5) / 45).rounded(.down)) % 8
        return Direction.allCases[sector]
    }

    enum Gesture: Equatable {
        case layout(WindowLayoutAction)
        case minimize
        case close
        /// The display that lies this way, where the Displays settings put it.
        case display(Direction)
        /// One cell of a 3×3 grid, counted from the top left.
        case ninth(column: Int, row: Int)
    }

    /// What a swipe does with the modifiers held. Plain: halves to the sides,
    /// quarters to the corners, maximized up, minimized down. Screen modifier:
    /// the display that way. General: closed down, almost full screen up.
    /// Secondary: the 3×2 grid's corners, the top and bottom halves, the side
    /// thirds. Tertiary: the 3×3 grid's outer cells.
    static func gesture(for direction: Direction, role: ForkSwishModifiers.Role) -> Gesture? {
        switch role {
        case .none: break
        case .screen:
            return [.left, .right, .up, .down].contains(direction) ? .display(direction) : nil
        case .general:
            switch direction {
            case .down: return .close
            case .up: return .layout(.marginMaximize)
            default: return nil
            }
        case .secondary:
            switch direction {
            case .upLeft: return .layout(.topLeftSixth)
            case .upRight: return .layout(.topRightSixth)
            case .downLeft: return .layout(.bottomLeftSixth)
            case .downRight: return .layout(.bottomRightSixth)
            case .up: return .layout(.topHalf)
            case .down: return .layout(.bottomHalf)
            case .left: return .layout(.leftThird)
            case .right: return .layout(.rightThird)
            }
        case .tertiary:
            let cells: [Direction: (Int, Int)] = [.upLeft: (0, 0), .up: (1, 0), .upRight: (2, 0), .left: (0, 1),
                                                  .right: (2, 1), .downLeft: (0, 2), .down: (1, 2), .downRight: (2, 2)]
            return cells[direction].map { .ninth(column: $0.0, row: $0.1) }
        }
        switch direction {
        case .left: return .layout(.leftHalf)
        case .right: return .layout(.rightHalf)
        case .up: return .layout(.maximize)
        case .down: return .minimize
        case .upLeft: return .layout(.topLeft)
        case .upRight: return .layout(.topRight)
        case .downLeft: return .layout(.bottomLeft)
        case .downRight: return .layout(.bottomRight)
        }
    }

    /// What a pinch does once it is over: closed far enough, the window
    /// closes; opened far enough, it goes full screen.
    static func gesture(forPinch magnification: Double) -> Gesture? {
        guard magnification.isFinite else { return nil }
        if magnification <= -pinchThreshold { return .close }
        if magnification >= pinchThreshold { return .layout(.fullScreen) }
        return nil
    }

    /// The phases a trackpad reports with a scroll or a pinch.
    enum Phase: Equatable {
        case began, changed, ended, cancelled, other

        init(raw: Int64) {
            switch raw {
            case 1, 128: self = .began
            case 2: self = .changed
            case 4: self = .ended
            case 8: self = .cancelled
            default: self = .other
            }
        }
    }

    /// Closing that turns into quitting when done twice in a row on the same
    /// window, as Swish does. The first close waits a moment; a second gesture
    /// starting on that window within it holds the close back until it ends:
    /// a close then quits the app, anything else lets the window close.
    struct Twice: Equatable {
        /// How soon after the first close the second gesture has to start.
        static let window: TimeInterval = 0.4
        private var pendingID: UInt32?
        private var pendingTime: TimeInterval = 0
        /// A second gesture is under way on the window waiting to close.
        private(set) var holding = false

        enum Decision: Equatable {
            /// Close the window once the moment has passed without a second.
            case closeLater
            /// The second in time: quit the app instead.
            case quit
        }

        /// A gesture starts on a window. True when it follows a close of that
        /// window closely enough: the close now waits for this gesture's end.
        mutating func begin(window id: UInt32, at time: TimeInterval) -> Bool {
            guard pendingID == id, time - pendingTime <= Self.window else { return false }
            holding = true
            return true
        }

        mutating func close(window id: UInt32, at time: TimeInterval) -> Decision {
            if holding, pendingID == id {
                pendingID = nil
                holding = false
                return .quit
            }
            pendingID = id
            pendingTime = time
            holding = false
            return .closeLater
        }

        /// The gesture that held a close back ended as something else, or was
        /// called off. True when that close must happen now.
        mutating func release() -> Bool {
            let held = holding
            holding = false
            if held { pendingID = nil }
            return held
        }
    }

    /// One gesture being followed: what it is on, and how far it has gone.
    struct Tracker: Equatable {
        var travel = CGVector.zero
        var magnification: Double = 0
        /// When the fingers last moved, in seconds of system uptime.
        var lastMoved: TimeInterval = 0

        mutating func add(_ movement: CGVector) {
            travel.dx += movement.dx
            travel.dy += movement.dy
        }

        mutating func add(magnification change: Double) {
            guard change.isFinite else { return }
            magnification += change
        }
    }
}
