// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Swish's gestures on a Dock icon, as pure choices: where the Dock can be,
/// what a swipe or a pinch over an app's icon does, and which window comes
/// forward when going through an app's windows.
enum ForkSwishDock {
    typealias Direction = ForkTitleBarGestureLogic.Direction

    /// How deep the band along the Dock's edge is where a gesture may be on an
    /// icon, in points: deeper than the Dock at its largest, so an icon
    /// magnified under the pointer still counts.
    static let band: CGFloat = 130

    /// Whether a point (AppKit coordinates) lies in the band along the edge of
    /// this display where the Dock sits ("bottom", "left" or "right", as the
    /// Dock's own preferences say).
    static func isInBand(_ point: CGPoint, screen: CGRect, orientation: String?) -> Bool {
        guard screen.contains(point) else { return false }
        switch orientation {
        case "left": return point.x <= screen.minX + band
        case "right": return point.x >= screen.maxX - band
        default: return point.y <= screen.minY + band
        }
    }

    enum Gesture: Equatable {
        /// Bring the app's next window forward, or its last one.
        case cycle(forward: Bool)
        /// Minimize the app's front window, or all of them.
        case minimize(all: Bool)
        /// Bring back the app's last minimized window, or all of them.
        case unminimize(all: Bool)
        case quit
    }

    /// What a swipe over an icon does. Plain: left and right go through the
    /// app's windows, down minimizes, up brings back. Secondary modifier: down
    /// and up act on every window. General modifier: down quits.
    static func gesture(for direction: Direction, role: ForkSwishModifiers.Role) -> Gesture? {
        switch (role, direction) {
        case (.none, .left): return .cycle(forward: false)
        case (.none, .right): return .cycle(forward: true)
        case (.none, .down): return .minimize(all: false)
        case (.none, .up): return .unminimize(all: false)
        case (.secondary, .down): return .minimize(all: true)
        case (.secondary, .up): return .unminimize(all: true)
        case (.general, .down): return .quit
        default: return nil
        }
    }

    /// A pinch over an icon: closed, the app quits.
    static func gesture(forPinch magnification: Double) -> Gesture? {
        ForkTitleBarGestureLogic.gesture(forPinch: magnification) == .close ? .quit : nil
    }

    /// The window to bring forward among an app's windows, front to back: the
    /// one behind the front window going forward, the backmost going back.
    static func cycleTarget(_ windows: [UInt32], forward: Bool) -> UInt32? {
        guard windows.count >= 2 else { return nil }
        return forward ? windows[1] : windows.last
    }
}
