// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Lot 9i: the Care window (`ForkCareHub`), one window for every cleaning
/// tool, a sidebar on the left to go from one to another. Which tools, in
/// which order, their colours and the short state line under each name.
enum ForkCareHubLogic {
    typealias RGB = ForkCareLogic.RGB

    enum Module: String, CaseIterable, Identifiable {
        case smartScan, cleanup, protection, performance, applications, diskMap

        var id: String { rawValue }

        /// ⌘1 to ⌘6, in the sidebar's order.
        var digit: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

        var symbol: String {
            switch self {
            case .smartScan: return "wand.and.stars"
            case .cleanup: return "trash"
            case .protection: return "checkmark.shield"
            case .performance: return "wrench.and.screwdriver"
            case .applications: return "square.grid.2x2"
            case .diskMap: return "square.grid.3x3.square"
            }
        }

        /// The fork's own tool behind a module, with its colours; nil for the
        /// two pages upstream draws (the cleaner and the uninstaller).
        var tool: ForkCareLogic.Tool? {
            switch self {
            case .smartScan: return .smartScan
            case .protection: return .antivirus
            case .performance: return .maintenance
            case .diskMap: return .diskMap
            case .cleanup, .applications: return nil
            }
        }

        /// The module's hue in the sidebar: its tool's light, or a hue of its own.
        var tint: RGB {
            if let tool { return ForkCareLogic.glow(tool) }
            return self == .cleanup ? RGB(hex: 0xF472B6) : RGB(hex: 0xFB923C)
        }
    }

    static func module(forDigit digit: Int) -> Module? {
        Module.allCases.first { $0.digit == digit }
    }

    /// The module last open, so the window comes back where it was left.
    static func module(stored raw: String?) -> Module {
        raw.flatMap(Module.init(rawValue:)) ?? .smartScan
    }

    // MARK: - State lines

    /// "today", "yesterday" or "3 days ago", for a past date.
    static func relativeDay(_ date: Date, now: Date, french: Bool, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return french ? "aujourd’hui" : "today"
        case 1: return french ? "hier" : "yesterday"
        default: return french ? "il y a \(days) jours" : "\(days) days ago"
        }
    }

    /// The antivirus: threats to look at first, then a scan under way, then the last scan.
    static func protectionState(threats: Int, scanning: Bool, lastScan: Date?, now: Date, french: Bool) -> String? {
        if threats > 0 {
            if french { return threats == 1 ? "1 menace à examiner" : "\(threats) menaces à examiner" }
            return threats == 1 ? "1 threat to review" : "\(threats) threats to review"
        }
        if scanning { return french ? "Analyse en cours…" : "Scanning…" }
        guard let lastScan else { return nil }
        let day = relativeDay(lastScan, now: now, french: french)
        return french ? "Analysé \(day)" : "Scanned \(day)"
    }

    /// Maintenance: jobs under way, otherwise the most recent run.
    static func performanceState(running: Bool, lastRun: Date?, now: Date, french: Bool) -> String? {
        if running { return french ? "En cours…" : "Running…" }
        guard let lastRun else { return nil }
        let day = relativeDay(lastRun, now: now, french: french)
        return french ? "Fait \(day)" : "Done \(day)"
    }

    /// The disk map: files counted while it scans, then ready.
    static func diskMapState(scanning: Bool, files: Int, hasMap: Bool, french: Bool) -> String? {
        if scanning {
            let count = files.formatted(.number.locale(Locale(identifier: french ? "fr_FR" : "en_US")))
            return french ? "Analyse… \(count) fichiers" : "Scanning… \(count) files"
        }
        return hasMap ? (french ? "Carte prête" : "Map ready") : nil
    }
}
