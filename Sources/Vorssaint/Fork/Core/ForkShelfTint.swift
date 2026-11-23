// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The colour the clipboard shelf is tinted with, chosen in its settings,
/// stored as a "#RRGGBB" string, with how strongly it shows. Pure values.
enum ForkShelfTint {
    /// A soft blue, so the shelf has a little colour out of the box.
    static let defaultHex = "#3D7BFF"
    static let defaultIntensity: Double = 0.35
    static let intensityRange: ClosedRange<Double> = 0...1

    /// The colour of a stored string, nil for none or anything unreadable.
    static func components(_ hex: String?) -> (red: Double, green: Double, blue: Double)? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// A colour as the string stored, its channels kept within 0...1.
    static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ channel: Double) -> Int { Int((min(max(channel.isFinite ? channel : 0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    static func intensity(_ stored: Double) -> Double {
        guard stored.isFinite else { return defaultIntensity }
        return min(max(stored, intensityRange.lowerBound), intensityRange.upperBound)
    }
}
