// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The capture settings as the fork presents them: one short page, the lines
/// that matter day to day, a sentence under each one that needs it.
///
/// It sits at the top of upstream's capture page, placed by one line in
/// `ScreenCaptureSettings`. Upstream's own sections, all of them, stay
/// available below behind "All settings". Nothing here stores anything new:
/// every line edits a preference that already exists, upstream's or the
/// fork's, through upstream's own controls where it has one.
struct ForkCaptureSettingsPage: View {
    @Binding var showsAll: Bool
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var screenshots = ScreenshotService.shared
    @ObservedObject private var captures = ScreenCaptureService.shared
    @ObservedObject private var captureMenu = ForkCaptureMenu.shared
    @AppStorage(DefaultsKey.screenshotFullScreenShortcutEnabled) private var fullScreenEnabled = false
    @AppStorage(DefaultsKey.screenshotShortcutEnabled) private var areaEnabled = false
    @AppStorage(DefaultsKey.forkCaptureMenuShortcutEnabled) private var menuEnabled = true
    @AppStorage(DefaultsKey.forkScreenshotPreviewCard) private var previewCard = true
    @AppStorage(DefaultsKey.forkScreenshotCaptureSound) private var captureSound = true
    @AppStorage(DefaultsKey.screenshotDefaultAction) private var defaultAction = ""
    @AppStorage(DefaultsKey.screenshotSaveFolder) private var saveFolder = ""
    @AppStorage(DefaultsKey.forkScreenshotExcludeDesktopIcons) private var excludeDesktopIcons = true
    @AppStorage(DefaultsKey.screenshotIncludePointer) private var includePointer = false
    @AppStorage(DefaultsKey.screenshotHideVorssaintWindows) private var hideOwnWindows = true
    @AppStorage(DefaultsKey.screenshotDelay) private var delay = 0
    @AppStorage(DefaultsKey.screenshotFreeze) private var freeze = true
    @AppStorage(DefaultsKey.screenshotShowLastRegion) private var showLastRegion = true
    @AppStorage(DefaultsKey.forkScrollingControls) private var scrollingControls = true
    @AppStorage(DefaultsKey.forkScrollingHorizontal) private var scrollingHorizontal = false
    @AppStorage(DefaultsKey.forkEditorCrop) private var simplerCrop = true
    @AppStorage(DefaultsKey.forkRecorderDoNotDisturb) private var doNotDisturb = true
    @AppStorage(DefaultsKey.forkWindowCaptureStyle) private var windowStyle = ForkWindowCaptureStyle.Mode.shadow.rawValue
    @AppStorage(DefaultsKey.forkRecorderShowsKeys) private var showsKeys = false
    @AppStorage(DefaultsKey.forkRecorderAllKeys) private var allKeys = false
    @ObservedObject private var focus = ForkRecorderFocusService.shared

    var body: some View {
        let text = ForkStrings.current
        if !permissions.screenRecording {
            Section {
                PermissionRow(kind: .screenRecording)
            }
        }
        Section {
            shortcuts(text)
        } header: {
            Text(text.settingsShortcuts)
        }
        .onAppear { if doNotDisturb { focus.refresh() } }
        ForkCaptureMenuSettingsSection()
        Section {
            afterCapture(text)
        } header: {
            Text(text.settingsAfterCapture)
        }
        Section {
            inPicture(text)
        } header: {
            Text(text.settingsInPicture)
        }
        Section {
            Toggle(text.settingsFreeze, isOn: $freeze)
            caption(text.settingsFreezeCaption)
            Toggle(text.settingsLastRegion, isOn: $showLastRegion)
        } header: {
            Text(text.settingsDuringSelection)
        }
        Section {
            let scrolling = ForkScrollingStrings.current
            Toggle(scrolling.controlsToggle, isOn: $scrollingControls)
            caption(scrolling.controlsCaption)
            Toggle(scrolling.horizontalToggle, isOn: $scrollingHorizontal)
            caption(scrolling.horizontalCaption)
        } header: {
            Text(ForkScrollingStrings.current.section)
        }
        Section {
            recording(text)
        } header: {
            Text(text.settingsRecording)
        }
        Section {
            Button {
                withAnimation { showsAll.toggle() }
            } label: {
                Label(showsAll ? text.settingsHideAll : text.settingsShowAll,
                      systemImage: showsAll ? "chevron.up" : "chevron.down")
            }
            caption(text.settingsAllCaption)
        }
    }

    @ViewBuilder
    private func shortcuts(_ text: ForkStrings) -> some View {
        Toggle(text.settingsFullScreen, isOn: $fullScreenEnabled)
            .onChange(of: fullScreenEnabled) { _, _ in screenshots.syncWithPreferences() }
        ShortcutPreferenceRow(role: .screenshotFullScreen, isEnabled: fullScreenEnabled) {
            screenshots.syncWithPreferences()
        }
        if fullScreenEnabled, screenshots.fullScreenShortcutRegistrationFailed { unavailable }
        caption(text.settingsFullScreenCaption)

        Toggle(text.settingsArea, isOn: $areaEnabled)
            .onChange(of: areaEnabled) { _, _ in captures.syncWithPreferences() }
        ShortcutPreferenceRow(role: .screenshot, isEnabled: areaEnabled) {
            captures.syncWithPreferences()
        }
        if areaEnabled, captures.toolShortcutRegistrationFailures.contains(.screenshot) { unavailable }
        caption(text.settingsAreaCaption)

        Toggle(text.captureMenuToggle(ForkCaptureMenu.shortcutDisplayString), isOn: $menuEnabled)
        if menuEnabled, captureMenu.shortcutUnavailable { unavailable }
        caption(text.captureMenuCaption)
    }

    @ViewBuilder
    private func afterCapture(_ text: ForkStrings) -> some View {
        Toggle(text.previewCardToggle, isOn: $previewCard)
        caption(text.previewCardCaption)
        if previewCard { ForkPreviewShortcutRows() }
        Toggle(text.captureSoundToggle, isOn: $captureSound)
        Toggle(ForkCropStrings.current.settingsToggle, isOn: $simplerCrop)
        caption(ForkCropStrings.current.settingsCaption)
        ScreenshotDefaultActionPicker(strings: FeatureStrings.screenshot(l10n.language), selection: $defaultAction)
        caption(text.settingsDefaultActionCaption(AppInfo.name))
        LabeledContent(text.settingsFolder) {
            HStack(spacing: 8) {
                Text(folderName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(text.settingsChoose) { chooseFolder() }
            }
        }
        caption(text.settingsFolderCaption)
    }

    @ViewBuilder
    private func inPicture(_ text: ForkStrings) -> some View {
        Toggle(text.excludeDesktopIconsToggle, isOn: $excludeDesktopIcons)
        caption(text.excludeDesktopIconsCaption)
        Picker(text.windowStyleLabel, selection: $windowStyle) {
            Text(text.windowStylePlain).tag(ForkWindowCaptureStyle.Mode.plain.rawValue)
            Text(text.windowStyleShadow).tag(ForkWindowCaptureStyle.Mode.shadow.rawValue)
            Text(text.windowStyleBackdrop).tag(ForkWindowCaptureStyle.Mode.backdrop.rawValue)
        }
        caption(text.windowStyleCaption)
        Toggle(text.settingsPointer, isOn: $includePointer)
        Toggle(text.settingsHideOwnWindows(AppInfo.name), isOn: $hideOwnWindows)
        caption(text.settingsHideOwnWindowsCaption)
        Picker(text.settingsDelay, selection: $delay) {
            ForEach(ScreenshotSupport.allowedDelays, id: \.self) { seconds in
                Text(seconds == 0 ? text.settingsDelayNone : text.captureMenuSeconds(seconds)).tag(seconds)
            }
        }
        caption(text.settingsDelayCaption)
    }

    @ViewBuilder
    private func recording(_ text: ForkStrings) -> some View {
        Toggle(text.keysToggle, isOn: $showsKeys)
        if showsKeys {
            Picker(text.keysWhich, selection: $allKeys) {
                Text(text.keysShortcutsOnly).tag(false)
                Text(text.keysAll).tag(true)
            }
        }
        caption(text.keysCaption)
        Toggle(text.focusToggle, isOn: $doNotDisturb)
            .onChange(of: doNotDisturb) { _, on in if on { focus.refresh() } }
        if doNotDisturb {
            let ready = focus.found.on != nil && focus.found.off != nil
            LabeledContent(text.focusShortcutsLabel) {
                HStack(spacing: 8) {
                    Text(ready ? text.focusShortcutsReady : text.focusShortcutsToCreate)
                        .foregroundStyle(ready ? Color.secondary : Color.orange)
                    if !ready {
                        Button(text.focusCreate) { focus.createMissing() }
                    }
                    Button(text.focusCheck) { focus.refresh() }
                }
            }
            caption(text.focusCaption)
        }
    }

    private var unavailable: some View {
        Text(l10n.s.shortcutUnavailable)
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The folder as Finder names it. An empty preference is upstream's
    /// default, the Desktop.
    private var folderName: String {
        let manager = FileManager.default
        let path = saveFolder.isEmpty
            ? (manager.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory())
            : (saveFolder as NSString).expandingTildeInPath
        return manager.displayName(atPath: path)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if !saveFolder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (saveFolder as NSString).expandingTildeInPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url.path
        }
    }
}
