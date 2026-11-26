// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit

/// Everything the fork does at launch that upstream does not. Called once from
/// main.swift, after the command-line modes have had their chance to exit.
enum ForkBootstrap {
    static func run() {
        #if VORSSAINT_DEVELOPMENT
        ForkMissionControlProbe.runIfRequested()  // Developer builds: lot 6 feasibility probe, then quits
        ForkBluetoothBatteryProbe.runIfRequested()  // Developer builds: lot 8 probe, then quits
        #endif
        ForkUpstreamServices.keepDisabled()
        ForkCoexistence.shared.start()
        ForkCaptureMenu.shared.start()
        ForkPreviewCards.shared.start()
        ForkRecorderFocusService.shared.start()
        ForkRecorderKeyCapture.shared.start()
        ForkClipboardCopySoundPlayer.shared.start()
        ForkTitleBarGestures.shared.start()
        ForkSwishArrowHotkeys.shared.start()
        ForkSwishDoubleTap.shared.start()
        ForkCurrencyAnswer.install()
        ForkDragTopGuard.shared.start()
        ForkTrackpadSwitcher.shared.start()
        ForkMissionControlPlus.shared.start()
        ForkChromeFullscreenSwipe.shared.start()
        ForkBatteryAlerts.shared.start()
        ForkBatteryStatusItem.shared.start()
        ForkLidDisplaySleep.shared.start()
        ForkAmbientPlayer.shared.start()
        ForkCareAutomation.shared.start()
        ForkQuickActions.applyDefaultsOnce()
        ForkTodoist.shared.start()
        ForkVercel.shared.start()
        ForkWeather.shared.start()
        ForkTranslate.shared.start()
        ForkClaudeSessions.shared.start()
        ForkHome.shared.start()
        ForkBambu.shared.start()
    }
}

/// Keeps online sharing off.
///
/// Sharing a screenshot or a recording uploads it to upstream's server, which
/// a fork has no business using. The identity pass already points that host at
/// a name that cannot resolve; turning the two preferences off goes one step
/// further and hides the share buttons, which all read these keys.
enum ForkUpstreamServices {
    private static let sharingKeys = [
        DefaultsKey.screenshotSharingEnabled,
        DefaultsKey.recorderSharingEnabled,
    ]

    static func keepDisabled() {
        turnOff()
        // Upstream's Settings still show the two toggles. Switching one on
        // snaps it back instead of revealing buttons that could only fail. The
        // observer lives as long as the app, so its token is not kept.
        _ = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in
            turnOff()
        }
    }

    /// Writes only when a key is on, so the change notification this causes
    /// finds nothing left to do and the observer does not loop.
    private static func turnOff() {
        let defaults = UserDefaults.standard
        for key in sharingKeys where defaults.bool(forKey: key) {
            defaults.set(false, forKey: key)
        }
    }
}

/// Warns when upstream's app runs next to the fork.
///
/// Both register the same global shortcuts and install the same event taps, so
/// every shortcut and gesture would fire twice. Nothing stops the two from
/// being installed side by side; they just should not run together.
final class ForkCoexistence {
    static let shared = ForkCoexistence()

    /// Upstream's release and Developer builds. Files under Fork/ are copied
    /// verbatim by the identity pass, so these stay upstream's identifiers.
    private static let upstreamBundleIDs = ["com.vorssaint.utils", "com.vorssaint.utils.dev"]
    private static let upstreamName = "Vorssaint"

    private var isPresenting = false

    private init() {}

    func start() {
        // At launch, once the app can show a window…
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.warnIfUpstreamIsRunning()
        }
        // …and whenever upstream is opened later.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let launched = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let identifier = launched?.bundleIdentifier,
                  Self.upstreamBundleIDs.contains(identifier) else { return }
            self?.warnIfUpstreamIsRunning()
        }
    }

    private func runningUpstreamApps() -> [NSRunningApplication] {
        Self.upstreamBundleIDs.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
    }

    private func warnIfUpstreamIsRunning() {
        let upstreamApps = runningUpstreamApps()
        guard !upstreamApps.isEmpty, !isPresenting else { return }
        isPresenting = true
        defer { isPresenting = false }

        let text = ForkStrings.current
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text.coexistenceTitle(Self.upstreamName)
        alert.informativeText = text.coexistenceMessage(AppInfo.name, Self.upstreamName)
        alert.addButton(withTitle: text.quit(Self.upstreamName))
        alert.addButton(withTitle: text.quit(AppInfo.name))
        alert.addButton(withTitle: text.keepBoth)
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            upstreamApps.forEach { $0.terminate() }
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
    }
}
