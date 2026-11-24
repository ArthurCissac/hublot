// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Mission Control, with a × on the window under the pointer and ⌘W, ⌘H,
/// ⌘Q acting on it. On macOS 27 WindowManager draws Mission Control and
/// tells accessibility about each window it shows: a button per window,
/// identified `<bundle id>.space.<n>`, titled like the window, framed where
/// the thumbnail is, with the window's number (see
/// docs/reference/mission-control-plus.md). Pure: the thumbnails, the
/// pointer and the keys come in, what to do goes out.
///
/// Accessibility coordinates: origin at the top left of the primary display,
/// y downward.
enum ForkMissionControlLogic {
    struct Thumbnail: Equatable {
        /// The window's number, when WindowManager gives it.
        let windowID: CGWindowID?
        let bundleID: String
        let title: String
        let frame: CGRect
    }

    /// The app of a thumbnail's identifier, `com.google.Chrome.space.5` giving
    /// `com.google.Chrome`; nil for what is not a window (the Spaces bar).
    static func bundleID(fromIdentifier identifier: String) -> String? {
        guard let range = identifier.range(of: ".space.", options: .backwards) else { return nil }
        let bundle = identifier[..<range.lowerBound]
        let number = identifier[range.upperBound...]
        guard !bundle.isEmpty, !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        return String(bundle)
    }

    /// The thumbnail under the pointer; the smallest when two overlap, as the
    /// smaller one is drawn on top while they rearrange.
    static func thumbnail(at point: CGPoint, in thumbnails: [Thumbnail]) -> Thumbnail? {
        thumbnails.filter { $0.frame.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// The × button, in points: a circle in the thumbnail's top left corner.
    static let buttonSize: CGFloat = 22
    static let buttonInset: CGFloat = 6

    static func closeButtonFrame(for thumbnail: CGRect) -> CGRect {
        CGRect(x: thumbnail.minX + buttonInset, y: thumbnail.minY + buttonInset,
               width: buttonSize, height: buttonSize)
    }

    enum Action: Equatable {
        case close, hide, quit
    }

    /// ⌘W closes the window, ⌘H hides its app, ⌘Q quits it. Command alone:
    /// with any other modifier the keys are left to macOS.
    static func action(keyCode: Int, command: Bool, otherModifiers: Bool) -> Action? {
        guard command, !otherModifiers else { return nil }
        switch keyCode {
        case 13: return .close  // W
        case 4: return .hide  // H
        case 12: return .quit  // Q
        default: return nil
        }
    }

    /// A two-finger pinch over a window quits its app once it has closed as
    /// far as a title bar pinch must (`ForkTitleBarGestureLogic`).
    static func pinchQuits(magnification: Double) -> Bool {
        magnification.isFinite && magnification <= -ForkTitleBarGestureLogic.pinchThreshold
    }

    /// Whether a pinch under way leans toward quitting, to light the × up.
    static func pinchLeans(magnification: Double) -> Bool {
        magnification.isFinite && magnification < -0.03
    }

    /// One window of the window list, as far as the watch needs it.
    struct WindowInfo: Equatable {
        let owner: String
        let layer: Int
        let bounds: CGRect
    }

    /// Whether Mission Control (or App Exposé) is on screen: WindowManager
    /// covers a display at layer 19 on macOS 27; earlier systems had the Dock
    /// at layer 18.
    static func overviewIsOpen(windows: [WindowInfo], displays: [CGRect]) -> Bool {
        windows.contains { window in
            guard (window.owner == "WindowManager" && window.layer == 19)
                    || (window.owner == "Dock" && window.layer == 18) else { return false }
            return displays.contains { window.bounds.width >= $0.width - 1 && window.bounds.height >= $0.height - 1 }
        }
    }

    /// A rectangle in accessibility coordinates, in AppKit's (y upward from
    /// the primary display's bottom).
    static func appKitRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// An AppKit point in accessibility coordinates.
    static func accessibilityPoint(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
