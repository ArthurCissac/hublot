// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Preference keys the fork adds.
///
/// They carry a `fork` prefix so a key upstream introduces later can never
/// collide with one of them. Each one has its default in the fork's block at
/// the top of `Defaults.registeredDefaults`; being registered there is also
/// what makes a key travel in settings backups (Fork/check.sh verifies it).
extension DefaultsKey {
    /// Leave the desktop icons out of screenshots. The desktop itself is not touched.
    static let forkScreenshotExcludeDesktopIcons = "forkScreenshotExcludeDesktopIcons"
    /// The clipboard history opens as a shelf of cards along the bottom of the screen.
    static let forkClipboardShelf = "forkClipboardShelf"
    /// Two-finger swipes on a window's title bar lay it out; pinches close it or make it full screen.
    static let forkTitleBarSwipe = "forkTitleBarSwipe"
    static let forkTitleBarPinch = "forkTitleBarPinch"
    /// Three fingers swiped sideways on the trackpad open the window switcher.
    static let forkSwitcherTrackpadGesture = "forkSwitcherTrackpadGesture"
    /// The shelf in Liquid Glass (macOS 26 and later), its tint and how strongly it shows.
    static let forkClipboardShelfGlass = "forkClipboardShelfGlass"
    static let forkClipboardShelfTint = "forkClipboardShelfTint"
    static let forkClipboardShelfTintIntensity = "forkClipboardShelfTintIntensity"
    /// The sound played on each copy; empty for none.
    static let forkClipboardCopySound = "forkClipboardCopySound"
    /// How a window capture comes out: plain, with a shadow, or on a background.
    static let forkWindowCaptureStyle = "forkWindowCaptureStyle"
    /// Play the system's screen-capture sound when a screenshot is taken.
    static let forkScreenshotCaptureSound = "forkScreenshotCaptureSound"
    /// Show the capture preview as a card at the bottom left of the pointer's
    /// display, in place of the standard preview and of the island's.
    static let forkScreenshotPreviewCard = "forkScreenshotPreviewCard"
    /// Whether the capture menu answers its global shortcut.
    static let forkCaptureMenuShortcutEnabled = "forkCaptureMenuShortcutEnabled"
    /// The capture menu's global shortcut, in `GlobalShortcut` storage form.
    static let forkCaptureMenuShortcut = "forkCaptureMenuShortcut"
    /// The capture menu's items, in order, a hidden one marked with "!" (ForkCaptureMenuLayout.items).
    static let forkCaptureMenuItems = "forkCaptureMenuItems"
    /// What the capture menu shows first: its bar alone, the last area, or a selection.
    static let forkCaptureMenuOpening = "forkCaptureMenuOpening"
    /// The menu's Area item photographs an area as soon as it is drawn.
    static let forkCaptureMenuAreaAtOnce = "forkCaptureMenuAreaAtOnce"
    /// What a recording from the capture menu films: an area, a window or the whole display.
    static let forkRecorderScope = "forkRecorderScope"
    /// A dragged item is kept one point under the top edge, so macOS does not open Mission Control.
    static let forkDragTopGuard = "forkDragTopGuard"
    /// Scrolling captures from the capture menu go sideways.
    static let forkScrollingHorizontal = "forkScrollingHorizontal"
    /// The format the capture menu holds its area to, as an index in its list.
    static let forkCaptureMenuFormat = "forkCaptureMenuFormat"
    /// The last area framed, in global points. A place on this Mac's displays.
    static let forkCaptureMenuLastArea = "forkCaptureMenuLastArea"  // not registered
    /// The shortcut that brings back the last capture card put away.
    static let forkReopenPreviewShortcutEnabled = "forkReopenPreviewShortcutEnabled"
    static let forkReopenPreviewShortcut = "forkReopenPreviewShortcut"
    /// Export a recording's sound in mono rather than in stereo.
    static let forkRecorderMonoAudio = "forkRecorderMonoAudio"
    /// Show a ring on each click in new recordings.
    static let forkRecorderShowsClicks = "forkRecorderShowsClicks"
    /// Show the keys pressed while recording, as captions; all keys, or only shortcuts.
    static let forkRecorderShowsKeys = "forkRecorderShowsKeys"
    static let forkRecorderAllKeys = "forkRecorderAllKeys"
    /// Turn Do Not Disturb on while recording, through two shortcuts of the Shortcuts app.
    static let forkRecorderDoNotDisturb = "forkRecorderDoNotDisturb"
    /// Show the camera bubble while recording.
    static let forkRecorderCamera = "forkRecorderCamera"
    /// The camera bubble's shape: circle, square or rectangle.
    static let forkRecorderCameraShape = "forkRecorderCameraShape"
    /// The camera bubble's height, in points.
    static let forkRecorderCameraSize = "forkRecorderCameraSize"
    /// The microphone chosen for recordings; empty means the Mac's own. A device of one Mac, so it
    /// is deliberately left without a registered default: that keeps it out of settings backups.
    static let forkRecorderMicrophoneID = "forkRecorderMicrophoneID"  // not registered
    /// Swish's modifiers, as raw event flag masks (ForkSwishModifiers).
    static let forkSwishGeneralModifier = "forkSwishGeneralModifier"
    static let forkSwishScreenModifier = "forkSwishScreenModifier"
    static let forkSwishSecondaryModifier = "forkSwishSecondaryModifier"
    static let forkSwishTertiaryModifier = "forkSwishTertiaryModifier"
    static let forkSwishSuperModifier = "forkSwishSuperModifier"
    /// The super modifier and an arrow key lay out the frontmost window.
    static let forkSwishArrowKeys = "forkSwishArrowKeys"
    /// The pointer follows a window sent to another display.
    static let forkSwishMoveCursor = "forkSwishMoveCursor"
    /// Gestures only with the super modifier held.
    static let forkSwishRequireSuper = "forkSwishRequireSuper"
    /// Hold back a gesture's scroll and pinch events from the window underneath.
    static let forkSwishActiveListener = "forkSwishActiveListener"
    /// Two fingers tapped twice on the title bar center the window.
    static let forkSwishDoubleTap = "forkSwishDoubleTap"
    /// The trackpad taps once when a gesture acts.
    static let forkSwishHaptics = "forkSwishHaptics"
    /// How short a swipe may be, from 1 (calm) to 5 (lively).
    static let forkSwishSensitivity = "forkSwishSensitivity"
    /// Fingers resting this long, in seconds, call the gesture off; 0 never.
    static let forkSwishCancelTimeout = "forkSwishCancelTimeout"
    /// During a swipe, a translucent frame shows where the window will go.
    static let forkSwishPreview = "forkSwishPreview"
    /// Swipes and pinches over a Dock icon act on that app's windows.
    static let forkSwishDockGestures = "forkSwishDockGestures"
    /// During a gesture, a bubble by the pointer says what it will do.
    static let forkSwishBubble = "forkSwishBubble"
    /// During a swipe, the window glides to where the gesture would put it.
    static let forkSwishLiveMove = "forkSwishLiveMove"
    /// Lyrics of the same song and album are accepted up to eight seconds off its length.
    static let forkLyricsNearbyDuration = "forkLyricsNearbyDuration"
    /// The island's queue page reads Spotify's queue through its Web API.
    static let forkSpotifyQueue = "forkSpotifyQueue"
    /// The client ID of the user's own app on developer.spotify.com. Public, not a secret
    /// (PKCE): the tokens it obtains live in the Keychain only, never in preferences.
    static let forkSpotifyClientID = "forkSpotifyClientID"
}
