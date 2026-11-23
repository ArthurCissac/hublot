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
if [[ "$(count 'static var neverSelfUpdates: Bool { true }' Sources/Vorssaint/Fork/AppInfo+Fork.swift)" == 1 ]]; then
    ok "neverSelfUpdates is unconditionally true"
else
    fail "AppInfo.neverSelfUpdates is no longer unconditionally true"
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
#   - ForkClipboardShelf (two lines), ForkClipboardSettingsSection: the clipboard
#     history opens upstream's window again, and its setting is gone;
#   - ForkRecorderImageVisibility, ForkRecorderImageDrag (two lines): a picture moved on
#     the editor's stage shows twice while held, or not at all once let go;
#   - ForkRecorderAudioBoost, forkMicrophoneBoost (four lines): the microphone can no
#     longer be made louder than 100 % in the editor;
#   - ForkTitleBarGestures (apply's window: parameter, forkTarget), ForkSwishSettings:
#     title bar gestures act on the frontmost window, or not at all;
#   - ForkDragTopGuardRow: the setting that keeps Mission Control away from a drag is gone;
#   - ForkTrackpadSwitcher (the AppSwitcher extension, the settings row): three fingers
#     on the trackpad no longer open the window switcher;
#   - ForkLyricsNearbyDuration (two lines), ForkLyricsSettingsRow: lyrics a few
#     seconds off the song's length are refused again, or their setting is gone;
#   - forkReadSpotifyQueue (call and extension), ForkSpotifyConnectButton,
#     ForkSpotifyQueueSettingsRows: the island's queue page no longer reads
#     Spotify's queue, cannot sign in, or its settings are gone;
#   - ForkTests: the fork's tests compile but never run.
print
print "Fork hooks in upstream sources"
for hook_site in \
    'ForkBootstrap.run()|Sources/Vorssaint/main.swift' \
    'ForkAttributionView()|Sources/Vorssaint/UI/Settings/SettingsView.swift' \
    'Link(l10n.s.viewOnGitHub, destination: AppInfo.forkRepositoryURL)  // Fork|Sources/Vorssaint/UI/Settings/SettingsView.swift' \
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
    'func forkBeginGestureSession(scope: SwitcherSessionScope, reversed: Bool)|Sources/Vorssaint/Services/Switcher/AppSwitcher.swift' \
    'ForkSwitcherGestureRow(switcherEnabled: switcherEnabled)|Sources/Vorssaint/UI/Settings/SwitcherSettings.swift' \
    'ForkLyricsNearbyDuration.candidates(result.data, strictFound: !found.isEmpty, for: track, verifiedArtistAliases: verifiedArtistAliases)  // Fork|Sources/Vorssaint/Services/Notch/NotchLyricsService.swift' \
    'let accumulated = candidates + found + nearby  // Fork: nearby lengths rank last|Sources/Vorssaint/Services/Notch/NotchLyricsService.swift' \
    'if lyricsOnline { ForkLyricsSettingsRow() }|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
    'forkReadSpotifyQueue(after: reply, request: request)  // Fork|Sources/Vorssaint/Services/Notch/NotchMusicService.swift' \
    'fileprivate func forkReadSpotifyQueue(after reply: [String: Any], request: UUID)|Sources/Vorssaint/Services/Notch/NotchMusicService.swift' \
    'ForkSpotifyConnectButton(playback: playback)  // Fork|Sources/Vorssaint/UI/Notch/NotchQueueView.swift' \
    'if queueEnabled, AppFeature.notchQueue.isAvailable { ForkSpotifyQueueSettingsRows() }|Sources/Vorssaint/UI/Settings/NotchSettings.swift' \
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
