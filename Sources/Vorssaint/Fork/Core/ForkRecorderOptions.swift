// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AVFoundation
import Foundation

/// The recording options the fork adds, read by one-line hooks in upstream's
/// exporter and edit document. Both files are compiled by the harness too, so
/// everything here stays free of AppKit and of the fork's interface code.
enum ForkRecorderOptions {
    /// One channel when the sound is wanted in mono, two otherwise.
    static func channelCount(mono: Bool) -> Int {
        mono ? 1 : 2
    }

    /// The channel count of an exported recording's sound. The take itself is
    /// always recorded in stereo: mono is a choice about the finished file,
    /// made by mixing the two channels down as the export reads them.
    static func exportChannelCount(in defaults: UserDefaults = .standard) -> Int {
        channelCount(mono: defaults.bool(forKey: DefaultsKey.forkRecorderMonoAudio))
    }

    /// What the export adds to the settings it reads the sound with. Nothing
    /// in stereo: naming a channel count there, even two, changes how the
    /// tracks are mixed and no longer matches upstream's levels. In mono, the
    /// one channel the mix is brought down to.
    static func exportReaderSettings(in defaults: UserDefaults = .standard) -> [String: Any] {
        exportChannelCount(in: defaults) == 1 ? [AVNumberOfChannelsKey: 1] : [:]
    }

    /// Whether a new recording shows a ring on each click. A preference that
    /// was never registered reads as upstream's own default, which is on.
    /// The region to record when the camera bubble is on. Upstream records a
    /// clicked window from that window's own buffer, which holds nothing but
    /// the window: the bubble would be left out of the video. With the bubble
    /// on, the window's area is recorded instead, as a drawn area would be.
    /// The price: the recording no longer follows the window if it moves.
    static func recordedRegion(_ region: RecorderSupport.Region, withCamera: Bool) -> RecorderSupport.Region {
        guard withCamera, region.windowID != nil else { return region }
        return RecorderSupport.Region(displayID: region.displayID, windowID: nil, pixelRect: region.pixelRect,
                                      anchorRect: region.anchorRect, scale: region.scale)
    }

    static func showsClicks(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.forkRecorderShowsClicks) as? Bool ?? true
    }
}
