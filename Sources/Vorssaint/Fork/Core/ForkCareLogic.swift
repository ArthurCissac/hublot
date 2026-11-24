// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9e, the look shared by the fork's cleaning tools (maintenance,
/// antivirus, disk map): one screen per step, welcome with a single round
/// button, the work under way, then a summary; options behind a link. Pure:
/// the colours, their contrast, the steps and the summaries.
enum ForkCareLogic {
    enum Tool: CaseIterable {
        case maintenance, antivirus, diskMap, smartScan, ambient
    }

    /// A colour in sRGB, each channel from 0 to 1.
    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(hex: UInt32) {
            self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        }

        static let white = RGB(1, 1, 1)
    }

    /// Each tool's background, a dark gradient of its own hue: blue for
    /// maintenance, green for the antivirus, violet for the disk map. Dark
    /// enough for white text everywhere on it. Blue-green for the one-click scan.
    static func gradient(_ tool: Tool) -> (top: RGB, bottom: RGB) {
        switch tool {
        case .maintenance: return (RGB(hex: 0x1E3A8A), RGB(hex: 0x0B1533))
        case .antivirus: return (RGB(hex: 0x065F46), RGB(hex: 0x04221A))
        case .diskMap: return (RGB(hex: 0x5B21B6), RGB(hex: 0x1E0B3D))
        case .smartScan: return (RGB(hex: 0x0B5F73), RGB(hex: 0x05232E))
        case .ambient: return (RGB(hex: 0x312E81), RGB(hex: 0x0F0B2E))
        }
    }

    /// Secondary text is white at this opacity, readable on the cards too.
    static let secondaryOpacity = 0.82

    /// The cards are white at this opacity over the background.
    static let cardOpacity = 0.07

    static func cardBackground(over background: RGB) -> RGB {
        blend(.white, over: background, opacity: cardOpacity)
    }

    /// The round button's fill, a bright gradient of the tool's hue that
    /// stands out from the background. Its white title is large and bold,
    /// so it needs 3:1 on both ends (WCAG's large-text threshold).
    static func buttonGradient(_ tool: Tool) -> (top: RGB, bottom: RGB) {
        switch tool {
        case .maintenance: return (RGB(hex: 0x3B82F6), RGB(hex: 0x1D4ED8))
        case .antivirus: return (RGB(hex: 0x059669), RGB(hex: 0x047857))
        case .diskMap: return (RGB(hex: 0x8B5CF6), RGB(hex: 0x6D28D9))
        case .smartScan: return (RGB(hex: 0x0891B2), RGB(hex: 0x0E7490))
        case .ambient: return (RGB(hex: 0x6366F1), RGB(hex: 0x4338CA))
        }
    }

    /// The round button's title is 17 points semibold: large text.
    static let buttonTitleMinimumContrast = 3.0

    /// The light around the round button and its ring; never behind text.
    static func glow(_ tool: Tool) -> RGB {
        switch tool {
        case .maintenance: return RGB(hex: 0x60A5FA)
        case .antivirus: return RGB(hex: 0x34D399)
        case .diskMap: return RGB(hex: 0xA78BFA)
        case .smartScan: return RGB(hex: 0x22D3EE)
        case .ambient: return RGB(hex: 0xA5B4FC)
        }
    }

    /// A result's colour on the cards: its large figure and its icon.
    enum Category: CaseIterable { case cleaning, protection, performance, warning, danger }

    static func accent(_ category: Category) -> RGB {
        switch category {
        case .cleaning: return RGB(hex: 0x6EE7B7)
        case .protection: return RGB(hex: 0x93C5FD)
        case .performance: return RGB(hex: 0xFCD34D)
        case .warning: return RGB(hex: 0xFDBA74)
        case .danger: return RGB(hex: 0xFCA5A5)
        }
    }

    // MARK: - The light look (the windows follow the system's appearance)

    /// Each tool's background in light mode: a pale wash of its hue, light
    /// enough for near-black text everywhere on it.
    static func lightGradient(_ tool: Tool) -> (top: RGB, bottom: RGB) {
        switch tool {
        case .maintenance: return (RGB(hex: 0xDBEAFE), RGB(hex: 0xF5F8FF))
        case .antivirus: return (RGB(hex: 0xD1FAE5), RGB(hex: 0xF3FDF8))
        case .diskMap: return (RGB(hex: 0xEDE9FE), RGB(hex: 0xF9F7FF))
        case .smartScan: return (RGB(hex: 0xCFFAFE), RGB(hex: 0xF2FCFE))
        case .ambient: return (RGB(hex: 0xE0E7FF), RGB(hex: 0xF6F7FF))
        }
    }

    /// Text in light mode: near-black, and a slate grey for what is secondary.
    static let lightPrimary = RGB(hex: 0x0F172A)
    static let lightSecondary = RGB(hex: 0x475569)

    /// The cards are white at this opacity over the light background.
    static let lightCardOpacity = 0.62

    static func lightCardBackground(over background: RGB) -> RGB {
        blend(.white, over: background, opacity: lightCardOpacity)
    }

    /// A result's colour on light cards: the same hues, deep enough to read.
    static func lightAccent(_ category: Category) -> RGB {
        switch category {
        case .cleaning: return RGB(hex: 0x047857)
        case .protection: return RGB(hex: 0x1D4ED8)
        case .performance: return RGB(hex: 0xA16207)
        case .warning: return RGB(hex: 0xC2410C)
        case .danger: return RGB(hex: 0xB91C1C)
        }
    }

    /// The tool's hue for a symbol or a figure: its light on the dark
    /// background, its deepest button shade on the light one.
    static func tint(_ tool: Tool, dark: Bool) -> RGB {
        dark ? glow(tool) : buttonGradient(tool).bottom
    }

    /// WCAG relative luminance.
    static func luminance(_ colour: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.040_45 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour.red) + 0.7152 * linear(colour.green) + 0.0722 * linear(colour.blue)
    }

    /// WCAG contrast ratio, from 1 to 21.
    static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let (light, dark) = luminance(first) >= luminance(second)
            ? (luminance(first), luminance(second)) : (luminance(second), luminance(first))
        return (light + 0.05) / (dark + 0.05)
    }

    /// A colour laid over another at some opacity, as the screen shows it.
    static func blend(_ top: RGB, over bottom: RGB, opacity: Double) -> RGB {
        RGB(top.red * opacity + bottom.red * (1 - opacity),
            top.green * opacity + bottom.green * (1 - opacity),
            top.blue * opacity + bottom.blue * (1 - opacity))
    }

    /// Which screen a tool shows. The work under way wins over a summary.
    enum Stage: Equatable { case welcome, working, summary }

    static func stage(working: Bool, summaryReady: Bool) -> Stage {
        working ? .working : (summaryReady ? .summary : .welcome)
    }

    /// The round button's ring, from 0 to 1; nil when the length is unknown.
    static func progress(done: Int, total: Int) -> Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(done) / Double(total)))
    }

    /// How a maintenance run went, from each job's success.
    enum MaintenanceOutcome: Equatable {
        case allDone(Int)
        case partly(done: Int, failed: Int)
        case nothingRan
    }

    /// Whether a count takes the plural: from 2 in French (0 and 1 are
    /// singular), anything but 1 in English.
    static func isPlural(_ count: Int, french: Bool) -> Bool {
        french ? count > 1 : count != 1
    }

    static func maintenanceOutcome(_ results: [Bool]) -> MaintenanceOutcome {
        guard !results.isEmpty else { return .nothingRan }
        let failed = results.filter { !$0 }.count
        return failed == 0 ? .allDone(results.count) : .partly(done: results.count - failed, failed: failed)
    }
}
