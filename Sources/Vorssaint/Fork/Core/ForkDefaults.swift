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
    /// Scrolling captures show the fork's controls, with an auto-scroll steered by the pointer.
    static let forkScrollingControls = "forkScrollingControls"
    /// The editor's crop has large grips, ratios and the thirds (ForkCropTool).
    static let forkEditorCrop = "forkEditorCrop"
    /// Mission Control shows a × on the window under the pointer; ⌘W, ⌘H and ⌘Q act on it.
    static let forkMissionControlPlus = "forkMissionControlPlus"
    /// Three fingers down in Chrome leave a video's full screen, and bring it back.
    static let forkChromeFullscreenSwipe = "forkChromeFullscreenSwipe"
    /// Battery alerts at several levels, with a banner and a sound (lot 8).
    static let forkBatteryAlerts = "forkBatteryAlerts"
    /// A sound when the charger is plugged in or out.
    static let forkPowerSounds = "forkPowerSounds"
    /// The device whose battery the menu bar shows, by name; empty for the lowest.
    static let forkPinnedBatteryDevice = "forkPinnedBatteryDevice"
    /// A battery item of its own in the menu bar, opening a panel like Juicy's.
    static let forkBatteryStatusItem = "forkBatteryStatusItem"
    /// How far the low battery halo reaches in: thin, medium or large.
    static let forkBatteryHaloSize = "forkBatteryHaloSize"
    /// The battery alerts, one by one, as JSON (`ForkBatteryAlertRules`); empty for Juicy's defaults.
    static let forkBatteryAlertRules = "forkBatteryAlertRules"
    /// The menu bar battery: the level inside, coloured by level, percent, time or both, large.
    static let forkBatteryIconNumber = "forkBatteryIconNumber"
    static let forkBatteryIconColors = "forkBatteryIconColors"
    static let forkBatteryIconText = "forkBatteryIconText"
    static let forkBatteryIconLarge = "forkBatteryIconLarge"
    /// The devices pinned beside the battery, by name, in order (JSON); the single pin above is the first.
    static let forkPinnedBatteryDevices = "forkPinnedBatteryDevices"
    /// The battery panel's cards: their order, the folded ones, the chart's hours.
    static let forkBatteryPanelOrder = "forkBatteryPanelOrder"
    static let forkBatteryPanelCollapsed = "forkBatteryPanelCollapsed"
    static let forkBatteryChartHours = "forkBatteryChartHours"
    /// An alert when an app draws at least the threshold (watts) for minutes on battery.
    static let forkAppEnergyAlerts = "forkAppEnergyAlerts"
    static let forkAppEnergyThreshold = "forkAppEnergyThreshold"
    /// The period the panel's energy card shows: live, day, week or month.
    static let forkAppEnergyPeriod = "forkAppEnergyPeriod"
    /// A global shortcut opens the battery panel (⌃⌥J unless changed; stored as GlobalShortcut text).
    static let forkBatteryShortcutEnabled = "forkBatteryShortcutEnabled"
    static let forkBatteryShortcut = "forkBatteryShortcut"
    /// The island's battery activity was turned off once for the charger pills.
    static let forkNotchBatteryMigrated = "forkNotchBatteryMigrated"  // not registered
    /// The Hublot icon in the menu bar cut to its ink, without upstream's empty sides.
    static let forkTightMenuBarIcon = "forkTightMenuBarIcon"
    /// The size of the alert pills: extraSmall, small, standard or large.
    static let forkBatteryPillSize = "forkBatteryPillSize"
    /// A pill when the charger is plugged in or out, with its watts.
    static let forkPowerAlertPill = "forkPowerAlertPill"
    /// The charger's sounds: `none`, `hublot.<sound>`, `system.<macOS sound>` or `file.<imported>`.
    static let forkPowerSoundPlugged = "forkPowerSoundPlugged"
    static let forkPowerSoundUnplugged = "forkPowerSoundUnplugged"
    /// The iPhones and iPads Hublot connects to, with their last level: this Mac's own.
    static let forkBluetoothDeviceCache = "forkBluetoothDeviceCache"  // not registered
    /// The old battery figure in the combined menu bar item was turned off once for the battery item.
    static let forkBatteryStatusItemMigrated = "forkBatteryStatusItemMigrated"  // not registered
    /// The Mac's battery level over the last 24 hours, for the panel's chart: this Mac's own.
    static let forkBatteryHistory = "forkBatteryHistory"  // not registered
    /// The Cleaner page offers the disk map and the antivirus (lot 9).
    static let forkCleanerTools = "forkCleanerTools"
    /// The maintenance jobs checked, by name (lot 9d).
    static let forkMaintenanceSelection = "forkMaintenanceSelection"
    /// When each maintenance job last went well, seconds since 1970 by name.
    static let forkMaintenanceLastRuns = "forkMaintenanceLastRuns"  // not registered
    /// Background sound: offered at all, its mix, its volume, its timer in
    /// minutes (0 never stops), its menu bar icon and its global shortcut.
    static let forkAmbientEnabled = "forkAmbientEnabled"
    static let forkAmbientMix = "forkAmbientMix"
    /// Named mixes kept by the user, as JSON (ForkAmbientLogic.Favorite).
    static let forkAmbientFavorites = "forkAmbientFavorites"
    /// Plays for a time (timer) or in Pomodoro cycles, and their work length in minutes.
    static let forkAmbientMode = "forkAmbientMode"
    static let forkAmbientPomodoroMinutes = "forkAmbientPomodoroMinutes"
    /// The sound holds during calls and while music plays.
    static let forkAmbientPauseForCalls = "forkAmbientPauseForCalls"
    static let forkAmbientPauseForMusic = "forkAmbientPauseForMusic"
    /// The closed island shows a wave while the sound plays.
    static let forkAmbientIslandActivity = "forkAmbientIslandActivity"
    /// The closed island draws a little scene for what plays, rather than the wave.
    static let forkAmbientScenes = "forkAmbientScenes"
    static let forkAmbientVolume = "forkAmbientVolume"
    static let forkAmbientTimer = "forkAmbientTimer"
    static let forkAmbientMenuBarIcon = "forkAmbientMenuBarIcon"
    static let forkAmbientShortcutEnabled = "forkAmbientShortcutEnabled"
    static let forkAmbientShortcut = "forkAmbientShortcut"
    /// The island control was taken off the hidden controls once.
    static let forkAmbientIslandShown = "forkAmbientIslandShown"  // not registered
    /// The antivirus checks for new signatures once a day, in the background.
    static let forkAntivirusAutoUpdate = "forkAntivirusAutoUpdate"
    /// When a signature check last succeeded, found something or not.
    static let forkAntivirusLastCheck = "forkAntivirusLastCheck"  // not registered
    /// Each finished new item of Downloads is scanned by the antivirus.
    static let forkAntivirusWatchDownloads = "forkAntivirusWatchDownloads"
    /// The one-click scan runs by itself: "off", "weekly" or "daily".
    static let forkSmartScanSchedule = "forkSmartScanSchedule"
    /// Its day (the Gregorian weekday, 1 for Sunday) and its hour.
    static let forkSmartScanWeekday = "forkSmartScanWeekday"
    static let forkSmartScanHour = "forkSmartScanHour"
    /// When the schedule last ran a scan, or last changed.
    static let forkSmartScanLastAuto = "forkSmartScanLastAuto"  // not registered
    /// The format the capture menu holds its area to, as an index in its list.
    static let forkCaptureMenuFormat = "forkCaptureMenuFormat"
    /// The last area framed, in global points. A place on this Mac's displays.
    static let forkCaptureMenuLastArea = "forkCaptureMenuLastArea"  // not registered
    /// The shortcut that brings back the last capture card put away.
    static let forkReopenPreviewShortcutEnabled = "forkReopenPreviewShortcutEnabled"
    static let forkReopenPreviewShortcut = "forkReopenPreviewShortcut"
    /// A global shortcut hides every capture preview card, and shows them again.
    static let forkHidePreviewsShortcutEnabled = "forkHidePreviewsShortcutEnabled"
    static let forkHidePreviewsShortcut = "forkHidePreviewsShortcut"
    /// How many fingers the trackpad switcher gesture takes: 3 or 4.
    static let forkSwitcherTrackpadFingers = "forkSwitcherTrackpadFingers"
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
    /// The menu bar panel's simple menus: named tabs, tiles, state first, only what is of use.
    static let forkSimplePanels = "forkSimplePanels"
    /// The companion's idle activities, varied visits, wandering eyes and mood.
    static let forkMascotLively = "forkMascotLively"
    /// The companion follows the day: props by hour, season and focus, Todoist cheers and worries.
    static let forkMascotDay = "forkMascotDay"
    /// The minimal companion as a cat, a ghost, a pixel one or a blob ("classic" otherwise).
    static let forkMascotVariant = "forkMascotVariant"
    /// Rare speech bubbles, a mini keyboard while typing fast, the weather of a city.
    static let forkMascotBubbles = "forkMascotBubbles"
    static let forkMascotTyping = "forkMascotTyping"
    static let forkMascotWeather = "forkMascotWeather"
    static let forkMascotWeatherCity = "forkMascotWeatherCity"
    /// The day it last said hello.
    static let forkMascotGreetedDay = "forkMascotGreetedDay"  // not registered
    /// How much it was petted lately (0 to 100), and when that was last updated.
    static let forkMascotAffection = "forkMascotAffection"  // not registered
    static let forkMascotAffectionDate = "forkMascotAffectionDate"  // not registered
    /// Todoist's tasks in the island and the menu (the token lives in the Keychain).
    /// Vercel's deployments in the island (the token lives in the Keychain).
    static let forkVercelEnabled = "forkVercelEnabled"
    /// "all" (production and previews) or "production".
    static let forkVercelScope = "forkVercelScope"
    static let forkVercelNotifySuccess = "forkVercelNotifySuccess"
    static let forkVercelNotifyFailure = "forkVercelNotifyFailure"
    static let forkTodoistEnabled = "forkTodoistEnabled"
    /// Control-Option-N opens the tasks' panel; the shortcut itself, when changed.
    static let forkTodoistShortcutEnabled = "forkTodoistShortcutEnabled"
    static let forkTodoistShortcut = "forkTodoistShortcut"  // not registered
    /// The island's Weather page, its cities (JSON) and its ⌃⌥W shortcut.
    static let forkWeatherEnabled = "forkWeatherEnabled"
    static let forkWeatherCities = "forkWeatherCities"
    static let forkWeatherShortcutEnabled = "forkWeatherShortcutEnabled"
    static let forkWeatherShortcut = "forkWeatherShortcut"  // not registered
    /// The closed island shows the task being done, or a timed task near its time.
    static let forkTodoistIslandActivity = "forkTodoistIslandActivity"
    /// How many minutes before its time a task comes into the closed island (5, 15, 30 or 60).
    static let forkTodoistIslandLead = "forkTodoistIslandLead"
    /// A task with a time is recalled in the island when it comes.
    static let forkTodoistReminders = "forkTodoistReminders"
    /// The task being done now, pinned first; kept on this Mac only.
    static let forkTodoistActiveTask = "forkTodoistActiveTask"  // not registered
    /// The fork's quick action tiles taken off the menu, comma-separated.
    static let forkQuickActionsHidden = "forkQuickActionsHidden"
    /// The menu's tiles in the order arranged by hand, the fork's and upstream's mixed (ForkTileLayoutLogic).
    static let forkTileOrder = "forkTileOrder"
    /// The tiles' first setup (three of upstream's hidden) was done.
    static let forkQuickActionsSetUp = "forkQuickActionsSetUp"  // not registered
    /// What presentation mode changed, to put back; absent when it is off.
    static let forkPresentationSnapshot = "forkPresentationSnapshot"  // not registered
    /// Closing the lid in Keep Awake's closed-lid mode puts every display to
    /// sleep, the external ones included.
    static let forkLidSleepsDisplays = "forkLidSleepsDisplays"
    /// Dev server ports show a button with a QR code that opens them on a phone.
    static let forkLocalQREnabled = "forkLocalQREnabled"
    /// The command bar converts currencies with the European Central Bank's rates.
    static let forkCurrencyEnabled = "forkCurrencyEnabled"
    /// The currency an amount becomes when no target is typed ("1500 $").
    static let forkCurrencyTarget = "forkCurrencyTarget"
    /// While the island shows the volume, the volume keys move it in round steps of 5 %.
    static let forkVolumeRoundSteps = "forkVolumeRoundSteps"
    /// While the island shows the brightness, the brightness keys move it in round steps of 5 %.
    static let forkBrightnessRoundSteps = "forkBrightnessRoundSteps"
    /// The selected text, or the clipboard's, translated in the island's Translation page.
    static let forkTranslateEnabled = "forkTranslateEnabled"
    /// Control-Option-Command-T translates; the shortcut itself, when changed.
    static let forkTranslateShortcutEnabled = "forkTranslateShortcutEnabled"
    static let forkTranslateShortcut = "forkTranslateShortcut"  // not registered
    /// The language translations go to: "auto" (French into English, the rest into French) or a code such as "es".
    static let forkTranslateTarget = "forkTranslateTarget"
    /// The tool last shown in the Care window, to reopen it there.
    static let forkCareHubModule = "forkCareHubModule"  // not registered
    /// A notice in the island when a Claude Code session waits for an answer.
    static let forkAgentsWaitingAlert = "forkAgentsWaitingAlert"
    /// The AI page in Hublot's style: a widget per kind of information, on a grid that never scrolls.
    static let forkAgentsHublotStyle = "forkAgentsHublotStyle"
    /// Explorer shows all its tiles at once, the island growing taller for them.
    static let forkExplorerFitsAll = "forkExplorerFitsAll"
    /// Pages left out of Explorer (still in the island), by name.
    static let forkExplorerHidden = "forkExplorerHidden"
    /// The island's Home page (Home Assistant), its server's address and a fallback one,
    /// the favourite devices (entity ids, in order) and those also shown as menu tiles.
    /// The access token is kept in the Keychain, never here.
    static let forkHomeEnabled = "forkHomeEnabled"
    static let forkHomeURL = "forkHomeURL"
    static let forkHomeFallbackURL = "forkHomeFallbackURL"
    static let forkHomeFavorites = "forkHomeFavorites"
    static let forkHomeMenuTiles = "forkHomeMenuTiles"
    /// The Home page shows a 3D printer tile while the Printer page is on.
    static let forkHomeShowsPrinter = "forkHomeShowsPrinter"
    /// The island's Printer page (a Bambu Lab printer on the local network): its address, serial
    /// and name. The access code is kept in the Keychain, never here.
    static let forkBambuEnabled = "forkBambuEnabled"
    static let forkBambuHost = "forkBambuHost"
    static let forkBambuSerial = "forkBambuSerial"
    static let forkBambuName = "forkBambuName"
    /// The printer's certificate fingerprints, remembered at the first connection.
    static let forkBambuPins = "forkBambuPins"  // not registered
}
