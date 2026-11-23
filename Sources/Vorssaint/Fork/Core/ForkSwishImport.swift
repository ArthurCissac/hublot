// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Hublot's Swish-style settings read from Swish's own preferences, so moving
/// over takes one button. Only what Swish actually stores is carried; what it
/// leaves at its default keeps Hublot's, which already matches.
enum ForkSwishImport {
    /// Swish's preference domains: the Setapp build first, then the one sold
    /// directly.
    static let domains = ["co.highlyopinionated.swish-setapp", "co.highlyopinionated.swish"]

    /// Swish's modifiers and the preference each one fills.
    private static let modifiers: [(swish: String, key: String)] = [
        ("generalModifier", DefaultsKey.forkSwishGeneralModifier),
        ("screenModifier", DefaultsKey.forkSwishScreenModifier),
        ("secondaryModifier", DefaultsKey.forkSwishSecondaryModifier),
        ("tertiaryModifier", DefaultsKey.forkSwishTertiaryModifier),
        ("superModifier", DefaultsKey.forkSwishSuperModifier),
    ]

    /// The preferences to write, from Swish's (as `UserDefaults` hands them).
    static func values(fromSwish prefs: [String: Any]) -> [String: Any] {
        var values: [String: Any] = [:]
        for (swish, key) in modifiers {
            guard let raw = int(prefs[swish]) else { continue }
            let mask = raw & ForkSwishModifiers.relevantMask
            if mask != 0 { values[key] = mask }
        }
        if let hotkeys = bool(prefs["hotkeys"]) {
            // Swish can also use WASD or IJKL; only the arrow keys are carried.
            let arrows = string(prefs["hotkeyArrow"]).map { $0 == "arrows" } ?? true
            values[DefaultsKey.forkSwishArrowKeys] = hotkeys && arrows
        }
        if let requireSuper = bool(prefs["requireSuperMod"]) { values[DefaultsKey.forkSwishRequireSuper] = requireSuper }
        if let live = bool(prefs["tooltipLive"]) {
            values[DefaultsKey.forkSwishPreview] = live
            values[DefaultsKey.forkSwishBubble] = live
        }
        if let sensitivity = int(prefs["scrollingSensitivity"]) {
            values[DefaultsKey.forkSwishSensitivity] = max(1, min(5, sensitivity))
        }
        let follows = ["screensMoveCursor", "snappingMoveCursor"].compactMap { bool(prefs[$0]) }
        if !follows.isEmpty { values[DefaultsKey.forkSwishMoveCursor] = follows.contains(true) }
        return values
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue ?? (value as? Int)
    }

    private static func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber).map { $0.intValue != 0 } ?? (value as? Bool)
    }

    /// Swish keeps its choices as JSON strings: `"arrows"` with the quotes.
    private static func string(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        if let data = raw.data(using: .utf8), let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        return raw
    }
}
