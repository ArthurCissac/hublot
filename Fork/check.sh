#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Arthur Cissac

# Fork invariants. Run it after every rebase on upstream and before any
# install: it fails loudly when an upstream change silently reopens something
# this fork closed on purpose. It only reads files; it changes nothing.
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
ok()   { print "  ✓ $1"; }
fail() { print -u2 "  ✗ $1"; failures=$((failures + 1)); }

# Counts lines matching a fixed string. `grep -c` exits 1 on zero matches,
# which must not abort the script under `set -e`.
count() { grep -c -F -- "$1" "$2" || true; }

# --- 1. The in-app updater never runs -----------------------------------------
# Upstream gates its updater on `AppInfo.isDeveloperBuild` (bundle id ends in
# ".dev"). The fork replaces each gate with `AppInfo.neverSelfUpdates`, because
# an ungated updater would download the official app and delete this one.
#   - a leftover `isDeveloperBuild` means upstream added an entry point: convert it;
#   - fewer gates than expected means upstream restructured the updater: read the
#     new code, make sure every path that checks, downloads or installs is gated,
#     then update EXPECTED_UPDATER_GATES below.
EXPECTED_UPDATER_GATES=5
UPDATER="Sources/Vorssaint/Services/Update/UpdateService.swift"
print "Updater ($UPDATER)"
fork_gates=$(count 'AppInfo.neverSelfUpdates' "$UPDATER")
upstream_gates=$(count 'AppInfo.isDeveloperBuild' "$UPDATER")
if [[ "$upstream_gates" == 0 ]]; then
    ok "no upstream gate left"
else
    fail "$upstream_gates upstream gate(s) left: replace AppInfo.isDeveloperBuild with AppInfo.neverSelfUpdates"
fi
if [[ "$fork_gates" == "$EXPECTED_UPDATER_GATES" ]]; then
    ok "$fork_gates fork gates in place"
else
    fail "$fork_gates fork gate(s), expected $EXPECTED_UPDATER_GATES: review the updater entry points"
fi
if [[ "$(count 'static var neverSelfUpdates: Bool { isDeveloperBuild || !isForkRelease || updateRepository.isEmpty }' Sources/Vorssaint/Fork/AppInfo+Fork.swift)" == 1 ]]; then
    ok "neverSelfUpdates holds for the Developer build, a build not made for release, and without the fork's repository"
else
    fail "AppInfo.neverSelfUpdates no longer keeps the Developer build and a build without the fork's repository from updating"
fi

# --- 2. The identity pass is wired in and still sound -------------------------
# build.sh carries a handful of one-line hooks. A conflict resolved the wrong
# way during a rebase can drop one without breaking the build: the app would
# then compile, but under upstream's name or identifiers.
print
print "Identity pass (build.sh hooks, Fork/brand.py)"
for hook in \
    'source Fork/build-hooks.zsh' \
    'fork_brand_sources' \
    '"$FORK_APP_SRC/Services/FanControl/FanControlXPC.mirror.swift"' \
    'fork_brand_bundle_resources "$STAGE"' \
    'fork_test_sources' \
    '[[ "$APP_BUNDLE_ID" != "com.vorssaint.utils" ]]' \
    'ditto "${BRAND_DIR:-Resources/Brand}/AppIcon.icon"'; do
    found=$(count "$hook" build.sh)
    if [[ "$found" == 1 ]]; then
        ok "build.sh: $hook"
    else
        fail "build.sh: expected exactly one '$hook', found $found"
    fi
done
# The app icon, the menu bar glyph and the in-app mark all come from the
# fork's own artwork; upstream's logo is a trademark.
if [[ "$(count 'environment["BRAND_DIR"]' Tools/MakeIcon.swift)" == 1 ]]; then
    ok "Tools/MakeIcon.swift reads BRAND_DIR"
else
    fail "Tools/MakeIcon.swift no longer reads BRAND_DIR: the build would ship upstream's logo"
fi
for artwork in Fork/Brand/logo.png Fork/Brand/AppIcon-Default.png Fork/Brand/AppIcon.icon/icon.json; do
    [[ -s "$artwork" ]] || fail "missing artwork: $artwork"
done
if python3 Fork/brand.py selftest >/dev/null; then
    ok "the rules pass their own selftest"
else
    fail "python3 Fork/brand.py selftest failed"
fi
# A match outside string literals and comments would rename an identifier.
if audit=$(python3 Fork/brand.py audit 2>&1); then
    ok "no rule matches code: $(print -r -- "$audit" | head -1)"
else
    print -u2 -r -- "$audit"
    fail "python3 Fork/brand.py audit found a rule matching code"
fi

# --- The fork's one-line calls in upstream files are still there ---------------
# Each feature the fork adds lives in its own files and is reached from one
# line in an upstream file. A rebase conflict resolved the wrong way can drop
# such a line without breaking the build; the feature would then be dead code.
#   - ForkBootstrap: without it online sharing comes back on and nothing warns
#     when upstream's app runs alongside;
#   - ForkAttributionView: the About pane no longer says this build is a fork;
#   - AppInfo.forkRepositoryURL, AppInfo.showsUpstreamPromotion (three lines): « View on GitHub »
#     leads upstream again, or upstream's donation page and post-update showcase come back;
#   - ForkCaptureExclusions: desktop icons are back in every screenshot;
#   - ForkCaptureSettingsPage: the short capture settings page is gone, and with
#     it the only place the fork's own settings are shown;
#   - ForkCaptureSound: captures are silent again;
#   - ForkPreviewCards.present: the card preview never appears;
#   - ForkPreviewCards.shared.windowIDs: a card can show up in the next capture;
#   - ForkPreviewCards.editorDidClose: closing the editor loses the picture again;
#   - ForkPreviewCards.isEnabled() in the editor: it asks to discard edits that are kept;
#   - ForkPinControls.install: a pinned capture loses its bar of buttons;
#   - ForkRecorderOptions (three lines): recordings are stereo again, or show
#     click rings whatever the recording bar says;
#   - ForkRecorderDevices.captureMicrophone: recordings listen to the system's
#     default input again, whatever the recording bar says;
#   - forkCenter, forkTurn, ForkRecorderImagePlacement, ForkRecorderImageTurn,
#     ForkRecorderImageHandles (seven lines):
#     a picture laid over a recording is back to upstream's nine places and 60 %
#     width, on the stage, in the export, or both;
#   - forkMusic, ForkRecorderMusic, ForkRecorderMusicButton, ForkRecorderMusicLane
#     (twelve lines): music added in the video editor is not saved, not heard in
#     the preview, missing from the export, or cannot be added at all;
#   - ForkCaptureSelectionGuide: upstream's hint bar is back over the capture menu;
#   - ForkRecorderKeyCapture.addCaptions: keys pressed while recording never reach the video;
#   - ForkWindowCaptureStyle.markWindowCapture, ForkWindowCaptureStyler.styledIfWindow:
#     window captures lose their shadow or background;
#   - ForkScrollingDirection (three lines): horizontal scrolling captures come out
#     turned a quarter, or vertical;
#   - ForkScrollingControls (six lines): scrolling captures show upstream's controls
#     again, the pointer-steered auto-scroll is gone, or its strip stays on screen
#     or shows up in the picture;
#   - ForkCropTool, ForkCropOverlay, ForkCropBar (ten lines): the editor's crop is
#     back to upstream's small grips, or draws nothing, or leaving it loses the crop;
#   - ForkScrollingPreviewFeed (two lines): the live preview beside a scrolling
#     capture stays empty, or misses the strips after the first picture;
#   - ForkClipboardShelf (two lines), ForkClipboardSettingsSection: the clipboard
#     history opens upstream's window again, and its setting is gone;
#   - ForkRecorderImageVisibility, ForkRecorderImageDrag (two lines): a picture moved on
#     the editor's stage shows twice while held, or not at all once let go;
#   - ForkRecorderAudioBoost, forkMicrophoneBoost (four lines): the microphone can no
#     longer be made louder than 100 % in the editor;
#   - ForkTitleBarGestures (apply's window: parameter, forkTarget), ForkSwishSettings:
#     title bar gestures act on the frontmost window, or not at all;
#   - ForkDragTopGuardRow: the setting that keeps Mission Control away from a drag is gone;
#   - ForkBatteryLogic.pinnedMetric, ForkBatterySettingsCard: the pinned device no longer
#     shows in the menu bar, or lot 8's settings are gone;
#   - ForkMenuBarIconTrim: the Hublot icon has its 6 pt of empty sides again;
#   - ForkBatteryLogic.bluetoothRefreshInterval: a pinned iPhone or iPad is read every
#     five minutes again instead of every two;
#   - ForkCleanerToolsBar: the disk map and the antivirus can no longer be opened;
#   - ForkTrackpadSwitcher (the AppSwitcher extension, the settings row): three fingers
#     on the trackpad no longer open the window switcher;
#   - ForkLyricsNearbyDuration (two lines), ForkLyricsSettingsRow: lyrics a few
#     seconds off the song's length are refused again, or their setting is gone;
#   - forkReadSpotifyQueue (call and extension), ForkSpotifyConnectButton,
#     ForkSpotifyQueueSettingsRows: the island's queue page no longer reads
#     Spotify's queue, cannot sign in, or its settings are gone;
#   - ForkRoundSteps (volume, two brightness lines), ForkRoundStepSettingsRows: the volume
#     and brightness keys go back to the system's sixteenth steps, or their settings are gone;
#   - ForkTranslateSettingsSection: the translation's settings are gone from the island's page;
#   - the Translation page and button (NotchModule.translate, NotchControlItem.translate, their
#     symbol, key, title, tile and action): the island no longer shows translations;
#   - the Home page and button (NotchModule.home, NotchControlItem.home, their symbol, key, title,
#     tile, action, preview, colour, height and ForkHomeSettingsSection): Home Assistant's favourites
#     vanish from the island, its page scrolls, or its settings are gone;
#   - the Printer page and button (NotchModule.printer, NotchControlItem.printer, the same set, and
#     ForkBambuSettingsSection): the Bambu Lab printer vanishes from the island or cannot be set up;
#   - the AI page's Claude cards (NotchAgentCard.forkWaiting/forkTime/forkResume, their symbol, title,
#     period, view and order), the waiting notice's click and switch, the requests handed to the time per
#     project: the cards vanish, a waiting notice opens the AI page, or the time stays empty;
#   - the Hublot style (ForkAgentGrid, its height, the island growing for it) and Explorer on one page
#     (every row, the picker, the pencil, hidden pages left out): the AI page scrolls again, or Explorer pages;
#   - ForkTests: the fork's tests compile but never run.
print
print "Fork hooks in upstream sources"
for hook_site in \
    'ForkBootstrap.run()|Sources/Vorssaint/main.swift' \
    'ForkAttributionView()|Sources/Vorssaint/UI/Settings/SettingsView.swift' \
    'Link(l10n.s.viewOnGitHub, destination: AppInfo.forkRepositoryURL)  // Fork|Sources/Vorssaint/UI/Settings/SettingsView.swift' \
    'private let repository = AppInfo.updateRepository  // Fork|Sources/Vorssaint/Services/Update/UpdateService.swift' \
    '].filter { AppInfo.showsUpstreamPromotion || $0.page != .support }),  // Fork|Sources/Vorssaint/UI/Settings/SettingsDirectory.swift' \
    'guard AppInfo.showsUpstreamPromotion, AppInfo.version == UpdateShowcaseInfo.releaseVersion else {  // Fork|Sources/Vorssaint/App/AppDelegate.swift' \
    'ForkCaptureExclusions.windowIDs(in: content, isReading: keepsIslandOut)|Sources/Vorssaint/Services/QuickTools/ScreenshotCaptureEngine.swift' \
    'ForkCaptureSettingsPage(showsAll: $forkShowsAll)|Sources/Vorssaint/UI/Settings/ScreenCaptureSettings.swift' \
    'ForkCaptureSound.play()|Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift' \
    'ForkPreviewCards.shared.windowIDs|Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift' \
    'ForkPreviewCards.editorDidClose(self)|Sources/Vorssaint/Services/QuickTools/ScreenshotEditorController.swift' \
    'if ForkPreviewCards.isEnabled() { return true }|Sources/Vorssaint/Services/QuickTools/ScreenshotEditorController.swift' \
    'ForkPreviewCards.present(capture, strings: strings, disabled: model.disabledActions, perform: action)|Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift' \
    'ForkPinControls.install(in: view, image: image, scale: scale,|Sources/Vorssaint/Services/QuickTools/ScreenshotPinController.swift' \
    'ForkRecorderOptions.showsClicks(),  // Fork|Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift' \
    'ForkRecorderOptions.exportReaderSettings()) { _, fork in fork })|Sources/Vorssaint/Services/Recorder/RecorderExporter.swift' \
    'ForkRecorderOptions.exportChannelCount(),  // Fork: and written|Sources/Vorssaint/Services/Recorder/RecorderExporter.swift' \
    'ForkRecorderDevices.captureMicrophone() ?? AVCaptureDevice.default(for: .audio)|Sources/Vorssaint/Services/Recorder/RecorderCaptureEngine.swift' \
    'var forkCenter: CGPoint? = nil  // Fork|Sources/Vorssaint/Services/Recorder/RecorderImageOverlay.swift' \
    'var forkTurn: ForkRecorderImageTurn? = nil  // Fork|Sources/Vorssaint/Services/Recorder/RecorderImageOverlay.swift' \
    'ForkRecorderImageTurn.transform(overlay.forkTurn, size: size, origin: origin)|Sources/Vorssaint/Services/Recorder/RecorderComposer.swift' \
    '0.04...ForkRecorderImagePlacement.largestSize|Sources/Vorssaint/Services/Recorder/RecorderImageOverlay.swift' \
    'ForkRecorderImagePlacement.origin(of: overlay, drawn: size, in: plan.canvasSize)|Sources/Vorssaint/Services/Recorder/RecorderComposer.swift' \
    'ForkRecorderImageHandles(model: model, stage: proxy.size)|Sources/Vorssaint/UI/Recorder/RecorderEditorView.swift' \
    '$0.anchor = anchor; $0.forkCenter = nil }|Sources/Vorssaint/UI/Recorder/RecorderInspector.swift' \
    'var forkMusic: ForkRecorderMusic.Track? = nil  // Fork|Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift' \
    'decodeIfPresent(ForkRecorderMusic.Track.self, forKey: .forkMusic)|Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift' \
    'forkMusic?.path != other.forkMusic?.path|Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift' \
    'forkMusic?.gain != other.forkMusic?.gain|Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift' \
    'ForkRecorderMusic.add(to: result.asset, document: self.document, duration: result.duration)|Sources/Vorssaint/Services/Recorder/RecorderEditorController.swift' \
    'ForkRecorderMusic.mixing(item.audioMix, in: result.asset, document: self.document)|Sources/Vorssaint/Services/Recorder/RecorderEditorController.swift' \
    'ForkRecorderMusic.mixing(player.currentItem?.audioMix, in: player.currentItem?.asset, document: document)|Sources/Vorssaint/Services/Recorder/RecorderEditorController.swift' \
    'ForkRecorderMusic.isPresent(in: document)|Sources/Vorssaint/Services/Recorder/RecorderExporter.swift' \
    'ForkRecorderMusic.add(to: timeline, document: document, duration: result.duration)|Sources/Vorssaint/Services/Recorder/RecorderExporter.swift' \
    'ForkRecorderMusic.mixing(output.audioMix, in: timeline, document: document)|Sources/Vorssaint/Services/Recorder/RecorderExporter.swift' \
    'ForkRecorderMusicButton(model: model)|Sources/Vorssaint/UI/Recorder/RecorderEditorView.swift' \
    'ForkRecorderMusicLane(model: model)|Sources/Vorssaint/UI/Recorder/RecorderEditorView.swift' \
    '!ForkCaptureSelectionGuide.isHidden, let panel else {|Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift' \
    'ForkRecorderKeyCapture.addCaptions(to: self)|Sources/Vorssaint/Services/Recorder/RecorderEditorController.swift' \
    'ForkWindowCaptureStyle.markWindowCapture()  // Fork|Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift' \
    'route(ForkWindowCaptureStyler.styledIfWindow(capture))|Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift' \
    'ForkScrollingDirection.first(await source.image())|Sources/Vorssaint/Services/QuickTools/ScreenshotScrollingCapture.swift' \
    'ForkScrollingDirection.oriented(await source.image())|Sources/Vorssaint/Services/QuickTools/ScreenshotScrollingCapture.swift' \
    'ForkScrollingDirection.restored(stitch(completedSlices))|Sources/Vorssaint/Services/QuickTools/ScreenshotScrollingCapture.swift' \
    'ids.formUnion(ForkScrollingControls.shared.windowIDs)|Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift' \
    'ForkScrollingControls.shared.dismiss()  // Fork: on teardown|Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift' \
    '&& !ForkScrollingControls.isEnabled  // Fork|Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift' \
    'ForkScrollingControls.shared.show(region: region, onFinish: { finishSignal.request() },|Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift' \
    'ForkScrollingControls.shared.update(height: height)  // Fork|Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift' \
    'ForkScrollingControls.shared.dismiss()  // Fork: when the capture ends|Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift' \
    'ForkCropTool.commitOnLeave(self, draft: cropDraft, next: tool)|Sources/Vorssaint/Services/QuickTools/ScreenshotEditorController.swift' \
    'ForkCropTool.handle(at: point, rect: draft, zoom: currentDisplayZoom)|Sources/Vorssaint/Services/QuickTools/ScreenshotEditorController.swift' \
    'ForkCropTool.resized(origin, dragging: handle, to: point, imageSize: imageSize)|Sources/Vorssaint/Services/QuickTools/ScreenshotEditorController.swift' \
    'ForkCropTool.drawn(from: dragStart, to: point, imageSize: imageSize)|Sources/Vorssaint/Services/QuickTools/ScreenshotEditorController.swift' \
    'ForkCropTool.endDrag(at: point, isTap: isTap, draft: cropDraft, imageSize: imageSize)|Sources/Vorssaint/Services/QuickTools/ScreenshotEditorController.swift' \
    'model.cropDraft = nil  // Fork: Escape|Sources/Vorssaint/Services/QuickTools/ScreenshotEditorController.swift' \
    'ForkCropOverlay(model: model, zoom: zoom, canvasSize: canvasSize)|Sources/Vorssaint/UI/Screenshot/ScreenshotEditorView.swift' \
    'if ForkCropTool.setCursor(tool: model.tool, draft: model.cropDraft, imageSize: model.imageSize,|Sources/Vorssaint/UI/Screenshot/ScreenshotEditorView.swift' \
    'guard !ForkCropTool.isEnabled else { return }|Sources/Vorssaint/UI/Screenshot/ScreenshotEditorView.swift' \
    'if ForkCropTool.isEnabled { ForkCropBar(model: model, strings: strings) } else { cropBar }|Sources/Vorssaint/UI/Screenshot/ScreenshotEditorView.swift' \
    'ForkScrollingPreviewFeed.send(slices)  // Fork: live preview, first picture|Sources/Vorssaint/Services/QuickTools/ScreenshotScrollingCapture.swift' \
    'ForkScrollingPreviewFeed.send(slices)  // Fork: live preview, each strip|Sources/Vorssaint/Services/QuickTools/ScreenshotScrollingCapture.swift' \
    'if ForkClipboardShelf.shared.toggle() { return }|Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift' \
    'if ForkClipboardShelf.shared.show() { return }|Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift' \
    'ForkClipboardSettingsSection()|Sources/Vorssaint/UI/Settings/ClipboardSettings.swift' \
    'guard !ForkRecorderImageVisibility.isHidden(overlay.id) else { continue }|Sources/Vorssaint/Services/Recorder/RecorderComposer.swift' \
    'ForkRecorderImageDrag.previewRebuilt(self.player)|Sources/Vorssaint/Services/Recorder/RecorderEditorController.swift' \
    'ForkRecorderAudioBoost.apply(to: parameters, source: source, document: document)|Sources/Vorssaint/Services/Recorder/RecorderComposition.swift' \
    'var forkMicrophoneBoost: Double? = nil  // Fork|Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift' \
    'forKey: .forkMicrophoneBoost)  // Fork|Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift' \
    'forkMicrophoneBoost != other.forkMicrophoneBoost|Sources/Vorssaint/Services/Recorder/RecorderEditDocument.swift' \
    'ForkRecorderMicBoostRow(model: model)|Sources/Vorssaint/UI/Recorder/RecorderEditorView.swift' \
    'func apply(_ action: WindowLayoutAction, window forkWindow: AXUIElement? = nil)|Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift' \
    'forkWindow.map({ forkTarget(for: $0, action: action) }) ?? focusedTarget(for: action)|Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift' \
    'fileprivate func forkTarget(for window: AXUIElement, action: WindowLayoutAction)|Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift' \
    'ForkSwishSettings()|Sources/Vorssaint/UI/Settings/WindowLayoutSettings.swift' \
    'ForkDragTopGuardRow()|Sources/Vorssaint/UI/Settings/ShelfSettings.swift' \
    'if let pinned = ForkBatteryLogic.pinnedMetric(devices: devices,|Sources/Vorssaint/Services/Metrics/PeripheralBatterySupport.swift' \
    'ForkBatterySettingsCard()  // Fork|Sources/Vorssaint/UI/Settings/MonitorSettings.swift' \
    'button.image = ForkMenuBarIconTrim.trimmed(button.image)  // Fork|Sources/Vorssaint/App/StatusItemController.swift' \
    'private var bluetoothCacheInterval: TimeInterval { ForkBatteryLogic.bluetoothRefreshInterval }|Sources/Vorssaint/Services/Metrics/PeripheralBatterySampler.swift' \
    'ForkCleanerToolsBar()  // Fork|Sources/Vorssaint/UI/Cleaner/CleanerView.swift' \
    'func forkBeginGestureSession(scope: SwitcherSessionScope, reversed: Bool)|Sources/Vorssaint/Services/Switcher/AppSwitcher.swift' \
    'ForkSwitcherGestureRow(switcherEnabled: switcherEnabled)|Sources/Vorssaint/UI/Settings/SwitcherSettings.swift' \
    'ForkLyricsNearbyDuration.candidates(result.data, strictFound: !found.isEmpty, for: track, verifiedArtistAliases: verifiedArtistAliases)  // Fork|Sources/Vorssaint/Services/Notch/NotchLyricsService.swift' \
    'let accumulated = candidates + found + nearby  // Fork: nearby lengths rank last|Sources/Vorssaint/Services/Notch/NotchLyricsService.swift' \
    'if lyricsOnline { ForkLyricsSettingsRow() }|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'forkReadSpotifyQueue(after: reply, request: request)  // Fork|Sources/Vorssaint/Services/Notch/NotchMusicService.swift' \
    'fileprivate func forkReadSpotifyQueue(after reply: [String: Any], request: UUID)|Sources/Vorssaint/Services/Notch/NotchMusicService.swift' \
    'ForkSpotifyConnectButton(playback: playback)  // Fork|Sources/Vorssaint/UI/Notch/NotchQueueView.swift' \
    'if queueEnabled, AppFeature.notchQueue.isAvailable { ForkSpotifyQueueSettingsRows() }|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'ForkLidDisplaySleepRow().padding(.leading, settingsRowTextInset)  // Fork|Sources/Vorssaint/UI/Settings/EnergySettings.swift' \
    'ForkLidDisplaySleepMenuRow(clamshellPreferred: awake.clamshellPreferred)  // Fork|Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift' \
    'if ForkLidDisplaySleep.shared.holdsDisplaysAsleep { return }  // Fork|Sources/Vorssaint/Services/KeepAwakeManager.swift' \
    'if !editing, expanded != .memory { ForkHeavyAppsBlock() }  // Fork|Sources/Vorssaint/UI/MenuPanel/SystemSection.swift' \
    '.modifier(ForkProcessQuitOnHover(row: row))  // Fork|Sources/Vorssaint/UI/MenuPanel/ProcessUsageRow.swift' \
    'ForkDiskPanelTools()  // Fork|Sources/Vorssaint/UI/MenuPanel/DiskSection.swift' \
    'if !ForkPanelLook.hidesLogo() { header }  // Fork|Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift' \
    'ForkPanelTabs(sections: visibleSections, active: activeSection|Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift' \
    'return 180 - ForkPanelLook.chromeSaving() + bannerHeight  // Fork|Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift' \
    'ForkKeepAwakeTop {  // Fork|Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift' \
    '}  // Fork: end of ForkKeepAwakeTop|Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift' \
    'ForkSectionTitle { sectionTitle(title) }  // Fork|Sources/Vorssaint/UI/MenuPanel/PanelLayout.swift' \
    'ForkQuickActionsGrid(editing: editing) { QuickTogglesList(|Sources/Vorssaint/UI/MenuPanel/QuickTogglesSection.swift' \
    '} }  // Fork: end of ForkQuickActionsGrid|Sources/Vorssaint/UI/MenuPanel/QuickTogglesSection.swift' \
    'ForkPanelLook.showsDiskChooser(diskCount: disks.count, editing: editing)|Sources/Vorssaint/UI/MenuPanel/DiskSection.swift' \
    'ForkPanelLook.diskBlocks(orderedBlocks.filter(isVisible)|Sources/Vorssaint/UI/MenuPanel/DiskSection.swift' \
    'ForkPanelLoadingRows(leading: 38)  // Fork|Sources/Vorssaint/UI/MenuPanel/SystemSection.swift' \
    'ForkPanelValueText(text: value.map { MetricFormat.temperature|Sources/Vorssaint/UI/MenuPanel/SystemSection.swift' \
    'ForkPanelValueText(text: fraction.map|Sources/Vorssaint/UI/MenuPanel/SystemSection.swift' \
    'ForkPanelLoadingRows()  // Fork|Sources/Vorssaint/UI/MenuPanel/NetworkSection.swift' \
    'ForkPanelValueText(text: value.map { MetricFormat.networkRate|Sources/Vorssaint/UI/MenuPanel/NetworkSection.swift' \
    'if !ForkPanelLook.systemSoundsInOptions() { systemSoundOutputPicker }  // Fork|Sources/Vorssaint/UI/MenuPanel/MixerSection.swift' \
    'if ForkPanelLook.systemSoundsInOptions() { systemSoundOutputPicker.padding(.leading, 19) }  // Fork|Sources/Vorssaint/UI/MenuPanel/MixerSection.swift' \
    '.lineLimit(ForkPanelLook.deviceLines())  // Fork|Sources/Vorssaint/UI/MenuPanel/MixerSection.swift' \
    'Text(ForkPanelLook.fanStopped(rpm: fan.actualRPM)|Sources/Vorssaint/UI/MenuPanel/FanControlSection.swift' \
    'Text(ForkPanelLook.fanStopped(rpm: fallbackFanSpeeds[index])|Sources/Vorssaint/UI/MenuPanel/FanControlSection.swift' \
    'ForkDiskHealthFold(disk: disk, editing: editing) { smartBlock(|Sources/Vorssaint/UI/MenuPanel/DiskSection.swift' \
    'ForkSimplePanelsRow()  // Fork|Sources/Vorssaint/UI/Settings/GeneralToolSettings.swift' \
    'case ambient  // Fork: background sound (ForkAmbientLogic)|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient: return ForkAmbientLogic.islandSymbol  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient: return .none  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient: return ForkAmbientLogic.islandControlAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient: ForkAmbientIslandTile(service: service)  // Fork|Sources/Vorssaint/UI/Notch/NotchControlsView.swift' \
    'case .ambient: return ForkAmbientStrings.current.title  // Fork|Sources/Vorssaint/UI/Notch/NotchControlsView.swift' \
    'case .ambient: ForkAmbientPlayer.shared.toggle()  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    '== [.panel, .ambient, .tasks, .translate, .home, .printer],  // Fork|Tests/NotchTests.swift' \
    '(spacious.sectionRows(count: allModules.count) + 2) >= allModules.count,  // Fork|Tests/NotchTests.swift' \
    'wave (ForkAmbientStrip)|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient: return ForkAmbientLogic.title(french: language == .fr)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient: return .ambient  // Fork: its own page|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'self == .ambient ? ForkAmbientLogic.islandSymbol : self == .keepAwake|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    '+ (ForkAmbientLogic.islandActivityShown() ? [.ambient] : [])  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case .ambient: return geometry.compactTimerGeometry(showsDownloads: false, wing: ForkAmbientLogic.islandStripWing(geometry))  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case .ambient: return layout.keepAwakeSurface(reading: ForkAmbientLogic.islandReading(language), geometry: geometry)  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case .ambient: ForkAmbientCapsuleStrip(service: service, size: size)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .ambient: ForkAmbientStrip(service: service, displayGeometry: geometry)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .ambient: ForkAmbientCapsuleStrip(service: service, size: size, displayGeometry: geometry)  // Fork|Sources/Vorssaint/UI/Notch/NotchMirrorView.swift' \
    'case .ambient: ForkAmbientStrip(service: service, displayGeometry: mirror.strip)  // Fork|Sources/Vorssaint/UI/Notch/NotchMirrorView.swift' \
    'case .timer, .keepAwake, .watch, .ambient, .tasks, .deploys:  // Fork|Sources/Vorssaint/UI/Notch/NotchCapsuleViews.swift' \
    'case .timer, .keepAwake, .watch, .ambient, .tasks, .deploys:  // Fork: no mark|Sources/Vorssaint/UI/Notch/NotchTimerStrip.swift' \
    'case .timer, .keepAwake, .watch, .ambient, .tasks, .deploys:  // Fork: its own title|Sources/Vorssaint/UI/Notch/NotchTimerStrip.swift' \
    'case .downloads, .timer, .keepAwake, .watch, .ambient, .tasks, .deploys:  // Fork|Sources/Vorssaint/UI/Notch/NotchTimerStrip.swift' \
    "case tasks  // Fork: Todoist's next task (ForkTodoistStrip)|Sources/Vorssaint/Services/Notch/NotchSupport.swift" \
    'case .tasks: return ForkTodoistLogic.title(french: language == .fr)  // Fork: the next task|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    "case .tasks: return .tasks  // Fork: Todoist's page|Sources/Vorssaint/Services/Notch/NotchSupport.swift" \
    '+ (ForkTodoistLogic.islandActivityShown() ? [.tasks] : [])  // Fork: the next task|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case .tasks: return geometry.compactCalendarGeometry(wing: ForkTodoistLogic.islandStripWing(geometry))  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case .tasks: return layout.keepAwakeSurface(reading: ForkTodoistLogic.islandReading(), geometry: geometry)  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'if ForkTodoistLogic.isReminder(symbol: selectedNotice.symbol) { open(.tasks); if expanded { dismissNotice() }; return }  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case .tasks: ForkTodoistCapsuleStrip(service: service, size: size)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .tasks: ForkTodoistStrip(service: service, displayGeometry: geometry)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .tasks: ForkTodoistCapsuleStrip(service: service, size: size, displayGeometry: geometry)  // Fork|Sources/Vorssaint/UI/Notch/NotchMirrorView.swift' \
    'case .tasks: ForkTodoistStrip(service: service, displayGeometry: mirror.strip)  // Fork|Sources/Vorssaint/UI/Notch/NotchMirrorView.swift' \
    'ForkPortQRMenuItem(entry: entry)  // Fork: QR code to open on a phone|Sources/Vorssaint/UI/PortManager/PortManagerView.swift' \
    'ForkPortQRButton(entry: entry)  // Fork: QR code to open on a phone|Sources/Vorssaint/UI/PortManager/PortManagerView.swift' \
    'ForkLocalQRToggle().padding(.horizontal, 14).padding(.bottom, 8)  // Fork: QR code button toggle|Sources/Vorssaint/UI/PortManager/PortManagerView.swift' \
    'ForkPortQRButton(entry: entry)  // Fork: QR code to open on a phone|Sources/Vorssaint/UI/MenuPanel/PanelPortManagerView.swift' \
    'if let fork = ForkCurrencyLogic.commandBarAnswer(query, bar) { return fork }  // Fork: currencies at the ECB rates|Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift' \
    'ForkCurrencySettingsRows()  // Fork: currencies beside the calculator|Sources/Vorssaint/UI/Settings/CommandBarSettings.swift' \
    'ForkNotifications.handle(response)  // Fork: a scan|Sources/Vorssaint/App/AppDelegate.swift' \
    'case tasks  // Fork: Todoist (ForkTodoistLogic)|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .tasks: return ForkTodoistLogic.islandSymbol  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .tasks: return .none  // Fork: Todoist|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .tasks: return ForkTodoistLogic.islandControlAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .tasks: ForkTodoistIslandTile(service: service)  // Fork|Sources/Vorssaint/UI/Notch/NotchControlsView.swift' \
    'case .tasks: return ForkTodoistStrings.current.title  // Fork|Sources/Vorssaint/UI/Notch/NotchControlsView.swift' \
    'case .tasks: perform { ForkTodoistPanel.shared.show() }  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case deploys  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .deploys: return ForkVercelLogic.title(french: language == .fr)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .deploys: return .controls  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'self == .deploys ? ForkVercelLogic.islandSymbol|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'ForkVercelLogic.islandActivityShown() ? [.deploys] : []|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case .deploys: return geometry.compactCalendarGeometry(wing: ForkVercelLogic.islandStripWing(geometry))|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case .deploys: return layout.keepAwakeSurface(reading: ForkVercelLogic.islandReading()|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'if ForkVercelLogic.isNotice(symbol: selectedNotice.symbol)|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case .deploys: ForkVercelCapsuleStrip(service: service, size: size, displayGeometry: geometry)|Sources/Vorssaint/UI/Notch/NotchMirrorView.swift' \
    'case .deploys: ForkVercelStrip(service: service, displayGeometry: mirror.strip)|Sources/Vorssaint/UI/Notch/NotchMirrorView.swift' \
    'case .deploys: ForkVercelCapsuleStrip(service: service, size: size)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .deploys: ForkVercelStrip(service: service, displayGeometry: geometry)|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'ForkVercelNotice.tint(for: notice.symbol)|Sources/Vorssaint/UI/Notch/NotchNoticeView.swift' \
    'case .weather: return ForkWeatherLogic.pageSymbol  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .weather: return "e"  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .weather: return ForkWeatherLogic.pageAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .weather: ForkWeatherIslandPage(size: pageSize)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .weather: return ForkWeatherLogic.title(french: language == .fr)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .weather: ForkWeatherIslandPage(size: size)  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .weather: return .cyan  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .weather: return ForkWeatherLogic.pageSummary(|Sources/Vorssaint/Core/NotchEditorStrings.swift' \
    'ForkWeatherSettingsSection()  // Fork|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'ForkVercelSettingsSection()  // Fork|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'ForkTodoistSettingsSection()  // Fork|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'let forkDecor = ForkMascotDecor()  // Fork|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'forkDecor.connect(rig: self, hopper: hopper, squasher: squasher, tilter: tilter, body: fill, outline: fillMask)|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'forkDecor.reacted(reaction)  // Fork|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'forkDecor.variantOverride = context.environment.forkMascotVariant  // Fork: a preview|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'forkDecor.variantOverride = context.environment.forkMascotVariant  // Fork: kept as it updates|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'forkDecor.configure(size: size, scale: scale)  // Fork|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'forkDecor.moodChanged(mood)  // Fork|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'let length = forkDecor.idleBeat() { pauseBlinking(for: length, from: nil); return }|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'private let forkGaze = ForkMascotGaze()  // Fork|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'forkGaze.sync(host: self, on: followsPointer)  // Fork|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'ForkMascotLife.notePetted()  // Fork|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'path: ForkMascotLife.path(for: visit, base: NotchMascotMotion.path(|Sources/Vorssaint/UI/Notch/NotchMascotView.swift' \
    'ForkMascotLife.restingMood(base: KeepAwakeManager.shared.isActive|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'ForkMascotSettingsRows()  // Fork|Sources/Vorssaint/UI/Settings/NotchMascotSettings.swift' \
    'case ambient, tasks, weather  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient: return ForkAmbientLogic.pageSymbol  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .tasks: return ForkTodoistLogic.pageSymbol  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient: return "u"  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .tasks: return "k"  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient: return ForkAmbientLogic.pageAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .tasks: return ForkTodoistLogic.pageAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient: ForkAmbientIslandPage(size: pageSize)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .tasks: ForkTodoistIslandPage(size: pageSize)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .ambient: return ForkAmbientLogic.title(french: language == .fr)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .tasks: return ForkTodoistLogic.title(french: language == .fr)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .ambient: ForkAmbientIslandPage(size: size)  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .tasks: ForkTodoistIslandPage(size: size)  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .ambient: return .indigo  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .tasks: return .red  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .mixer, .system, .tools, .ambient, .tasks, .weather, .translate:  // Fork|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'case .ambient: return ForkAmbientLogic.pageSummary(french: L10n.shared.language == .fr)  // Fork|Sources/Vorssaint/Core/NotchEditorStrings.swift' \
    'case .tasks: return ForkTodoistLogic.pageSummary(french: L10n.shared.language == .fr)  // Fork|Sources/Vorssaint/Core/NotchEditorStrings.swift' \
    '.scratchpad, .watch, .ambient, .tasks, .weather, .translate:  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .ambient, .tasks, .weather, .translate, .home, .printer: return nil  // Fork|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'private var forkVariant = "classic"  // Fork|Sources/Vorssaint/UI/Settings/NotchMascotSettings.swift' \
    'ForkMascotVariantPicker(look: look)  // Fork|Sources/Vorssaint/UI/Settings/NotchMascotSettings.swift' \
    'ForkMascotVariantLogic.variant(forkVariant).keepsShape {  // Fork|Sources/Vorssaint/UI/Settings/NotchMascotSettings.swift' \
    'ForkRoundStepSettingsRows(volume: volume && volumeAvailable, brightness: brightness && brightnessAvailable)  // Fork|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'ForkRoundSteps.volumeLevel(current: $0, direction: direction, fine: fine) ?? NotchSupport.volumeLevel(current: $0, direction: direction, fine: fine)  // Fork|Sources/Vorssaint/Services/Audio/PreciseVolumeRollerService.swift' \
    'BrightnessSupport.steppedBrightness(current, delta: delta)  // Fork: key step|Sources/Vorssaint/Services/Display/BrightnessService.swift' \
    'BrightnessSupport.steppedBrightness(current, delta: delta)  // Fork: system route|Sources/Vorssaint/Services/Display/BrightnessService.swift' \
    'ForkTranslateSettingsSection()  // Fork: translation of the selection|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'case translate  // Fork: the Translation page|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .translate: return ForkTranslateLogic.pageSymbol  // Fork: the Translation page|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .translate: return ForkTranslateLogic.pageSymbol  // Fork: the Translate button|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .translate: return "l"  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .translate: return ForkTranslateLogic.pageAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case translate  // Fork: translation (ForkTranslateLogic)|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .translate: return .none  // Fork: translation|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .translate: return ForkTranslateLogic.islandControlAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .translate: ForkTranslateIslandPage(size: pageSize)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .translate: return ForkTranslateLogic.title(french: language == .fr)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .translate: ForkTranslateIslandPage(size: size)  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .translate: return .blue  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .translate: return ForkTranslateLogic.pageSummary(|Sources/Vorssaint/Core/NotchEditorStrings.swift' \
    'case .translate: ForkTranslateIslandTile(service: service)  // Fork|Sources/Vorssaint/UI/Notch/NotchControlsView.swift' \
    'case .translate: return ForkTranslateStrings.current.translate  // Fork|Sources/Vorssaint/UI/Notch/NotchControlsView.swift' \
    'case .translate: ForkTranslate.shared.translateSelection()  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case home  // Fork: the Home page|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .home: return ForkHomeLogic.pageSymbol  // Fork: the Home page|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .home: return "h"  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .home: return ForkHomeLogic.pageAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case home  // Fork: Home Assistant (ForkHomeLogic)|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .home: return ForkHomeLogic.pageSymbol  // Fork: the Home button|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .home: return .none  // Fork: Home Assistant|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .home: return ForkHomeLogic.islandControlAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .home:  // Fork: every favourite shown, never scrolled|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'ForkHomeLogic.contentHeight(contentWidth) ?? budget)|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .home: ForkHomeIslandPage(size: pageSize)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .home: return ForkHomeLogic.title(french: language == .fr)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .home: ForkHomeIslandPage(size: size)  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .home: return .teal  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .home: return ForkHomeLogic.pageSummary(|Sources/Vorssaint/Core/NotchEditorStrings.swift' \
    'case .home: ForkHomeIslandTile(service: service)  // Fork|Sources/Vorssaint/UI/Notch/NotchControlsView.swift' \
    'case .home: return ForkHomeStrings.current.title  // Fork|Sources/Vorssaint/UI/Notch/NotchControlsView.swift' \
    'case .home: select(.home)  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case printer  // Fork: the Printer page|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .printer: return ForkBambuLogic.pageSymbol  // Fork: the Printer page|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .printer: return "j"  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .printer: return ForkBambuLogic.pageAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case printer  // Fork: Bambu Lab (ForkBambuLogic)|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .printer: return ForkBambuLogic.pageSymbol  // Fork: the Printer button|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .printer: return .none  // Fork: Bambu Lab|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .printer: return ForkBambuLogic.islandControlAvailable(in: defaults)  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .printer:  // Fork: the camera and the print, never scrolled|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'ForkBambuLogic.contentHeight(contentWidth) ?? budget)|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'case .printer: ForkBambuIslandPage(size: pageSize)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .printer: return ForkBambuLogic.title(french: language == .fr)  // Fork|Sources/Vorssaint/UI/Notch/NotchView.swift' \
    'case .printer: ForkBambuIslandPage(size: size)  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .printer: return .green  // Fork|Sources/Vorssaint/UI/Settings/NotchContentEditor.swift' \
    'case .printer: return ForkBambuLogic.pageSummary(|Sources/Vorssaint/Core/NotchEditorStrings.swift' \
    'case .printer: ForkBambuIslandTile(service: service)  // Fork|Sources/Vorssaint/UI/Notch/NotchControlsView.swift' \
    'case .printer: return ForkBambuStrings.current.title  // Fork|Sources/Vorssaint/UI/Notch/NotchControlsView.swift' \
    'case .printer: select(.printer)  // Fork|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'case .printer: ForkBambuSettingsSection()  // Fork|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    '.init(ForkBambuLogic.searchTerms(french: language == .fr), notch: .module(.printer)),  // Fork|Sources/Vorssaint/UI/Settings/SettingsDirectory.swift' \
    'case .home: ForkHomeSettingsSection()  // Fork|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'reason: available || module == .home || module == .printer ? nil :|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    '} else if module == .home || module == .printer {  // Fork|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    '.init(ForkHomeLogic.searchTerms(french: language == .fr), notch: .module(.home)),  // Fork|Sources/Vorssaint/UI/Settings/SettingsDirectory.swift' \
    'case forkWaiting, forkTime, forkResume  // Fork|Sources/Vorssaint/Services/Notch/NotchAgentSupport.swift' \
    'case .forkWaiting, .forkTime, .forkResume: return ForkAgentCardsLogic.symbol(self)  // Fork|Sources/Vorssaint/Services/Notch/NotchAgentSupport.swift' \
    'var followsPeriod: Bool { self == .spend || self == .trend || self == .models || self == .projects || self == .forkTime }  // Fork|Sources/Vorssaint/Services/Notch/NotchAgentSupport.swift' \
    'return ForkAgentCardsLogic.arranged(orderedCards(in: defaults).filter|Sources/Vorssaint/Services/Notch/NotchAgentSupport.swift' \
    'case .forkWaiting, .forkTime, .forkResume: return ForkAgentCardsLogic.title(card|Sources/Vorssaint/Core/NotchAgentStrings.swift' \
    '@ObservedObject private var forkSessions = ForkClaudeSessions.shared  // Fork|Sources/Vorssaint/UI/Notch/NotchAgentsView.swift' \
    'case .forkWaiting, .forkTime, .forkResume: ForkAgentCard(card: tile.card, period: shown, snapshot: snapshot)  // Fork|Sources/Vorssaint/UI/Notch/NotchAgentsView.swift' \
    'ForkAgentWaitingAlertRow()  // Fork|Sources/Vorssaint/UI/Settings/NotchAgentsSettings.swift' \
    'ForkClaudeSessionsLogic.takeRecords(store.records, next.now)  // Fork|Sources/Vorssaint/Services/AgentUsage/AgentUsageService.swift' \
    'if ForkClaudeSessionsLogic.isNotice(symbol: selectedNotice.symbol) { ForkClaudeSessionsLogic.goToWaiting()|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    '.resets, .forkTime, .forkResume],  // Fork|Tests/NotchAgentTests.swift' \
    '.projects, .forkTime],  // Fork|Tests/NotchAgentTests.swift' \
    '@AppStorage(DefaultsKey.forkAgentsHublotStyle) private var forkStyle = true  // Fork|Sources/Vorssaint/UI/Notch/NotchAgentsView.swift' \
    '} else if rows.isEmpty && !forkStyle {  // Fork|Sources/Vorssaint/UI/Notch/NotchAgentsView.swift' \
    'if forkStyle {  // Fork: Hublot style|Sources/Vorssaint/UI/Notch/NotchAgentsView.swift' \
    'ForkAgentGrid(tiles: rows.flatMap { $0 }, size: size, now: context.date, period: chosenPeriod,|Sources/Vorssaint/UI/Notch/NotchAgentsView.swift' \
    'if ForkAgentLayoutLogic.styleEnabled() {  // Fork: the Hublot style|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'NotchSupport.filteredModules(ForkAgentLayoutLogic.explorerShown(modules,|Sources/Vorssaint/Services/Notch/NotchService.swift' \
    'contentHeight = min(ForkAgentLayoutLogic.styleEnabled() ? max(budget, screen.height|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'ForkAgentLayoutLogic.explorerRows(count: count, columns: sectionColumns, presetRows:  // Fork|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    'let content = min(max(pageBudget, ForkAgentLayoutLogic.explorerFitsAll()|Sources/Vorssaint/Services/Notch/NotchSupport.swift' \
    '@ObservedObject private var forkEditing = ForkAgentEditing.shared  // Fork|Sources/Vorssaint/UI/Notch/NotchSectionsView.swift' \
    'ForkExplorerPicker(modules: service.modules)|Sources/Vorssaint/UI/Notch/NotchSectionsView.swift' \
    '.overlay(alignment: .bottomTrailing) { ForkExplorerEditButton() }  // Fork|Sources/Vorssaint/UI/Notch/NotchSectionsView.swift' \
    'ForkAgentStyleRows()  // Fork|Sources/Vorssaint/UI/Settings/NotchAgentsSettings.swift' \
    'ForkTests.run(suite)|Tests/MetricsTests.swift'; do
    hook="${hook_site%%|*}"
    site="${hook_site##*|}"
    found=$(count "$hook" "$site")
    if [[ "$found" == 1 ]]; then
        ok "$site: $hook"
    else
        fail "$site: expected exactly one '$hook', found $found"
    fi
done

# --- Each fork shortcut has its own id ---------------------------------------
# Two QuickToolHotkey with the same id answer each other's keys: one shortcut
# then fires the other's action, or none at all.
print
print "Fork shortcut ids"
dup_ids=$(grep -rhoE 'QuickToolHotkey\(id: [0-9_]+\)' Sources/Vorssaint/Fork | sort | uniq -d)
if [[ -z "$dup_ids" ]]; then
    ok "every fork shortcut id is unique"
else
    fail "fork shortcut ids used twice: ${dup_ids//$'\n'/, }"
fi
# Registering a shortcut writes a preference under upstream's lock and posts
# a change at once: an owner that registers again from that notification
# freezes the app at launch. Every owner defers it (ForkCoalescedMainAction).
for owner in $(grep -l 'QuickToolHotkey(id:' Sources/Vorssaint/Fork/*.swift); do
    if grep -q 'ForkCoalescedMainAction' "$owner"; then
        ok "${owner:t} defers its shortcut registration"
    else
        fail "${owner:t} registers its shortcut from the preferences' notification without ForkCoalescedMainAction"
    fi
done

# --- The fork's preferences are registered -------------------------------------
# Fork keys are declared in the fork's own file and registered in the fork's
# block of upstream's Core/Defaults.swift. A key that lost its line there would
# read as false or empty, and would silently drop out of settings backups.
print
print "Fork preferences (Core/Defaults.swift)"
FORK_KEYS_FILE="Sources/Vorssaint/Fork/Core/ForkDefaults.swift"
# A key marked "not registered" is machine state, kept out of backups on purpose.
fork_keys=(${(f)"$(grep -v '// not registered' "$FORK_KEYS_FILE" | sed -n 's/^ *static let \(fork[A-Za-z0-9]*\) = .*/\1/p')"})
if (( ${#fork_keys} == 0 )); then
    fail "$FORK_KEYS_FILE declares no fork key: has its format changed?"
fi
for key in $fork_keys; do
    found=$(count "DefaultsKey.$key:" Sources/Vorssaint/Core/Defaults.swift)
    if [[ "$found" == 1 ]]; then
        ok "$key has a registered default"
    else
        fail "$key: expected exactly one registered default in Core/Defaults.swift, found $found"
    fi
done

# --- The camera prompt says what the fork does with the camera -----------------
# Upstream's text promises that nothing is recorded; the fork's camera bubble
# goes into screen recordings. Fork/brand.py rewords it in the staged bundle and
# stops the build when the key is gone; this catches it before any build.
print
print "Permission prompts"
if [[ "$(count '<key>NSCameraUsageDescription</key>' Resources/Info.plist)" == 1 ]]; then
    ok "upstream's camera prompt is where the identity pass expects it"
else
    fail "Resources/Info.plist no longer has one NSCameraUsageDescription: review BUNDLE_TEXTS in Fork/brand.py"
fi
staged_bundles=(build/stage.noindex/*.app(N))
if (( ${#staged_bundles} )); then
    for staged in $staged_bundles; do
        if [[ "$(count 'Nothing is recorded' "$staged/Contents/Info.plist")" == 0 ]]; then
            ok "${staged:t}: the camera prompt is the fork's"
        else
            fail "${staged:t} still shows upstream's camera prompt: rebuild, then check Fork/brand.py"
        fi
    done
else
    print "  - no staged bundle: prompt not checked"
fi
# Home Assistant (ForkHome) is reached on the local network: without the
# prompt's text macOS 15 shows a bare request, and without
# NSAllowsLocalNetworking plain http to homeassistant.local is refused.
for staged in $staged_bundles; do
    if [[ "$(count '<key>NSLocalNetworkUsageDescription</key>' "$staged/Contents/Info.plist")" == 1 \
          && "$(count '<key>NSAllowsLocalNetworking</key>' "$staged/Contents/Info.plist")" == 1 ]]; then
        ok "${staged:t}: local network prompt and local http in place"
    else
        fail "${staged:t} lacks the local network keys: rebuild, then check BUNDLE_ADDITIONS in Fork/brand.py"
    fi
done

# --- 3. The fan helper trusts the fork's team, not upstream's ------------------
# Upstream hardcodes its Apple team in the XPC code requirement of the fan
# helper. The identity pass swaps it for FORK_TEAM_ID; if upstream ever moves
# or rewrites that literal, the swap would stop applying without any error and
# the release variant's helper would refuse the app.
print
print "Fan helper signing team"
source Fork/identity.sh
UPSTREAM_TEAM="3D485NHW29"
FAN_XPC="Sources/Vorssaint/Services/FanControl/FanControlXPC.swift"
if [[ "${FORK_TEAM_ID:-}" =~ '^[A-Z0-9]{10}$' ]]; then
    ok "FORK_TEAM_ID is set ($FORK_TEAM_ID)"
else
    fail "Fork/identity.sh does not define a 10-character FORK_TEAM_ID"
fi
if [[ "$(count "static let teamID = \"$UPSTREAM_TEAM\"" "$FAN_XPC")" == 1 ]]; then
    ok "upstream's team literal is where the identity pass expects it"
else
    fail "$FAN_XPC no longer declares teamID = \"$UPSTREAM_TEAM\": review the helper's code requirement"
fi
FAN_XPC_MIRROR="build/objects/fork-sources/Services/FanControl/FanControlXPC.mirror.swift"
if [[ -f "$FAN_XPC_MIRROR" ]]; then
    if [[ "$(count "$UPSTREAM_TEAM" "$FAN_XPC_MIRROR")" == 0 \
          && "$(count "static let teamID = \"${FORK_TEAM_ID:-}\"" "$FAN_XPC_MIRROR")" == 1 ]]; then
        ok "the compiled mirror requires team ${FORK_TEAM_ID:-}"
    else
        fail "the compiled mirror still names upstream's team: rebuild, then check Fork/brand.py"
    fi
else
    print "  - no build yet: mirror not checked"
fi

# --- 4. The signing certificate is there and not about to expire ---------------
# build.sh refuses to build without it (Fork/build-hooks.zsh). A Developer ID
# certificate lasts five years; renewing it within the same team keeps the
# app's permissions and the helper's trust, so the only risk is being surprised.
print
print "Signing certificate (Developer ID Application, team ${FORK_TEAM_ID:-?})"
latest_epoch=0
latest_end=""
certificate=""
while IFS= read -r line; do
    certificate+="$line"$'\n'
    if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
        subject="$(print -r -- "$certificate" | openssl x509 -noout -subject 2>/dev/null || true)"
        if [[ "$subject" == *"OU=${FORK_TEAM_ID:-none}"* ]]; then
            end="$(print -r -- "$certificate" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
            epoch="$(date -j -f '%b %e %T %Y %Z' "$end" +%s 2>/dev/null || print 0)"
            if (( epoch > latest_epoch )); then
                latest_epoch=$epoch
                latest_end="$end"
            fi
        fi
        certificate=""
    fi
done < <(security find-certificate -a -c "Developer ID Application" -p 2>/dev/null || true)
if (( latest_epoch == 0 )); then
    fail "no Developer ID Application certificate for this team in the keychain"
else
    days_left=$(( (latest_epoch - $(date +%s)) / 86400 ))
    if (( days_left < 0 )); then
        fail "the certificate expired on $latest_end: renew it before the next build"
    elif (( days_left < 30 )); then
        print "  ⚠ the certificate expires on $latest_end, in $days_left day(s): renew it now"
    else
        ok "valid until $latest_end ($days_left days left)"
    fi
fi

print
if (( failures == 0 )); then
    print "FORK CHECKS OK"
else
    print -u2 "FORK CHECKS FAILED ($failures)"
    exit 1
fi
