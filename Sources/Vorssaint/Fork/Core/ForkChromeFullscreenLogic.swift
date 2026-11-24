// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Three fingers swiped down in Chrome: a video in full screen leaves it, so
/// the tabs are back; the same swipe later brings that tab back and puts the
/// video in full screen again. Pure: the trackpad's frames come in, a swipe
/// goes out; the scripts Chrome runs are built here from numbers only.
enum ForkChromeFullscreenLogic {
    static let chromeBundleID = "com.google.Chrome"

    /// Recognizes three fingers going down the trackpad, fed MultitouchSupport's
    /// frames: how many fingers, and where their centre is, from 0 to 1 across
    /// the pad (y upward, as MultitouchSupport reports it).
    struct DownSwipe: Equatable {
        /// How far down, as a share of the pad's height, the fingers travel.
        static let distance: Float = 0.14
        /// Sideways or upward travel past this calls the gesture off.
        static let drift: Float = 0.10

        private enum State: Equatable {
            case idle
            case watching(startX: Float, startY: Float)
            /// Done, or not this gesture: nothing until the pad is empty.
            case waiting
        }

        private var state = State.idle

        /// True once, when three fingers have gone far enough down.
        mutating func feed(fingers: Int, center: (x: Float, y: Float)?) -> Bool {
            switch state {
            case .idle:
                guard fingers == 3, let center else { return false }
                state = .watching(startX: center.x, startY: center.y)
                return false
            case let .watching(startX, startY):
                guard fingers == 3 else {
                    state = fingers == 0 ? .idle : .waiting
                    return false
                }
                guard let center else { return false }
                let dx = center.x - startX, dy = center.y - startY
                if abs(dx) > Self.drift || dy > Self.drift {
                    state = .waiting
                    return false
                }
                guard dy <= -Self.distance, abs(dy) > abs(dx) * 1.5 else { return false }
                state = .waiting
                return true
            case .waiting:
                if fingers == 0 { state = .idle }
                return false
            }
        }
    }

    /// Whether macOS already takes three fingers down (App Exposé): then the
    /// swipe is left to it.
    static func systemUsesThreeFingersDown(verticalSwipe: Int?, appExposeGesture: Bool?) -> Bool {
        (verticalSwipe ?? 0) != 0 && appExposeGesture == true
    }

    /// The tab a video left full screen from: Chrome's window and tab ids.
    struct VideoTab: Equatable {
        let windowID: Int
        let tabID: Int
    }

    /// Asks Chrome for its front window and that window's tab.
    static let frontTabScript = """
        tell application id "\(chromeBundleID)"
            if (count of windows) is 0 then return ""
            set frontWindow to front window
            return ((id of frontWindow) as text) & "," & ((id of active tab of frontWindow) as text)
        end tell
        """

    /// Chrome's answer to `frontTabScript`.
    static func videoTab(fromReply reply: String) -> VideoTab? {
        let parts = reply.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let window = Int(parts[0]), let tab = Int(parts[1]), window > 0, tab > 0 else { return nil }
        return VideoTab(windowID: window, tabID: tab)
    }

    /// Brings that tab back in front, in its window; answers "ok" or "missing".
    /// Only numbers go into the script.
    static func showTabScript(_ tab: VideoTab) -> String {
        """
        tell application id "\(chromeBundleID)"
            repeat with candidateWindow in windows
                if (id of candidateWindow) is \(tab.windowID) then
                    set tabNumber to 0
                    repeat with candidateTab in tabs of candidateWindow
                        set tabNumber to tabNumber + 1
                        if (id of candidateTab) is \(tab.tabID) then
                            set active tab index of candidateWindow to tabNumber
                            set index of candidateWindow to 1
                            return "ok"
                        end if
                    end repeat
                end if
            end repeat
            return "missing"
        end tell
        """
    }
}
