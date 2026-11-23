// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The colour of an app's icon, for the band of its clipboard cards. Read
/// once per app from a tiny copy of the icon, then kept. Main thread only.
enum ForkAppTint {
    private static var cache: [String: Color?] = [:]

    static func color(for bundleID: String) -> Color? {
        if let known = cache[bundleID] { return known }
        let tint = bytes(of: InstalledApps.icon(for: bundleID)).flatMap(ForkClipboardCardInfo.bandColor(rgba:))
        let color = tint.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        cache[bundleID] = color
        return color
    }

    /// The icon drawn at 16 by 16, as premultiplied RGBA bytes.
    private static func bytes(of icon: NSImage) -> [UInt8]? {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = icon.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : nil
    }
}
