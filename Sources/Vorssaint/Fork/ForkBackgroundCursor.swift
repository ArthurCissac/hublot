// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lets this app set the pointer while another app is in front, for as long
/// as the capture menu is open. (Holding it whenever the pointer was over one
/// of the app's floating windows, the island or the menu bar panel, stopped
/// those windows from taking clicks: that use was taken out.) macOS only honors the cursor of the active
/// app; asking to become active is a request it may turn down, and the app in
/// front then puts its arrow back on every move, alternating with the menu's
/// crosshair pixel by pixel. Upstream's selection surface does the same
/// through the same window server property (its helper is private to its file).
enum ForkBackgroundCursor {
    private typealias ConnectionID = UInt32
    private typealias SetPropertyFunction = @convention(c) (ConnectionID, ConnectionID, CFString, CFTypeRef) -> Int32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
    }

    private static let connection: ConnectionID = {
        typealias Function = @convention(c) () -> ConnectionID
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: Function.self)()
    }()

    private static let setProperty: SetPropertyFunction? = {
        guard let symbol = symbol("CGSSetConnectionProperty") else { return nil }
        return unsafeBitCast(symbol, to: SetPropertyFunction.self)
    }()

    /// Who wants the permission: it holds while anyone does.
    enum Owner: Hashable {
        /// The capture menu, while it is open.
        case captureMenu
    }

    private static var owners: Set<Owner> = []

    /// Asked again on every call: upstream's selection turns the same
    /// property off when it ends, whoever else still needs it.
    static func setAllowed(_ allowed: Bool, by owner: Owner) {
        if allowed { owners.insert(owner) } else { owners.remove(owner) }
        guard connection != 0, let setProperty else { return }
        _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString,
                        owners.isEmpty ? kCFBooleanFalse : kCFBooleanTrue)
    }
}
