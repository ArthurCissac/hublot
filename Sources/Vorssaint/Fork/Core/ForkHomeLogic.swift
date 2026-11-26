// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// The island's Home page (`forkHomeEnabled`): Home Assistant devices chosen
/// as favourites, grouped by room, each with its state and a click for its
/// main action; the same favourites as menu tiles. Home Assistant is reached
/// through its WebSocket API with a long-lived token kept in the Keychain
/// (ForkHome). Pure: the server's address, the messages exchanged, the
/// devices read from its states, what a click may ask (a short allow list)
/// and the words shown.
enum ForkHomeLogic {
    // MARK: - The server's address

    enum AddressProblem: Error, Equatable {
        case invalid
        /// Plain http to a host off the local network: refused.
        case insecure
    }

    /// The server's base address from what is typed: http or https, a host,
    /// an optional port and nothing else. A bare host gets http on the local
    /// network and https elsewhere; plain http is refused off the local network.
    static func address(_ raw: String) -> Result<URL, AddressProblem> {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty, text.count <= 300, !text.contains(where: \.isWhitespace) else { return .failure(.invalid) }
        let bare = !text.contains("://")
        guard var parts = URLComponents(string: bare ? "http://" + text : text),
              let host = parts.host, !host.isEmpty else { return .failure(.invalid) }
        if bare { parts.scheme = isLocal(host: host) ? "http" : "https" }
        guard let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty, parts.port.map({ (1...65535).contains($0) }) ?? true else { return .failure(.invalid) }
        if scheme == "http", !isLocal(host: host) { return .failure(.insecure) }
        parts.scheme = scheme
        guard let url = parts.url else { return .failure(.invalid) }
        return .success(url)
    }

    static func validAddress(_ raw: String?) -> URL? {
        guard let raw, case .success(let url) = address(raw) else { return nil }
        return url
    }

    /// A host on the local network: a single-label name, `.local`, or a
    /// private, loopback or link-local address. These are the names macOS
    /// lets an app reach over plain http (NSAllowsLocalNetworking).
    static func isLocal(host raw: String) -> Bool {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        guard !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host.contains(":") {
            return host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd")
        }
        let numbers = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        if numbers.count == 4, numbers.allSatisfy({ $0.map { (0...255).contains($0) } ?? false }) {
            let a = numbers[0] ?? 0, b = numbers[1] ?? 0
            return a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254)
        }
        return !host.contains(".")
    }

    /// Home Assistant's WebSocket endpoint under its base address.
    static func webSocketURL(_ base: URL) -> URL? {
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.path = "/api/websocket"
        return parts.url
    }

    /// The profile page where long-lived tokens are made.
    static func tokensPage(_ base: URL) -> URL? {
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = "/profile/security"
        return parts.url
    }

    /// A pasted token, or nil when it cannot be one (Home Assistant's are JWTs).
    static func cleanToken(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (20...4096).contains(token.count),
              token.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else { return nil }
        return token
    }

    /// The addresses tried, in order: the main one, then the fallback.
    static func candidates(main: String?, fallback: String?) -> [URL] {
        var urls: [URL] = []
        for url in [validAddress(main), validAddress(fallback)].compactMap({ $0 }) where !urls.contains(url) {
            urls.append(url)
        }
        return urls
    }

    /// Seconds before trying again after a lost or refused connection.
    static func retryDelay(attempt: Int) -> TimeInterval {
        min(60, pow(2, Double(min(max(attempt, 0), 6) + 1)))
    }

    static let maximumMessageSize = 16 << 20
    static let pingInterval: TimeInterval = 30

    // MARK: - Messages

    static func encode(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func authMessage(token: String) -> String? {
        encode(["type": "auth", "access_token": token])
    }

    static func command(id: Int, type: String, _ fields: [String: Any] = [:]) -> String? {
        encode(fields.merging(["id": id, "type": type]) { _, new in new })
    }

    /// The favourites' states now, then each change, in Home Assistant's compressed form.
    static func subscribeEntities(id: Int, entityIDs: [String]) -> String? {
        command(id: id, type: "subscribe_entities", ["entity_ids": entityIDs.filter(isEntityID)])
    }

    static func callService(id: Int, _ call: ServiceCall) -> String? {
        guard isAllowed(call) else { return nil }
        var fields: [String: Any] = ["domain": call.domain, "service": call.service,
                                     "target": ["entity_id": call.entityID]]
        if !call.data.isEmpty { fields["service_data"] = call.data }
        return command(id: id, type: "call_service", fields)
    }

    enum Incoming {
        case authRequired, authOK, authInvalid
        case result(id: Int, success: Bool, value: Any?)
        case event(id: Int, value: [String: Any])
        case pong(id: Int)
        case other
    }

    /// What the server sent: one message, or several when it groups them.
    static func incoming(_ text: String) -> [Incoming] {
        guard text.utf8.count <= maximumMessageSize, let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let objects = (json as? [[String: Any]]) ?? [(json as? [String: Any])].compactMap { $0 }
        return objects.map { object in
            let id = object["id"] as? Int ?? -1
            switch object["type"] as? String {
            case "auth_required": return .authRequired
            case "auth_ok": return .authOK
            case "auth_invalid": return .authInvalid
            case "result": return .result(id: id, success: object["success"] as? Bool ?? false, value: object["result"])
            case "event": return .event(id: id, value: object["event"] as? [String: Any] ?? [:])
            case "pong": return .pong(id: id)
            default: return .other
            }
        }
    }

    // MARK: - States

    /// An entity's state as Home Assistant keeps it.
    struct Raw {
        var state: String
        var attributes: [String: Any]
    }

    static func isEntityID(_ id: String) -> Bool {
        id.count <= 255 && id.range(of: #"^[a-z0-9_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil
    }

    static func domain(of id: String) -> String { String(id.prefix { $0 != "." }) }

    /// Every state from `get_states`.
    static func raws(fromStates value: Any?) -> [String: Raw] {
        var raws: [String: Raw] = [:]
        for object in value as? [[String: Any]] ?? [] {
            guard let id = object["entity_id"] as? String, isEntityID(id), let state = object["state"] as? String else { continue }
            raws[id] = Raw(state: state, attributes: object["attributes"] as? [String: Any] ?? [:])
        }
        return raws
    }

    /// A `subscribe_entities` event applied: `a` adds whole states, `c`
    /// changes some (`+` sets, `-` removes attributes), `r` removes entities.
    static func applying(_ event: [String: Any], to raws: [String: Raw]) -> [String: Raw] {
        var raws = raws
        for (id, value) in event["a"] as? [String: Any] ?? [:] {
            guard isEntityID(id), let state = value as? [String: Any], let text = state["s"] as? String else { continue }
            raws[id] = Raw(state: text, attributes: state["a"] as? [String: Any] ?? [:])
        }
        for (id, value) in event["c"] as? [String: Any] ?? [:] {
            guard var raw = raws[id], let change = value as? [String: Any] else { continue }
            if let added = change["+"] as? [String: Any] {
                if let text = added["s"] as? String { raw.state = text }
                for (key, attribute) in added["a"] as? [String: Any] ?? [:] { raw.attributes[key] = attribute }
            }
            if let removed = change["-"] as? [String: Any] {
                for key in removed["a"] as? [String] ?? [] { raw.attributes[key] = nil }
            }
            raws[id] = raw
        }
        for id in event["r"] as? [String] ?? [] { raws[id] = nil }
        return raws
    }

    // MARK: - Devices

    /// The kinds of device shown. Locks, alarms and the rest are left out;
    /// a gate or a garage door moves only on a second click (`needsConfirmation`).
    enum Kind: String {
        case cover, light, toggle, scene, script, button, sensor, binarySensor
        /// A camera, or an image entity (a 3D printer's chamber picture): shown, never commanded.
        case camera
    }

    static func kind(domain: String) -> Kind? {
        switch domain {
        case "cover": return .cover
        case "light": return .light
        case "switch", "input_boolean", "fan": return .toggle
        case "scene": return .scene
        case "script": return .script
        case "button", "input_button": return .button
        case "sensor": return .sensor
        case "binary_sensor": return .binarySensor
        case "camera", "image": return .camera
        default: return nil
        }
    }

    struct Entity: Equatable, Identifiable {
        let id: String
        let kind: Kind
        let name: String
        let state: String
        var deviceClass: String? = nil
        var unit: String? = nil
        /// A cover's opening, from 0 (closed) to 100.
        var position: Int? = nil
        /// A light's brightness while on, in percent.
        var brightness: Int? = nil
        /// A cover that can be set to a position, a light that can be dimmed.
        var canSetLevel = false
        /// A cover's `supported_features`: 1 open, 2 close, 4 position, 8 stop.
        var features: Int? = nil

        var domain: String { ForkHomeLogic.domain(of: id) }
        var available: Bool { state != "unavailable" }
        /// Garage doors, gates and doors move only on a second click.
        var needsConfirmation: Bool { kind == .cover && ["garage", "gate", "door"].contains(deviceClass ?? "") }
        var canOpen: Bool { features.map { $0 & 1 != 0 } ?? true }
        var canClose: Bool { features.map { $0 & 2 != 0 } ?? true }
        var canStop: Bool { features.map { $0 & 8 != 0 } ?? true }
    }

    static func entity(id: String, raw: Raw) -> Entity? {
        guard isEntityID(id), let kind = kind(domain: domain(of: id)) else { return nil }
        let attributes = raw.attributes
        let named = (attributes["friendly_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var entity = Entity(id: id, kind: kind, name: named.isEmpty ? fallbackName(id) : named, state: raw.state,
                            deviceClass: attributes["device_class"] as? String,
                            unit: attributes["unit_of_measurement"] as? String)
        switch kind {
        case .cover:
            entity.position = (attributes["current_position"] as? Int).map { min(100, max(0, $0)) }
            entity.features = attributes["supported_features"] as? Int
            entity.canSetLevel = ((entity.features ?? 0) & 4) != 0 && !entity.needsConfirmation
        case .light:
            if raw.state == "on", let value = attributes["brightness"] as? Int { entity.brightness = percent(brightness: value) }
            let modes = attributes["supported_color_modes"] as? [String] ?? []
            entity.canSetLevel = modes.contains { $0 != "onoff" } || attributes["brightness"] is Int
        default: break
        }
        return entity
    }

    /// « Volet salon » from `cover.volet_salon` when the device has no name.
    static func fallbackName(_ id: String) -> String {
        let object = id.split(separator: ".").dropFirst().joined().replacingOccurrences(of: "_", with: " ")
        return object.prefix(1).uppercased() + object.dropFirst()
    }

    static func percent(brightness: Int) -> Int {
        Int((Double(min(255, max(0, brightness))) / 255 * 100).rounded())
    }

    // MARK: - What a click asks

    enum Command: Hashable {
        /// A tile's click: toggle, open or close, run, press.
        case main
        case open, close, stop
        case turnOn, turnOff
        /// A cover's position or a light's brightness, in percent.
        case level(Int)
    }

    struct ServiceCall: Equatable {
        let domain: String
        let service: String
        let entityID: String
        var data: [String: Int] = [:]
    }

    /// Every service Hublot may call. Nothing else is ever sent, whatever an
    /// entity claims: no lock, no alarm.
    static let allowedServices: Set<String> = [
        "cover.open_cover", "cover.close_cover", "cover.stop_cover", "cover.set_cover_position",
        "light.toggle", "light.turn_on", "light.turn_off",
        "switch.toggle", "switch.turn_on", "switch.turn_off",
        "input_boolean.toggle", "input_boolean.turn_on", "input_boolean.turn_off",
        "fan.toggle", "fan.turn_on", "fan.turn_off",
        "scene.turn_on", "script.turn_on", "button.press", "input_button.press",
    ]

    static func isAllowed(_ call: ServiceCall) -> Bool {
        isEntityID(call.entityID) && domain(of: call.entityID) == call.domain
            && allowedServices.contains("\(call.domain).\(call.service)")
            && call.data.keys.allSatisfy { ["position", "brightness_pct"].contains($0) }
            && call.data.values.allSatisfy { (0...100).contains($0) }
    }

    /// What a click asks. A gate or a garage door is asked only once the
    /// click is `confirmed` (a second click, or a menu item chosen).
    static func call(_ command: Command, for entity: Entity, confirmed: Bool = false) -> ServiceCall? {
        guard entity.available else { return nil }
        let call: ServiceCall?
        switch (entity.kind, command) {
        case (.cover, _) where entity.needsConfirmation && !confirmed: call = nil
        case (.cover, .open) where !entity.canOpen, (.cover, .close) where !entity.canClose,
             (.cover, .stop) where !entity.canStop: call = nil
        case (.cover, .main):
            let moving = entity.state == "opening" || entity.state == "closing"
            let service = moving ? "stop_cover" : entity.state == "closed" || entity.position == 0 ? "open_cover" : "close_cover"
            call = ServiceCall(domain: "cover", service: service, entityID: entity.id)
        case (.cover, .open): call = ServiceCall(domain: "cover", service: "open_cover", entityID: entity.id)
        case (.cover, .close): call = ServiceCall(domain: "cover", service: "close_cover", entityID: entity.id)
        case (.cover, .stop): call = ServiceCall(domain: "cover", service: "stop_cover", entityID: entity.id)
        case (.cover, .level(let value)) where entity.canSetLevel:
            call = ServiceCall(domain: "cover", service: "set_cover_position", entityID: entity.id,
                               data: ["position": min(100, max(0, value))])
        case (.light, .level(let value)) where entity.canSetLevel:
            call = value <= 0 ? ServiceCall(domain: "light", service: "turn_off", entityID: entity.id)
                : ServiceCall(domain: "light", service: "turn_on", entityID: entity.id, data: ["brightness_pct": min(100, value)])
        case (.light, .main), (.toggle, .main): call = ServiceCall(domain: entity.domain, service: "toggle", entityID: entity.id)
        case (.light, .turnOn), (.toggle, .turnOn): call = ServiceCall(domain: entity.domain, service: "turn_on", entityID: entity.id)
        case (.light, .turnOff), (.toggle, .turnOff): call = ServiceCall(domain: entity.domain, service: "turn_off", entityID: entity.id)
        case (.scene, .main), (.script, .main): call = ServiceCall(domain: entity.domain, service: "turn_on", entityID: entity.id)
        case (.button, .main): call = ServiceCall(domain: entity.domain, service: "press", entityID: entity.id)
        default: call = nil
        }
        return call.flatMap { isAllowed($0) ? $0 : nil }
    }

    /// Whether a tile has something to do on a click (once confirmed, for a gate).
    static func actionable(_ entity: Entity) -> Bool { call(.main, for: entity, confirmed: true) != nil }

    /// A cover's buttons, top to bottom of a remote: up, stop, down, those it supports.
    static func coverButtons(_ entity: Entity) -> [Command] {
        guard entity.kind == .cover else { return [] }
        return [entity.canOpen ? Command.open : nil, entity.canStop ? .stop : nil, entity.canClose ? .close : nil].compactMap { $0 }
    }

    static func commandSymbol(_ command: Command) -> String {
        switch command {
        case .open: return "chevron.up"
        case .stop: return "stop.fill"
        case .close: return "chevron.down"
        case .turnOn: return "power"
        case .turnOff: return "poweroff"
        case .main, .level: return "hand.tap"
        }
    }

    /// What a gate's tile says while it waits for the second click.
    static func confirmText(_ command: Command, for entity: Entity, french: Bool) -> String {
        let service = call(command, for: entity, confirmed: true)?.service ?? ""
        switch service {
        case "open_cover": return french ? "Recliquez pour ouvrir" : "Click again to open"
        case "close_cover": return french ? "Recliquez pour fermer" : "Click again to close"
        case "stop_cover": return french ? "Recliquez pour arrêter" : "Click again to stop"
        default: return french ? "Recliquez pour confirmer" : "Click again to confirm"
        }
    }

    /// How long a gate's first click waits for the second.
    static let confirmWindow: TimeInterval = 4

    /// What kind of device it is, for the list to choose from: a cover and
    /// a switch named alike are told apart.
    static func kindLabel(_ entity: Entity, french: Bool) -> String {
        switch entity.kind {
        case .cover:
            switch entity.deviceClass ?? "" {
            case "curtain": return french ? "Rideau" : "Curtain"
            case "window": return french ? "Fenêtre" : "Window"
            case "garage": return french ? "Porte de garage" : "Garage door"
            case "gate": return french ? "Portail" : "Gate"
            case "door": return french ? "Porte" : "Door"
            case "awning": return french ? "Store banne" : "Awning"
            default: return french ? "Volet" : "Cover"
            }
        case .light: return french ? "Lumière" : "Light"
        case .toggle:
            switch entity.domain {
            case "fan": return french ? "Ventilateur" : "Fan"
            case "input_boolean": return french ? "Bascule" : "Toggle"
            default: return entity.deviceClass == "outlet" ? (french ? "Prise" : "Plug") : (french ? "Interrupteur" : "Switch")
            }
        case .scene: return french ? "Scène" : "Scene"
        case .script: return "Script"
        case .button: return french ? "Bouton" : "Button"
        case .sensor: return french ? "Capteur" : "Sensor"
        case .binarySensor: return french ? "Détecteur" : "Detector"
        case .camera: return entity.domain == "image" ? "Image" : (french ? "Caméra" : "Camera")
        }
    }

    /// Lit: a light or switch on, a cover not closed, a script running, a sensor triggered.
    static func isOn(_ entity: Entity) -> Bool {
        switch entity.kind {
        case .cover: return ["open", "opening", "closing"].contains(entity.state) || (entity.position ?? 0) > 0
        case .light, .toggle, .binarySensor, .script: return entity.state == "on"
        case .scene, .button, .sensor, .camera: return false
        }
    }

    /// Where a horizontal drag on a tile sets its level: steps of five.
    static func level(at x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        return min(100, max(0, Int((x / width * 20).rounded()) * 5))
    }

    /// The level a tile shows: a cover's position, a light's brightness.
    static func level(_ entity: Entity) -> Int? {
        guard entity.canSetLevel else { return nil }
        switch entity.kind {
        case .cover: return entity.position
        case .light: return entity.state == "on" ? entity.brightness ?? 100 : 0
        default: return nil
        }
    }

    // MARK: - A shutter's single button

    /// Where a shutter goes.
    enum Direction: String {
        case up, down
        var opposite: Direction { self == .up ? .down : .up }
    }

    /// The way a shutter last went: asked by a click (`at` its time), or seen
    /// in Home Assistant (`at` the distant past, nothing to wait for).
    struct CoverRun: Equatable {
        var direction: Direction
        var at: Date
        /// Stopped by the ■ beside the arrow.
        var stopped = false
    }

    /// Stopped by hand: no run under way any more, the last one's way kept.
    static func stopped(_ run: CoverRun?) -> CoverRun? {
        run.map { CoverRun(direction: $0.direction, at: .distantPast, stopped: true) }
    }

    /// How long after a click or a stop what Home Assistant reports is its
    /// echo (the module gives its target first, its position later), not a
    /// run seen on its own.
    static let coverQuiet: TimeInterval = 30

    static func follows(lastAction: Date?, now: Date) -> Bool {
        guard let lastAction, now >= lastAction else { return true }
        return now.timeIntervalSince(lastAction) >= coverQuiet
    }

    /// How long after a click the button offers the other way and says the
    /// run asked, before Home Assistant has caught up.
    static let coverSettle: TimeInterval = 10

    /// A shutter's (not a gate's) single button does what its arrow says: up
    /// when closed, down when fully open, the other way from a click just
    /// made or from a run under way; part way, the other way from its last
    /// run (by position when unknown). A cover going one way only offers it.
    static func coverDirection(_ entity: Entity, last: CoverRun?, now: Date) -> Direction {
        let wanted = preferredDirection(entity, last: last, now: now)
        if wanted == .up, !entity.canOpen { return .down }
        if wanted == .down, !entity.canClose { return .up }
        return wanted
    }

    private static func preferredDirection(_ entity: Entity, last: CoverRun?, now: Date) -> Direction {
        switch entity.state {
        case "opening": return .down
        case "closing": return .up
        default: break
        }
        if let last, justAsked(last, now: now) || last.stopped { return last.direction.opposite }
        let position = coverPosition(entity)
        if position <= 0 { return .up }
        if position >= 100 { return .down }
        if let last { return last.direction.opposite }
        return position < 50 ? .up : .down
    }

    private static func justAsked(_ run: CoverRun, now: Date) -> Bool {
        now >= run.at && now.timeIntervalSince(run.at) < coverSettle
    }

    /// Its position, from its state when it reports none.
    static func coverPosition(_ entity: Entity) -> Int {
        entity.state == "closed" ? 0 : entity.position ?? 100
    }

    /// The way it went between two states Home Assistant reported.
    static func movement(from old: Entity, to new: Entity) -> Direction? {
        guard old.kind == .cover, new.kind == .cover, old.available, new.available else { return nil }
        switch new.state {
        case "opening": return .up
        case "closing": return .down
        default: break
        }
        let before = coverPosition(old), after = coverPosition(new)
        return after > before ? .up : after < before ? .down : nil
    }

    static func command(for direction: Direction) -> Command { direction == .up ? .open : .close }

    /// Under its name: the run just asked, or its state and what the button does.
    static func coverText(_ entity: Entity, last: CoverRun?, now: Date, french: Bool) -> String {
        let running: Direction? = entity.state == "opening" ? .up : entity.state == "closing" ? .down
            : last.flatMap { justAsked($0, now: now) ? $0.direction : nil }
        if let running { return running == .up ? (french ? "Montée…" : "Going up…") : (french ? "Descente…" : "Going down…") }
        let position = coverPosition(entity)
        let state = position <= 0 ? (french ? "Fermé" : "Closed") : position >= 100 ? (french ? "Ouvert" : "Open") : "\(position) %"
        let action = coverDirection(entity, last: last, now: now) == .up ? (french ? "Monter" : "Raise") : (french ? "Descendre" : "Lower")
        return "\(state) · \(action)"
    }

    // MARK: - Cameras

    /// A camera's or an image entity's current picture, asked from Home
    /// Assistant with the token in a header (never in the address).
    static func pictureURL(base: URL, entity: Entity) -> URL? {
        guard entity.kind == .camera, isEntityID(entity.id),
              var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = entity.domain == "image" ? "/api/image_proxy/\(entity.id)" : "/api/camera_proxy/\(entity.id)"
        parts.query = nil
        return parts.url
    }

    /// A picture is a few hundred kilobytes; anything far larger is refused.
    static let maximumPictureSize = 8 << 20
    /// How often an open camera asks for its next picture.
    static let pictureInterval: TimeInterval = 1.5

    /// The page's height while a camera is shown: its picture in 16:9, its title above.
    static func viewerHeight(width: CGFloat) -> CGFloat {
        min(400, (max(0, width - 12) * 9 / 16).rounded()) + 34 + pagePadding
    }

    // MARK: - Words

    static func stateText(_ entity: Entity, french: Bool, now: Date = Date(),
                          calendar: Calendar = .autoupdatingCurrent) -> String {
        switch entity.state {
        case "unavailable": return french ? "Indisponible" : "Unavailable"
        case "unknown": return "—"
        default: break
        }
        switch entity.kind {
        case .cover:
            switch entity.state {
            case "opening": return french ? "Ouverture…" : "Opening…"
            case "closing": return french ? "Fermeture…" : "Closing…"
            case "closed": return french ? "Fermé" : "Closed"
            default:
                if let position = entity.position, position < 100, position > 0 {
                    return french ? "Ouvert à \(position) %" : "Open \(position)%"
                }
                return french ? "Ouvert" : "Open"
            }
        case .light, .toggle:
            guard entity.state == "on" else { return french ? "Éteint" : "Off" }
            if let brightness = entity.brightness, entity.kind == .light { return french ? "Allumé · \(brightness) %" : "On · \(brightness)%" }
            return french ? "Allumé" : "On"
        case .scene: return french ? "Activer" : "Activate"
        case .camera: return french ? "Voir" : "View"
        case .script: return entity.state == "on" ? (french ? "En cours" : "Running") : (french ? "Lancer" : "Run")
        case .button: return french ? "Appuyer" : "Press"
        case .binarySensor: return binaryText(entity, french: french)
        case .sensor: return sensorText(entity, french: french, now: now, calendar: calendar)
        }
    }

    private static func binaryText(_ entity: Entity, french: Bool) -> String {
        let on = entity.state == "on"
        switch entity.deviceClass ?? "" {
        case "door", "garage_door", "opening", "window":
            return on ? (french ? "Ouvert" : "Open") : (french ? "Fermé" : "Closed")
        case "motion", "occupancy", "presence":
            return on ? (french ? "Détecté" : "Detected") : (french ? "Rien" : "Clear")
        case "problem": return on ? (french ? "Problème" : "Problem") : "OK"
        case "connectivity": return on ? (french ? "Connecté" : "Connected") : (french ? "Déconnecté" : "Disconnected")
        case "running": return on ? (french ? "En marche" : "Running") : (french ? "À l’arrêt" : "Stopped")
        default: return on ? (french ? "Activé" : "On") : (french ? "Désactivé" : "Off")
        }
    }

    private static func sensorText(_ entity: Entity, french: Bool, now: Date, calendar: Calendar) -> String {
        if entity.deviceClass == "timestamp" {
            return timestamp(entity.state, french: french, now: now, calendar: calendar) ?? words(entity.state, french: french)
        }
        guard let value = Double(entity.state), value.isFinite else { return words(entity.state, french: french) }
        if entity.deviceClass == "duration", let minutes = minutes(value, unit: entity.unit) {
            return minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
        }
        return withUnit(number(value, french: french), unit: entity.unit, french: french)
    }

    /// « 21,5 » or « 21.5 »: one decimal under a hundred when there is one.
    static func number(_ value: Double, french: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: french ? "fr_FR" : "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        let decimals = abs(value) < 100 && (value * 10).rounded() / 10 != value.rounded() ? 1 : 0
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func withUnit(_ number: String, unit: String?, french: Bool) -> String {
        guard let unit = unit?.trimmingCharacters(in: .whitespaces), !unit.isEmpty else { return number }
        if unit == "%" { return french ? "\(number) %" : "\(number)%" }
        return "\(number) \(unit)"
    }

    private static func minutes(_ value: Double, unit: String?) -> Int? {
        switch unit ?? "" {
        case "s": return Int((value / 60).rounded())
        case "min": return Int(value.rounded())
        case "h": return Int((value * 60).rounded())
        case "d": return Int((value * 1440).rounded())
        default: return nil
        }
    }

    /// « 14:32 » today, « mar. 14:32 » another day.
    static func timestamp(_ text: String, french: Bool, now: Date, calendar: Calendar) -> String? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        guard let date = parser.date(from: text) ?? fallback.date(from: text) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: french ? "fr_FR" : "en_US")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? (french ? "HH:mm" : "h:mm a")
            : (french ? "EEE HH:mm" : "EEE h:mm a")
        return formatter.string(from: date)
    }

    /// A word state as people read it: printers' and appliances' usual ones
    /// in French, the rest with a capital and spaces.
    static func words(_ state: String, french: Bool) -> String {
        if french {
            let known = ["idle": "Au repos", "printing": "Impression", "running": "En cours", "paused": "En pause",
                         "pause": "En pause", "finish": "Terminé", "finished": "Terminé", "failed": "Échec",
                         "offline": "Hors ligne", "online": "En ligne", "prepare": "Préparation", "error": "Erreur",
                         "on": "Activé", "off": "Désactivé", "home": "À la maison", "not_home": "Absent"]
            if let word = known[state.lowercased()] { return word }
        }
        let spaced = state.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func symbol(_ entity: Entity) -> String {
        let on = isOn(entity)
        switch entity.kind {
        case .cover:
            switch entity.deviceClass ?? "" {
            case "curtain": return on ? "curtains.open" : "curtains.closed"
            case "window": return on ? "window.vertical.open" : "window.vertical.closed"
            case "garage", "gate", "door": return on ? "door.garage.open" : "door.garage.closed"
            default: return on ? "blinds.horizontal.open" : "blinds.horizontal.closed"
            }
        case .light: return on ? "lightbulb.fill" : "lightbulb"
        case .toggle:
            if entity.domain == "fan" { return "fan.fill" }
            return entity.deviceClass == "outlet" ? "poweroutlet.type.f.fill" : "power"
        case .scene: return "sparkles"
        case .script: return "play.fill"
        case .button: return looksLikePrinter(entity) ? "printer.fill" : "button.programmable"
        case .binarySensor:
            switch entity.deviceClass ?? "" {
            case "door", "garage_door", "opening": return on ? "door.left.hand.open" : "door.left.hand.closed"
            case "window": return on ? "window.vertical.open" : "window.vertical.closed"
            case "motion", "occupancy", "presence": return "figure.walk"
            case "problem": return "exclamationmark.triangle.fill"
            default: return on ? "circle.fill" : "circle"
            }
        case .camera: return entity.domain == "image" ? "photo" : "video.fill"
        case .sensor:
            if looksLikePrinter(entity) { return "printer.fill" }
            switch entity.deviceClass ?? "" {
            case "temperature": return "thermometer.medium"
            case "humidity": return "humidity.fill"
            case "battery": return "battery.75percent"
            case "power", "energy", "current", "voltage": return "bolt.fill"
            case "illuminance": return "sun.max.fill"
            case "timestamp": return "clock.fill"
            case "duration": return "timer"
            default: return "gauge.medium"
            }
        }
    }

    private static func looksLikePrinter(_ entity: Entity) -> Bool {
        let text = (entity.id + " " + entity.name).lowercased()
        return ["print", "imprim", "bambu", "prusa", "octoprint"].contains { text.contains($0) }
    }

    // MARK: - Rooms

    /// Each entity's room (its own, or its device's) and the entities hidden
    /// or disabled in Home Assistant, from its three registries.
    struct Rooms: Equatable {
        var areaOfEntity: [String: String] = [:]
        var hidden: Set<String> = []
        /// A switch doubling its device's only shutter (a Fibaro module shows
        /// both, Z-Wave JS hiding the shutter), and that shutter: the shutter
        /// is driven instead, and offered though hidden by the integration.
        var coverOfSwitch: [String: String] = [:]
    }

    static func rooms(areas: Any?, devices: Any?, entities: Any?) -> Rooms {
        var names: [String: String] = [:]
        for area in areas as? [[String: Any]] ?? [] {
            if let id = area["area_id"] as? String, let name = area["name"] as? String { names[id] = name }
        }
        var deviceArea: [String: String] = [:]
        for device in devices as? [[String: Any]] ?? [] {
            if let id = device["id"] as? String, let area = device["area_id"] as? String { deviceArea[id] = area }
        }
        var rooms = Rooms()
        var covers: [String: [String]] = [:], switches: [String: [String]] = [:]
        for entry in entities as? [[String: Any]] ?? [] {
            guard let id = entry["entity_id"] as? String, isEntityID(id) else { continue }
            let hiddenBy = entry["hidden_by"] as? String, disabled = entry["disabled_by"] is String
            if hiddenBy != nil || disabled { rooms.hidden.insert(id) }
            let area = (entry["area_id"] as? String) ?? (entry["device_id"] as? String).flatMap { deviceArea[$0] }
            if let area, let name = names[area] { rooms.areaOfEntity[id] = name }
            // Settings (`entity_category`) are no doubles of the shutter.
            guard let device = entry["device_id"] as? String, !disabled, !(entry["entity_category"] is String) else { continue }
            switch domain(of: id) {
            case "cover" where hiddenBy == nil || hiddenBy == "integration": covers[device, default: []].append(id)
            case "switch" where hiddenBy == nil: switches[device, default: []].append(id)
            default: break
            }
        }
        for (device, ids) in switches {
            guard let shutters = covers[device], shutters.count == 1 else { continue }
            for id in ids { rooms.coverOfSwitch[id] = shutters[0] }
            rooms.hidden.remove(shutters[0])
        }
        return rooms
    }

    struct Group: Equatable, Identifiable {
        /// The room's name; nil when every favourite is in one room or none.
        let title: String?
        let entities: [Entity]
        var id: String { title ?? "" }
    }

    /// Favourites by room, rooms in the order their first favourite comes,
    /// those without a room last under `other`.
    static func groups(_ favorites: [Entity], areas: [String: String], other: String) -> [Group] {
        var order: [String] = []
        var members: [String: [Entity]] = [:]
        for entity in favorites {
            let area = areas[entity.id] ?? ""
            if members[area] == nil { order.append(area) }
            members[area, default: []].append(entity)
        }
        guard order.count > 1 else { return favorites.isEmpty ? [] : [Group(title: nil, entities: favorites)] }
        let sorted = order.filter { !$0.isEmpty } + (order.contains("") ? [""] : [])
        return sorted.map { Group(title: $0.isEmpty ? other : $0, entities: members[$0] ?? []) }
    }

    // MARK: - Favourites

    static let maximumFavorites = 48

    static func favorites(_ stored: String?) -> [String] {
        var ids: [String] = []
        for part in (stored ?? "").split(separator: ",") {
            let id = String(part)
            if isEntityID(id), !ids.contains(id), ids.count < maximumFavorites { ids.append(id) }
        }
        return ids
    }

    static func stored(_ ids: [String]) -> String { favorites(ids.joined(separator: ",")).joined(separator: ",") }

    /// Added at the end when absent (while there is room), removed when present.
    static func toggling(_ id: String, in ids: [String]) -> [String] {
        guard isEntityID(id) else { return ids }
        if ids.contains(id) { return ids.filter { $0 != id } }
        return ids.count < maximumFavorites ? ids + [id] : ids
    }

    /// A switch doubling a shutter gives way to the shutter, in its place and once.
    static func replacingSwitches(_ ids: [String], rooms: Rooms) -> [String] {
        var result: [String] = []
        for id in ids {
            let kept = rooms.coverOfSwitch[id] ?? id
            if !result.contains(kept) { result.append(kept) }
        }
        return result
    }

    /// The favourites the menu shows as tiles of their own.
    static func menuTiles(_ stored: String?, favorites: [String]) -> [String] {
        let wanted = Set(self.favorites(stored))
        return favorites.filter(wanted.contains)
    }

    // MARK: - Choosing devices

    /// The devices offered as favourites: supported, not hidden in Home
    /// Assistant nor doubling a shutter, by room then name.
    static func pickable(_ raws: [String: Raw], rooms: Rooms) -> [Entity] {
        raws.compactMap { id, raw in
            rooms.hidden.contains(id) || rooms.coverOfSwitch[id] != nil ? nil : entity(id: id, raw: raw)
        }
            .sorted { lhs, rhs in
                let left = rooms.areaOfEntity[lhs.id], right = rooms.areaOfEntity[rhs.id]
                if left != right {
                    guard let left else { return false }
                    guard let right else { return true }
                    return left.localizedStandardCompare(right) == .orderedAscending
                }
                let byName = lhs.name.localizedStandardCompare(rhs.name)
                return byName == .orderedSame ? lhs.id < rhs.id : byName == .orderedAscending
            }
    }

    /// Whether a device matches what is typed: its name, id or room, case and accents aside.
    static func matches(_ entity: Entity, area: String?, query: String) -> Bool {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = [entity.name, entity.id, area ?? ""].joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return words.allSatisfy { text.contains($0) }
    }

    // MARK: - The page

    static let tileHeight: CGFloat = 58
    static let tileSpacing: CGFloat = 8
    static let roomTitleHeight: CGFloat = 20
    static let roomSpacing: CGFloat = 12
    static let pagePadding: CGFloat = 8

    static func columns(width: CGFloat) -> Int { width >= 560 ? 4 : width >= 380 ? 3 : 2 }

    /// The page's height for its rooms (whether titled, how many tiles), so
    /// the island grows to show every favourite without scrolling.
    static func pageHeight(_ groups: [(titled: Bool, count: Int)], width: CGFloat) -> CGFloat {
        let columns = CGFloat(columns(width: width))
        let rooms = groups.filter { $0.count > 0 }
        guard !rooms.isEmpty else { return 0 }
        let heights = rooms.map { group -> CGFloat in
            let rows = (CGFloat(group.count) / columns).rounded(.up)
            return (group.titled ? roomTitleHeight : 0) + rows * tileHeight + (rows - 1) * tileSpacing
        }
        return heights.reduce(0, +) + roomSpacing * CGFloat(rooms.count - 1) + pagePadding
    }

    /// Where a tile that is no Home Assistant device (the 3D printer) goes:
    /// with the favourites when they have no rooms, in « Other » when there
    /// is one, otherwise in an « Other » of its own.
    enum ExtraPlacement: Equatable { case alone, inLast, newGroup }

    static func extraPlacement(_ groups: [(titled: Bool, count: Int)], lastIsOther: Bool) -> ExtraPlacement {
        guard let last = groups.last else { return .alone }
        if groups.count == 1 && !last.titled { return .inLast }
        return lastIsOther ? .inLast : .newGroup
    }

    static func adding(_ placement: ExtraPlacement, to groups: [(titled: Bool, count: Int)]) -> [(titled: Bool, count: Int)] {
        switch placement {
        case .alone: return [(titled: false, count: 1)]
        case .inLast: return groups.dropLast() + [(titled: groups.last?.titled ?? false, count: (groups.last?.count ?? 0) + 1)]
        case .newGroup: return groups + [(titled: true, count: 1)]
        }
    }

    /// The page's height while the printer shows: its back bar, then the printer.
    static let printerBar: CGFloat = 34

    /// Set by ForkHome once it runs, for upstream's island, which the tests
    /// compile without it: the page's height at a width, nil to fill the island.
    static var contentHeight: (_ width: CGFloat) -> CGFloat? = { _ in nil }

    static func title(french: Bool) -> String { french ? "Maison" : "Home" }

    /// What finds the page in Settings' search.
    static func searchTerms(french: Bool) -> [String] {
        [title(french: french), "Home Assistant", french ? "domotique" : "smart home", french ? "volets" : "covers",
         french ? "lumières" : "lights", french ? "jeton" : "token"]
    }

    static let pageSymbol = "house.fill"

    static func pageAvailable(in defaults: UserDefaults) -> Bool { defaults.bool(forKey: DefaultsKey.forkHomeEnabled) }

    static func islandControlAvailable(in defaults: UserDefaults) -> Bool { pageAvailable(in: defaults) }

    static func pageSummary(french: Bool) -> String {
        french ? "Vos appareils Home Assistant favoris par pièce : volets, lumières, prises, scènes, capteurs."
            : "Your favourite Home Assistant devices by room: covers, lights, plugs, scenes, sensors."
    }
}
