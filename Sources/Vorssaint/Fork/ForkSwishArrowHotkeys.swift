// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit

/// Swish's arrow hotkeys: the super modifier (⌘) and an arrow lay out the
/// frontmost window; with the screen modifier (⇧) as well, the window goes
/// to the display that way.
///
/// Eight Carbon hotkeys, held only while the feature is wanted, the window
/// layout feature available, Accessibility granted and the frontmost app not
/// one the window layout settings leave alone: there the arrows keep their
/// usual meaning, as upstream does for its own window shortcuts.
final class ForkSwishArrowHotkeys: ObservableObject {
    typealias Keys = ForkSwishArrowKeys

    static let shared = ForkSwishArrowHotkeys()

    /// Whether macOS refused one of the combinations (another app holds it).
    @Published private(set) var registrationFailed = false

    private var hotkeys: [(hotkey: QuickToolHotkey, arrow: Keys.Arrow, screen: Bool)] = []
    private var chain = Keys.Chain()
    private var observers: [NSObjectProtocol] = []
    private lazy var resync = ForkCoalescedMainAction { [weak self] in self?.sync() }

    private init() {
        // Ids out of upstream's quick-tool range, after the fork's 9_101 and 9_102.
        for (index, arrow) in Keys.Arrow.allCases.enumerated() {
            for screen in [false, true] {
                let hotkey = QuickToolHotkey(id: UInt32(9_110 + index * 2 + (screen ? 1 : 0)))
                hotkeys.append((hotkey, arrow, screen))
            }
        }
    }

    func start() {
        for entry in hotkeys {
            entry.hotkey.onPress = { [weak self] in self?.press(entry.arrow, screen: entry.screen) }
        }
        DispatchQueue.main.async { [weak self] in self?.sync() }
        let center = NotificationCenter.default
        for name in [UserDefaults.didChangeNotification, NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification] {
            // Never from inside the notification: see ForkCoalescedMainAction.
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.resync.schedule() })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.resync.schedule() })
    }

    func sync() {
        let defaults = UserDefaults.standard
        let frontmostIgnored = NSWorkspace.shared.frontmostApplication.map(ForkSwishWindowOps.isIgnored) ?? false
        let enabled = defaults.bool(forKey: DefaultsKey.forkSwishArrowKeys) && AppFeature.windowLayout.isAvailable
            && AXIsProcessTrusted() && !frontmostIgnored
        let superKey = GlobalShortcutModifiers(cgFlags: CGEventFlags(rawValue: UInt64(defaults.integer(forKey: DefaultsKey.forkSwishSuperModifier))))
        let screenKey = GlobalShortcutModifiers(cgFlags: CGEventFlags(rawValue: UInt64(defaults.integer(forKey: DefaultsKey.forkSwishScreenModifier))))
        // Carbon hotkeys cannot hold fn: a super modifier made of fn alone has no hotkeys.
        let usable = enabled && !superKey.isEmpty
        var failed = false
        for entry in hotkeys {
            let modifiers = entry.screen ? superKey.union(screenKey) : superKey
            let wanted = usable && (!entry.screen || !screenKey.isEmpty)
            let shortcut = GlobalShortcut(keyCode: entry.arrow.keyCode, modifiers: modifiers)
            let key = "forkSwishArrow.\(entry.arrow).\(entry.screen)"
            if !entry.hotkey.sync(enabled: wanted, shortcut: shortcut, storageKey: key) { failed = true }
        }
        if failed != registrationFailed { registrationFailed = failed }
    }

    private func press(_ arrow: Keys.Arrow, screen: Bool) {
        let action = chain.press(arrow, screen: screen, at: ProcessInfo.processInfo.systemUptime)
        let pointerFollows = UserDefaults.standard.bool(forKey: DefaultsKey.forkSwishMoveCursor)
        switch action {
        case .layout(let layout):
            _ = WindowLayoutService.shared.apply(layout)
        case .minimize:
            if let window = ForkSwishWindowOps.focusedWindow() { ForkSwishWindowOps.minimize(window) }
        case .display(let direction):
            if let window = ForkSwishWindowOps.focusedWindow() {
                ForkSwishWindowOps.moveToDisplay(window, toward: direction, pointerFollows: pointerFollows)
            }
        }
    }
}
