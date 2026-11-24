// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The editor's crop tool made simpler (see `ForkCropGeometry`): grips of a
/// fixed size on screen, every edge taken along its length, a ratio menu,
/// the thirds and the size while an edge is pulled. Return, a double click in
/// the frame or another tool applies it; Escape or Cancel leaves it.
///
/// Upstream's editor calls in at a few lines, each a no-op while the setting
/// is off: the editor then works exactly as upstream's. Main thread only,
/// like the editor. What upstream's gestures and cursor call is here, in
/// Core, with plain values: the test harness compiles those methods against
/// stand-ins for the editor. The views and what needs the editor itself are
/// in Fork/ForkCropEditor.swift.
enum ForkCropTool {
    typealias Handle = ScreenshotSupport.Handle

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.forkEditorCrop) }

    /// The ratio picked last, kept while the app runs.
    static var ratio = ForkCropGeometry.Ratio.free
    /// An edge or a new crop is being pulled: the thirds and the size show.
    private(set) static var isAdjusting = false
    private static var taps = ForkCropGeometry.TapTracker()

    // MARK: - Pointer, called by upstream's editor model

    /// The grip under a press; nil while the setting is off, or none is near.
    static func handle(at point: CGPoint, rect: CGRect, zoom: CGFloat) -> Handle? {
        guard isEnabled else { return nil }
        return ForkCropGeometry.grip(at: point, in: rect, zoom: zoom)
    }

    /// The crop as an edge or a corner is dragged: kept to the ratio picked,
    /// or to its own when Shift is held on a corner. Nil while the setting is off.
    static func resized(_ origin: CGRect, dragging handle: Handle, to point: CGPoint, imageSize: CGSize) -> CGRect? {
        guard isEnabled else { return nil }
        isAdjusting = true
        let corner = [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle)
        let held = corner && NSEvent.modifierFlags.contains(.shift) && origin.height > 0
            ? origin.width / origin.height : nil
        return ForkCropGeometry.resized(origin, dragging: handle, to: point,
                                        ratio: ratio.value(imageSize: imageSize) ?? held,
                                        within: CGRect(origin: .zero, size: imageSize))
    }

    /// A new crop drawn by a drag, kept to the ratio picked. Nil while the setting is off.
    static func drawn(from origin: CGPoint, to point: CGPoint, imageSize: CGSize) -> CGRect? {
        guard isEnabled else { return nil }
        isAdjusting = true
        return ForkCropGeometry.drawn(from: origin, to: point, ratio: ratio.value(imageSize: imageSize),
                                      within: CGRect(origin: .zero, size: imageSize))
    }

    /// The end of a press: whether it was the second click of a double click
    /// inside a crop smaller than the picture, which applies it.
    static func endDrag(at point: CGPoint, isTap: Bool, draft: CGRect?, imageSize: CGSize) -> Bool {
        isAdjusting = false
        guard isEnabled, isTap else {
            taps.reset()
            return false
        }
        guard let draft, draft.contains(point),
              draft.standardized != CGRect(origin: .zero, size: imageSize) else {
            taps.reset()
            return false
        }
        return taps.isDouble(at: point, time: ProcessInfo.processInfo.systemUptime,
                             interval: NSEvent.doubleClickInterval, slop: 6)
    }

    /// The pointer over the crop: the resize cursor of the grip under it, an
    /// open hand inside a crop it can move. False when not cropping.
    static func setCursor(tool: ScreenshotSupport.Tool, draft: CGRect?, imageSize: CGSize, zoom: CGFloat,
                          at point: CGPoint) -> Bool {
        guard isEnabled, tool == .crop, let draft else { return false }
        if let grip = ForkCropGeometry.grip(at: point, in: draft, zoom: zoom) {
            cursor(for: grip).set()
        } else if draft.contains(point), draft.standardized != CGRect(origin: .zero, size: imageSize) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
        return true
    }

    private static func cursor(for grip: Handle) -> NSCursor {
        switch grip {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default:
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition
                switch grip {
                case .topLeft: position = .topLeft
                case .topRight: position = .topRight
                case .bottomLeft: position = .bottomLeft
                default: position = .bottomRight
                }
                return .frameResize(position: position, directions: .all)
            }
            return .crosshair
        }
    }
}
