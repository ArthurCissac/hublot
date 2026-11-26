// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit

/// The Hublot icon in the menu bar without its empty sides. Upstream draws
/// every state on a 26 pt canvas made for Vorssaint's wide mark; Hublot's
/// round porthole is about 14 pt wide, which left some 6 pt of nothing on
/// each side, more than between macOS's own items. The image is cut to its
/// ink plus a point. Off with `forkTightMenuBarIcon`. Main thread only.
enum ForkMenuBarIconTrim {
    private static var cache: (source: ObjectIdentifier, result: NSImage)?

    static func trimmed(_ image: NSImage?) -> NSImage? {
        guard let image, UserDefaults.standard.bool(forKey: DefaultsKey.forkTightMenuBarIcon) else { return image }
        if let cache, cache.source == ObjectIdentifier(image) { return cache.result }
        guard let ink = inkBounds(of: image) else { return image }
        let rect = ForkMenuBarIconLogic.trimmedRect(ink: ink, canvas: image.size, margin: 1)
        guard rect.width < image.size.width - 0.5 else { return image }
        let result = NSImage(size: rect.size, flipped: false) { destination in
            image.draw(in: destination, from: rect, operation: .sourceOver, fraction: 1)
            return true
        }
        result.isTemplate = image.isTemplate
        result.accessibilityDescription = image.accessibilityDescription
        cache = (ObjectIdentifier(image), result)
        return result
    }

    /// Where the image has ink, in points, read from a bitmap at twice its size.
    private static func inkBounds(of image: NSImage) -> CGRect? {
        let sampling = 2
        let wide = Int(ceil(image.size.width)) * sampling, high = Int(ceil(image.size.height)) * sampling
        guard wide > 0, high > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: wide, pixelsHigh: high, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(wide), height: CGFloat(high)))
        NSGraphicsContext.restoreGraphicsState()
        var minX = wide, maxX = -1
        for x in 0..<wide {
            for y in 0..<high where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                break
            }
        }
        guard maxX >= minX else { return nil }
        let unit = CGFloat(sampling)
        return CGRect(x: CGFloat(minX) / unit, y: 0, width: CGFloat(maxX - minX + 1) / unit, height: image.size.height)
    }
}
