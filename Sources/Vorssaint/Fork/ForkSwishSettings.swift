// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// Swish's settings, first on upstream's window layout page, placed there by
/// one line: the gestures, their modifiers, the arrow keys, and a button that
/// copies Swish's own preferences over.
struct ForkSwishSettings: View {
    @AppStorage(DefaultsKey.forkTitleBarSwipe) private var swipe = true
    @AppStorage(DefaultsKey.forkTitleBarPinch) private var pinch = true
    @AppStorage(DefaultsKey.forkSwishMoveCursor) private var moveCursor = true
    @AppStorage(DefaultsKey.forkSwishGeneralModifier) private var general = ForkSwishModifiers.defaultGeneral
    @AppStorage(DefaultsKey.forkSwishScreenModifier) private var screen = ForkSwishModifiers.defaultScreen
    @AppStorage(DefaultsKey.forkSwishSecondaryModifier) private var secondary = ForkSwishModifiers.defaultSecondary
    @AppStorage(DefaultsKey.forkSwishTertiaryModifier) private var tertiary = ForkSwishModifiers.defaultTertiary
    @AppStorage(DefaultsKey.forkSwishSuperModifier) private var superKey = ForkSwishModifiers.defaultSuper
    @AppStorage(DefaultsKey.forkSwishArrowKeys) private var arrowKeys = true
    @AppStorage(DefaultsKey.forkSwishRequireSuper) private var requireSuper = false
    @AppStorage(DefaultsKey.forkSwishActiveListener) private var activeListener = true
    @AppStorage(DefaultsKey.forkSwishDoubleTap) private var doubleTap = true
    @AppStorage(DefaultsKey.forkSwishPreview) private var preview = true
    @AppStorage(DefaultsKey.forkSwishBubble) private var bubble = true
    @AppStorage(DefaultsKey.forkSwishLiveMove) private var liveMove = true
    @AppStorage(DefaultsKey.forkSwishDockGestures) private var dockGestures = true
    @AppStorage(DefaultsKey.forkSwishHaptics) private var haptics = true
    @AppStorage(DefaultsKey.forkSwishSensitivity) private var sensitivity = 1
    @AppStorage(DefaultsKey.forkSwishCancelTimeout) private var cancelTimeout = 0.8
    @AppStorage(DefaultsKey.forkMissionControlPlus) private var missionControlPlus = true
    @AppStorage(DefaultsKey.forkChromeFullscreenSwipe) private var chromeSwipe = true
    @ObservedObject private var arrowHotkeys = ForkSwishArrowHotkeys.shared
    @State private var swishRunning = false
    @State private var importResult: String?

    var body: some View {
        if AppFeature.windowLayout.isAvailable {
            let text = ForkStrings.current
            let swish = ForkSwishStrings.current
            Section(swish.section) {
                if swishRunning {
                    HStack {
                        Label(swish.swishRunning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(swish.quitSwish, action: quitSwish)
                    }
                }
                Toggle(text.titleBarSwipeToggle, isOn: $swipe)
                caption(text.titleBarSwipeCaption)
                Toggle(text.titleBarPinchToggle, isOn: $pinch)
                caption(text.titleBarPinchCaption + " " + swish.pinchTwiceCaption)
                Toggle(swish.bubbleToggle, isOn: $bubble)
                caption(swish.bubbleCaption)
                Toggle(swish.liveMoveToggle, isOn: $liveMove)
                caption(swish.liveMoveCaption)
                Toggle(swish.previewToggle, isOn: $preview)
                caption(swish.previewCaption)
                Toggle(swish.dockToggle, isOn: $dockGestures)
                caption(swish.dockCaption)
                Toggle(swish.doubleTapToggle, isOn: $doubleTap)
                caption(swish.doubleTapCaption)
                Toggle(swish.moveCursorToggle, isOn: $moveCursor)
                Toggle(swish.listenerToggle, isOn: $activeListener)
                caption(swish.listenerCaption)
                Toggle(swish.hapticToggle, isOn: $haptics)
                caption(swish.hapticCaption)
                LabeledContent(swish.sensitivity) {
                    Slider(value: Binding(get: { Double(sensitivity) }, set: { sensitivity = Int($0.rounded()) }),
                           in: 1...5, step: 1)
                        .frame(maxWidth: 220)
                }
                caption(swish.sensitivityCaption)
                LabeledContent(swish.cancelTimeout(cancelTimeout)) {
                    Slider(value: $cancelTimeout, in: 0.3...2, step: 0.1)
                        .frame(maxWidth: 220)
                }
                caption(swish.cancelCaption)
            }
            .onAppear(perform: refreshSwishRunning)
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
                refreshSwishRunning()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
                refreshSwishRunning()
            }

            Section(swish.modifiersSection) {
                ModifierRow(title: swish.superModifier, caption: swish.superCaption, mask: $superKey)
                Toggle(swish.requireSuper, isOn: $requireSuper)
                ModifierRow(title: swish.generalModifier, caption: swish.generalCaption, mask: $general)
                ModifierRow(title: swish.screenModifier, caption: swish.screenCaption, mask: $screen)
                ModifierRow(title: swish.secondaryModifier, caption: swish.secondaryCaption, mask: $secondary)
                ModifierRow(title: swish.tertiaryModifier, caption: swish.tertiaryCaption, mask: $tertiary)
            }

            Section(swish.keyboardSection) {
                Toggle(swish.arrowKeysToggle(ForkSwishModifiers.symbols(superKey)), isOn: $arrowKeys)
                caption(swish.arrowKeysCaption(ForkSwishModifiers.symbols(screen)))
                if arrowKeys, arrowHotkeys.registrationFailed {
                    Label(swish.arrowKeysFailed, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section(swish.importSection) {
                HStack {
                    Button(swish.importButton, action: takeSwishSettings)
                    if let importResult {
                        Text(importResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                caption(swish.importCaption)
            }

            let missionControl = ForkMissionControlStrings.current
            Section(missionControl.section) {
                Toggle(missionControl.toggle, isOn: $missionControlPlus)
                caption(missionControl.caption)
            }

            let chrome = ForkChromeStrings.current
            Section(chrome.section) {
                Toggle(chrome.toggle, isOn: $chromeSwipe)
                caption(chrome.caption)
            }
        }
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var swishApps: [NSRunningApplication] {
        ForkSwishImport.domains.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    }

    private func refreshSwishRunning() {
        swishRunning = !swishApps.isEmpty
    }

    private func quitSwish() {
        swishApps.forEach { $0.terminate() }
    }

    /// Copies what Swish stores over Hublot's settings, from the first of its
    /// preference domains this Mac has.
    private func takeSwishSettings() {
        let defaults = UserDefaults.standard
        let swish = ForkSwishStrings.current
        guard let prefs = ForkSwishImport.domains.lazy.compactMap({ defaults.persistentDomain(forName: $0) }).first else {
            importResult = swish.importNone
            return
        }
        let values = ForkSwishImport.values(fromSwish: prefs)
        for (key, value) in values { defaults.set(value, forKey: key) }
        importResult = swish.importDone(values.count)
    }
}

/// One modifier: its name, the five keys it can be made of, and what it does.
private struct ModifierRow: View {
    let title: String
    let caption: String
    @Binding var mask: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(ForkSwishModifiers.keys, id: \.self) { key in
                        Toggle(ForkSwishModifiers.symbols(key), isOn: Binding(
                            get: { mask & key != 0 },
                            set: { mask = $0 ? mask | key : mask & ~key }))
                            .toggleStyle(.button)
                            .controlSize(.small)
                    }
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
