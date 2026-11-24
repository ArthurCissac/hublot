// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit

/// The background sound in the closed island: how wide the wave draws, and
/// how wide its wings must be. Without a time limit the right side has
/// nothing to show, so the wings fit the mark alone (the wave, or the scene
/// for what plays) and the island stays as narrow as the timer's narrowest.
extension ForkAmbientLogic {
    /// The wave the island shows: four bars.
    static let islandWaveBars = 4

    /// A bar's width and the gap between bars, for a wave `height` tall
    /// (`ForkAmbientWave` draws with these).
    static func waveBarWidth(height: CGFloat) -> CGFloat { max(2, height / 6) }
    static func waveSpacing(height: CGFloat) -> CGFloat { max(1.5, height / 8) }

    static func waveWidth(bars: Int, height: CGFloat) -> CGFloat {
        guard bars > 0 else { return 0 }
        return (CGFloat(bars) * waveBarWidth(height: height)
            + CGFloat(bars - 1) * waveSpacing(height: height)).rounded(.up)
    }

    /// The wider of the two sides, the mark or the time left, drawn as the
    /// strip draws them, with the timer's clearance from the silhouette's
    /// curve and air beside the camera. Without a reading only the mark counts.
    static func stripWing(reading: String?, scenes: Bool = false, in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactTimerGeometry(showsDownloads: false,
                                                        wing: NotchTimerSupport.stripWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let wave = (scenes ? sceneWidth(height: iconSize) : waveWidth(bars: islandWaveBars, height: iconSize))
            + provisional.compactActivityEdgeInset(boxHeight: iconSize, radius: markRadius(height: iconSize, scenes: scenes))
        guard let reading else { return wave + NotchTimerSupport.stripCameraGap }
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let text = (NotchAgentSupport.readingShape(reading) as NSString)
            .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: textSize, weight: .medium)])
            .width.rounded(.up)
            + provisional.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0)
        return max(text, wave) + NotchTimerSupport.stripCameraGap
    }

    /// How round the mark's ends are: the wave's bars fully, a scene's box less.
    static func markRadius(height: CGFloat, scenes: Bool) -> CGFloat { scenes ? height * sceneCornerShare : height / 2 }

    /// Set by the player at launch, read by upstream's island code (which the
    /// tests compile without the player): the wings for what the strip shows
    /// now. Until then, the wave alone.
    static var islandStripWing: (NotchGeometry) -> CGFloat = { stripWing(reading: nil, in: $0) }
}
