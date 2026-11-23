// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The fork's own suites, run as the `fork` group of the harness
/// (`./build.sh --test-suite=fork`). Tests/MetricsTests.swift calls this from
/// one line; every fork test file is listed here, never there.
enum ForkTests {
    static func run(_ suite: TestSuite) {
        ForkCaptureTests.run(suite)
        ForkWindowCaptureTests.run(suite)
        ForkPreviewCardTests.run(suite)
        ForkPreviewCardGestureTests.run(suite)
        ForkCaptureMenuTests.run(suite)
        ForkCaptureAreaTests.run(suite)
        ForkScrollingTests.run(suite)
        ForkPinTests.run(suite)
        ForkRecorderTests.run(suite)
        ForkRecorderDeviceTests.run(suite)
        ForkRecorderImageTests.run(suite)
        ForkRecorderMusicTests.run(suite)
        ForkRecorderBoostTests.run(suite)
        ForkRecorderFocusTests.run(suite)
        ForkRecorderKeyTests.run(suite)
        ForkClipboardTests.run(suite)
        ForkClipboardBoardTests.run(suite)
        ForkClipboardCardTests.run(suite)
        ForkShelfTintTests.run(suite)
        ForkClipboardCopySoundTests.run(suite)
        ForkTitleBarGestureTests.run(suite)
        ForkSwishTests.run(suite)
        ForkTrackpadSwitchTests.run(suite)
        ForkLyricsTests.run(suite)
        ForkSpotifyTests.run(suite)
        ForkUpdateTests.run(suite)
    }
}
