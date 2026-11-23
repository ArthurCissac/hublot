// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AudioToolbox
import Foundation

/// The sound a screenshot makes.
///
/// It is macOS's own screen-capture sound, read from the system folder at run
/// time: nothing is bundled with the app. It plays through the system-sound
/// service rather than as ordinary audio, so it uses the alert volume and
/// stays silent when "Play user interface sound effects" is off.
enum ForkCaptureSound {
    static let systemSoundPath =
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"

    /// Registered once, on first use. Nil when this macOS no longer ships the
    /// file there: a capture then stays silent instead of failing.
    private static let soundID: SystemSoundID? = {
        var id: SystemSoundID = 0
        let url = URL(fileURLWithPath: systemSoundPath) as CFURL
        guard AudioServicesCreateSystemSoundID(url, &id) == kAudioServicesNoError else { return nil }
        return id
    }()

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.forkScreenshotCaptureSound)
    }

    static func play(defaults: UserDefaults = .standard) {
        guard isEnabled(in: defaults), let soundID else { return }
        AudioServicesPlaySystemSound(soundID)
    }
}
