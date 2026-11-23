// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AVFoundation
import Foundation

/// The hand-over between the stage's copy of a picture and the video's.
/// While a picture is held, the video leaves it out and the stage draws it;
/// once let go, the stage keeps drawing it until upstream has rebuilt the
/// preview with its new place, then the video takes over. Called from one
/// line at the end of upstream's preview rebuild. Main thread only.
final class ForkRecorderImageDrag: ObservableObject {
    static let shared = ForkRecorderImageDrag()

    /// The picture the stage draws in place of the video.
    @Published private(set) var heldID: UUID?
    private var gestureActive = false
    private var fallback: DispatchWorkItem?

    /// A gesture begins on a picture: the video lets go of it.
    func begin(_ id: UUID, player: AVPlayer) {
        fallback?.cancel()
        gestureActive = true
        guard heldID != id else { return }
        heldID = id
        ForkRecorderImageVisibility.hide(id)
        Self.redraw(player)
    }

    /// The gesture is over; the video takes the picture back with the next rebuild.
    func end(player: AVPlayer) {
        gestureActive = false
        // A gesture that changed nothing brings no rebuild: give the picture back anyway.
        let work = DispatchWorkItem { [weak self] in self?.release(player: player) }
        fallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Upstream has installed a rebuilt preview.
    static func previewRebuilt(_ player: AVPlayer) {
        shared.previewRebuilt(player)
    }

    private func previewRebuilt(_ player: AVPlayer) {
        guard !gestureActive, heldID != nil else {
            Self.redraw(player)
            return
        }
        release(player: player)
    }

    private func release(player: AVPlayer) {
        fallback?.cancel()
        fallback = nil
        guard !gestureActive, let id = heldID else { return }
        ForkRecorderImageVisibility.show(id)
        heldID = nil
        Self.redraw(player)
    }

    /// A paused player shows the frame it last drew; asking for the same
    /// moment again draws it anew, with the composition as it is now.
    static func redraw(_ player: AVPlayer) {
        guard player.rate == 0, let item = player.currentItem else { return }
        player.seek(to: item.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
