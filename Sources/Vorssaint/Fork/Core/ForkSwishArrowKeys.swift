// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Swish's arrow hotkeys: the super modifier with an arrow lays out the
/// frontmost window the way a swipe would. Left or right: that half. Up:
/// maximized. Down: minimized. Two arrows pressed one after the other reach
/// the corner between them. With the screen modifier as well, the window goes
/// to the display that way.
enum ForkSwishArrowKeys {
    typealias Direction = ForkTitleBarGestureLogic.Direction

    enum Arrow: CaseIterable, Equatable {
        case left, right, up, down

        /// The virtual key code of the arrow key.
        var keyCode: Int64 {
            switch self {
            case .left: return 123
            case .right: return 124
            case .down: return 125
            case .up: return 126
            }
        }

        var direction: Direction {
            switch self {
            case .left: return .left
            case .right: return .right
            case .up: return .up
            case .down: return .down
            }
        }
    }

    /// How soon the second arrow has to follow the first to reach a corner.
    static let chainWindow: TimeInterval = 0.6

    enum Action: Equatable {
        case layout(WindowLayoutAction)
        case minimize
        case display(Direction)
    }

    /// The arrows pressed so far, to tell a corner from two separate presses.
    struct Chain: Equatable {
        private(set) var last: Arrow?
        private(set) var lastTime: TimeInterval = 0

        /// What one press does. A press with the screen modifier is never part
        /// of a corner, and leaves no trace for the next press.
        mutating func press(_ arrow: Arrow, screen: Bool, at time: TimeInterval) -> Action {
            if screen {
                last = nil
                return .display(arrow.direction)
            }
            let previous = time - lastTime <= ForkSwishArrowKeys.chainWindow ? last : nil
            last = arrow
            lastTime = time
            if let corner = ForkSwishArrowKeys.corner(previous, arrow) {
                // A corner ends the chain: a third arrow starts afresh.
                last = nil
                return .layout(corner)
            }
            switch arrow {
            case .left: return .layout(.leftHalf)
            case .right: return .layout(.rightHalf)
            case .up: return .layout(.maximize)
            case .down: return .minimize
            }
        }
    }

    /// The corner two arrows in a row point to. Down never starts a corner:
    /// it has already minimized the window the next arrow would move.
    static func corner(_ first: Arrow?, _ second: Arrow) -> WindowLayoutAction? {
        switch (first, second) {
        case (.left, .up), (.up, .left): return .topLeft
        case (.right, .up), (.up, .right): return .topRight
        case (.left, .down): return .bottomLeft
        case (.right, .down): return .bottomRight
        default: return nil
        }
    }
}
