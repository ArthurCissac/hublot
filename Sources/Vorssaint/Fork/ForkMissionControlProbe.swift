// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import ApplicationServices

#if VORSSAINT_DEVELOPMENT
/// A feasibility probe for lot 6, Developer builds only: does macOS tell, by
/// accessibility, which windows Mission Control shows and where? It opens
/// Mission Control for a moment, writes what the Dock and WindowManager
/// expose, closes it again, and quits. Nothing else of the app starts.
///
///     open -n "Hublot (Developer).app" --args --probe-mission-control /path/out.txt
///
/// Launched through `open`, the probe is its own app for macOS, so it reads
/// accessibility with this app's permission. Window titles are never
/// written: only their length, and whether one matches a window on screen.
enum ForkMissionControlProbe {
    static let flag = "--probe-mission-control"

    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard let index = arguments.firstIndex(of: flag) else { return }
        let path = index + 1 < arguments.count ? arguments[index + 1]
            : NSTemporaryDirectory() + "mission-control-probe.txt"
        var report = Report()
        report.run()
        try? report.text.write(toFile: path, atomically: true, encoding: .utf8)
        exit(0)
    }

    private struct Report {
        var lines: [String] = []
        var text: String { lines.joined(separator: "\n") + "\n" }
        /// On-screen window titles, by owner, for matching only.
        private var windowTitles: [String: String] = [:]
        private var nodes = 0

        /// Names heard, filled by observers on the main queue while the run loop turns.
        private final class Heard: @unchecked Sendable {
            var names: [String] = []
        }

        mutating func line(_ string: String) { lines.append(string) }

        mutating func run() {
            line("Mission Control probe, \(ProcessInfo.processInfo.operatingSystemVersionString)")
            line("accessibility trusted: \(AXIsProcessTrusted())")
            line("post events allowed: \(CGPreflightPostEventAccess())")
            line("screen recording allowed: \(CGPreflightScreenCaptureAccess())")
            line("")
            line("## Before")
            windows()

            let center = DistributedNotificationCenter.default()
            let heard = Heard()
            let observer = center.addObserver(forName: nil, object: nil, queue: .main) { note in
                heard.names.append(note.name.rawValue)
            }
            let workspace = NSWorkspace.shared.notificationCenter
            let spaceObserver = workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                      object: nil, queue: .main) { _ in
                heard.names.append("NSWorkspace.activeSpaceDidChange")
            }

            let missionControl = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
            NSWorkspace.shared.open(missionControl)
            RunLoop.main.run(until: Date().addingTimeInterval(1.6))

            line("")
            line("## Mission Control open")
            windows()
            line("")
            for bundle in ["com.apple.dock", "com.apple.WindowManager"] {
                tree(bundle: bundle)
                line("")
            }

            NSWorkspace.shared.open(missionControl)
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
            center.removeObserver(observer)
            workspace.removeObserver(spaceObserver)

            line("## Notifications while opening and closing (names only)")
            for name in Array(Set(heard.names)).sorted() { line("  \(name)") }
            line("")
            line("## After")
            windows()
        }

        /// Windows of the Dock and WindowManager, and every layer seen.
        mutating func windows() {
            guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
            else {
                line("  window list unavailable")
                return
            }
            windowTitles = [:]
            var layers: [Int: Int] = [:]
            for window in list {
                let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
                let layer = window[kCGWindowLayer as String] as? Int ?? 0
                layers[layer, default: 0] += 1
                if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                    windowTitles[name] = owner
                }
                guard owner == "Dock" || owner == "WindowManager" else { continue }
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
                let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
                line("  \(owner) layer \(layer) alpha \(alpha) "
                     + "\(Int(bounds["X"] ?? 0)),\(Int(bounds["Y"] ?? 0)) \(Int(bounds["Width"] ?? 0))×\(Int(bounds["Height"] ?? 0))")
            }
            line("  layers: " + layers.keys.sorted().map { "\($0)×\(layers[$0] ?? 0)" }.joined(separator: " "))
            line("  windows with a readable title: \(windowTitles.count)")
        }

        mutating func tree(bundle: String) {
            line("## Accessibility of \(bundle)")
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
                line("  not running")
                return
            }
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 1.0)
            nodes = 0
            walk(application, depth: 0)
            if nodes >= 1_500 { line("  … stopped at 1500 elements") }
        }

        mutating func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= 12, nodes < 1_500 else { return }
            nodes += 1
            // The application itself is never asked its role (see the repository tests).
            let role = depth == 0 ? "AXApplication" : string(element, kAXRoleAttribute) ?? "?"
            var parts = [String(repeating: "  ", count: depth + 1) + role]
            if let subrole = string(element, kAXSubroleAttribute) { parts.append("sub=\(subrole)") }
            if let identifier = string(element, kAXIdentifierAttribute) { parts.append("id=\(identifier)") }
            if let roleDescription = string(element, kAXRoleDescriptionAttribute) { parts.append("desc=\(roleDescription)") }
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
                if let value = string(element, attribute), !value.isEmpty { parts.append("\(attribute)=\(redacted(value))") }
            }
            if let frame = frame(element) {
                parts.append("frame=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height))")
            }
            let children = self.children(element)
            if !children.isEmpty { parts.append("children=\(children.count)") }
            // Every attribute name of a leaf, to see what a thumbnail can tell.
            if children.isEmpty, depth >= 2, nodes < 400 {
                var names: CFArray?
                if AXUIElementCopyAttributeNames(element, &names) == .success, let names = names as? [String] {
                    parts.append("attrs=[\(names.joined(separator: ","))]")
                }
            }
            line(parts.joined(separator: " "))
            for child in children { walk(child, depth: depth + 1) }
        }

        /// A title's length, and whether it is a window's title on screen, or an app's name.
        func redacted(_ value: String) -> String {
            var notes = ["\(value.count) car."]
            if let owner = windowTitles[value] { notes.append("titre de fenêtre de \(owner)") }
            if NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == value }) {
                notes.append("nom d'app")
            }
            return "«" + notes.joined(separator: ", ") + "»"
        }

        func string(_ element: AXUIElement, _ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else {
                return nil
            }
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }

        func children(_ element: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
            else { return [] }
            return value as? [AXUIElement] ?? []
        }

        func frame(_ element: AXUIElement) -> CGRect? {
            var position: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size,
                  CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
            else { return nil }
            var point = CGPoint.zero, extent = CGSize.zero
            // swiftlint:disable:next force_cast
            AXValueGetValue(position as! AXValue, .cgPoint, &point)
            // swiftlint:disable:next force_cast
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            return CGRect(origin: point, size: extent)
        }
    }
}
#endif
