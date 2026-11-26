// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The Home page: addresses accepted or refused, the messages sent to Home
/// Assistant and read back, its states and their changes, what a click may
/// ask (never a lock), the words shown, rooms and favourites.
enum ForkHomeTests {
    typealias Logic = ForkHomeLogic

    private static func url(_ raw: String) -> String? {
        if case .success(let url) = Logic.address(raw) { return url.absoluteString }
        return nil
    }

    private static func problem(_ raw: String) -> Logic.AddressProblem? {
        if case .failure(let problem) = Logic.address(raw) { return problem }
        return nil
    }

    private static let states = """
    [{"entity_id": "cover.volet_salon", "state": "open", "attributes": {"friendly_name": "Volet salon", "current_position": 60, "supported_features": 15, "device_class": "shutter"}},
     {"entity_id": "light.plafond", "state": "on", "attributes": {"friendly_name": "Plafond", "brightness": 178, "supported_color_modes": ["brightness"]}},
     {"entity_id": "switch.prise", "state": "off", "attributes": {"friendly_name": "Prise bureau", "device_class": "outlet"}},
     {"entity_id": "lock.porte", "state": "locked", "attributes": {"friendly_name": "Porte d’entrée"}},
     {"entity_id": "cover.garage", "state": "closed", "attributes": {"friendly_name": "Garage", "device_class": "garage", "supported_features": 15}},
     {"entity_id": "sensor.imprimante_progression", "state": "42", "attributes": {"friendly_name": "Imprimante progression", "unit_of_measurement": "%"}},
     {"entity_id": "sensor.salon_temperature", "state": "21.46", "attributes": {"friendly_name": "Température salon", "unit_of_measurement": "°C", "device_class": "temperature"}},
     {"entity_id": "Bad.ID", "state": "on", "attributes": {}}]
    """

    private static var raws: [String: Logic.Raw] {
        Logic.raws(fromStates: try? JSONSerialization.jsonObject(with: Data(states.utf8)))
    }

    private static func entity(_ id: String) -> Logic.Entity? {
        raws[id].flatMap { Logic.entity(id: id, raw: $0) }
    }

    static func run(_ suite: TestSuite) {
        addresses(suite)
        messages(suite)
        statesAndChanges(suite)
        commands(suite)
        words(suite)
        roomsAndFavorites(suite)
    }

    private static func addresses(_ suite: TestSuite) {
        suite.expect(url("http://homeassistant.local:8123/") == "http://homeassistant.local:8123"
            && url("homeassistant.local:8123") == "http://homeassistant.local:8123"
            && url("192.168.1.20:8123") == "http://192.168.1.20:8123"
            && url("ha.example.com") == "https://ha.example.com"
            && url("https://abc.ui.nabu.casa") == "https://abc.ui.nabu.casa",
                     "an address is kept bare, a bare host gets http at home and https elsewhere")
        suite.expect(problem("http://ha.example.com") == .insecure && problem("http://8.8.8.8:8123") == .insecure,
                     "plain http off the local network is refused")
        suite.expect(problem("") == .invalid && problem("ftp://homeassistant.local") == .invalid
            && problem("http://user:pass@homeassistant.local") == .invalid
            && problem("http://homeassistant.local:8123/lovelace") == .invalid
            && problem("http://homeassistant.local/?token=x") == .invalid && problem("home assistant") == .invalid,
                     "other schemes, credentials, paths, queries and spaces are refused")
        suite.expect(Logic.isLocal(host: "homeassistant") && Logic.isLocal(host: "10.0.0.4") && Logic.isLocal(host: "172.20.1.1")
            && Logic.isLocal(host: "[fe80::1]") && Logic.isLocal(host: "fd12::5") && !Logic.isLocal(host: "172.32.0.1")
            && !Logic.isLocal(host: "example.com") && !Logic.isLocal(host: "8.8.8.8"),
                     "local hosts: single labels, .local, private and link-local addresses")
        let base = URL(string: "https://abc.ui.nabu.casa")!
        suite.expect(Logic.webSocketURL(URL(string: "http://homeassistant.local:8123")!)?.absoluteString
                        == "ws://homeassistant.local:8123/api/websocket"
            && Logic.webSocketURL(base)?.absoluteString == "wss://abc.ui.nabu.casa/api/websocket"
            && Logic.tokensPage(base)?.absoluteString == "https://abc.ui.nabu.casa/profile/security",
                     "the WebSocket endpoint and the tokens page sit under the address")
        suite.expect(Logic.candidates(main: "homeassistant.local:8123", fallback: "https://abc.ui.nabu.casa").map(\.absoluteString)
                        == ["http://homeassistant.local:8123", "https://abc.ui.nabu.casa"]
            && Logic.candidates(main: "", fallback: "http://bad.example.com").isEmpty,
                     "the main address first, then the fallback, invalid ones left out")
        suite.expect(Logic.cleanToken("  eyJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJhIn0.sig-_x  \n") == "eyJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJhIn0.sig-_x"
            && Logic.cleanToken("short") == nil && Logic.cleanToken("eyJhbGciOiJIUzI1NiJ9 with spaces inside") == nil,
                     "a pasted token is trimmed, and refused when it cannot be one")
        suite.expect(Logic.retryDelay(attempt: 0) == 2 && Logic.retryDelay(attempt: 2) == 8 && Logic.retryDelay(attempt: 20) == 60,
                     "retries wait longer each time, a minute at most")
    }

    private static func messages(_ suite: TestSuite) {
        suite.expect(Logic.authMessage(token: "abc") == #"{"access_token":"abc","type":"auth"}"#,
                     "the auth message carries the token")
        suite.expect(Logic.subscribeEntities(id: 3, entityIDs: ["cover.volet_salon", "Bad.ID"])
                        == #"{"entity_ids":["cover.volet_salon"],"id":3,"type":"subscribe_entities"}"#,
                     "only valid entity ids are subscribed to")
        let call = Logic.ServiceCall(domain: "cover", service: "set_cover_position", entityID: "cover.volet_salon", data: ["position": 40])
        suite.expect(Logic.callService(id: 7, call)
                        == #"{"domain":"cover","id":7,"service":"set_cover_position","service_data":{"position":40},"target":{"entity_id":"cover.volet_salon"},"type":"call_service"}"#,
                     "a service call names its target and its data")
        suite.expect(Logic.callService(id: 8, Logic.ServiceCall(domain: "lock", service: "unlock", entityID: "lock.porte")) == nil
            && Logic.callService(id: 9, Logic.ServiceCall(domain: "cover", service: "open_cover", entityID: "light.plafond")) == nil
            && Logic.callService(id: 10, Logic.ServiceCall(domain: "light", service: "turn_on", entityID: "light.plafond",
                                                            data: ["brightness_pct": 400])) == nil,
                     "a service outside the allow list, a mismatched target or an odd value is never sent")
        let incoming = Logic.incoming(#"{"type":"auth_ok","ha_version":"2026.11.0"}"#)
        if case .authOK? = incoming.first {} else { suite.expect(false, "auth_ok is read") }
        let grouped = Logic.incoming(#"[{"id":4,"type":"result","success":true,"result":null},{"id":5,"type":"pong"}]"#)
        if grouped.count == 2, case .result(4, true, _) = grouped[0], case .pong(5) = grouped[1] {
            suite.expect(true, "grouped messages are read one by one")
        } else {
            suite.expect(false, "grouped messages are read one by one")
        }
        if case .authInvalid? = Logic.incoming(#"{"type":"auth_invalid","message":"Invalid access token"}"#).first {
            suite.expect(true, "a refused token is read")
        } else {
            suite.expect(false, "a refused token is read")
        }
        suite.expect(Logic.incoming("not json").isEmpty, "a broken message is ignored")
    }

    private static func statesAndChanges(_ suite: TestSuite) {
        suite.expect(raws.count == 7 && raws["Bad.ID"] == nil, "states are read, invalid ids left out")
        let cover = entity("cover.volet_salon")
        suite.expect(cover?.name == "Volet salon" && cover?.position == 60 && cover?.canSetLevel == true && cover?.kind == .cover,
                     "a cover reads its name, its position and whether it can be set")
        let light = entity("light.plafond")
        suite.expect(light?.brightness == 70 && light?.canSetLevel == true, "a light reads its brightness in percent")
        suite.expect(entity("lock.porte") == nil, "a lock is not a device the page shows")
        suite.expect(entity("cover.garage")?.needsConfirmation == true && entity("cover.garage")?.canSetLevel == false,
                     "a garage door waits for a second click and has no position to set")
        suite.expect(Logic.fallbackName("switch.prise_du_bureau") == "Prise du bureau", "a nameless device is named after its id")

        let first: [String: Any] = ["a": ["cover.volet_salon": ["s": "closed", "a": ["friendly_name": "Volet", "current_position": 0]],
                                          "light.plafond": ["s": "off", "a": ["friendly_name": "Plafond"]]]]
        var live = Logic.applying(first, to: [:])
        live = Logic.applying(["c": ["cover.volet_salon": ["+": ["s": "opening", "a": ["current_position": 30]]],
                                     "light.plafond": ["+": ["s": "on"], "-": ["a": ["friendly_name"]]]]], to: live)
        suite.expect(live["cover.volet_salon"]?.state == "opening"
            && live["cover.volet_salon"]?.attributes["current_position"] as? Int == 30
            && live["cover.volet_salon"]?.attributes["friendly_name"] as? String == "Volet"
            && live["light.plafond"]?.state == "on" && live["light.plafond"]?.attributes["friendly_name"] == nil,
                     "changes set states and attributes, and remove the attributes listed")
        live = Logic.applying(["r": ["light.plafond"]], to: live)
        suite.expect(live.keys.sorted() == ["cover.volet_salon"], "a removed entity goes")
    }

    private static func commands(_ suite: TestSuite) {
        guard let cover = entity("cover.volet_salon"), let light = entity("light.plafond"), let plug = entity("switch.prise"),
              let garage = entity("cover.garage"), let printer = entity("sensor.imprimante_progression") else {
            return suite.expect(false, "the sample states read")
        }
        suite.expect(Logic.call(.main, for: cover)?.service == "close_cover", "an open cover closes on a click")
        let closed = Logic.Entity(id: "cover.volet_salon", kind: .cover, name: "Volet", state: "closed", position: 0)
        let moving = Logic.Entity(id: "cover.volet_salon", kind: .cover, name: "Volet", state: "opening")
        suite.expect(Logic.call(.main, for: closed)?.service == "open_cover" && Logic.call(.main, for: moving)?.service == "stop_cover",
                     "a closed cover opens, a moving one stops")
        suite.expect(Logic.call(.level(42), for: cover) == Logic.ServiceCall(domain: "cover", service: "set_cover_position",
                                                                             entityID: "cover.volet_salon", data: ["position": 42]),
                     "a drag sets a cover's position")
        suite.expect(Logic.call(.level(0), for: light)?.service == "turn_off"
            && Logic.call(.level(55), for: light)?.data == ["brightness_pct": 55]
            && Logic.call(.main, for: light)?.service == "toggle" && Logic.call(.main, for: plug)?.service == "toggle",
                     "a light dims or turns off, a click toggles lights and plugs")
        suite.expect(Logic.call(.main, for: garage) == nil && Logic.call(.open, for: garage) == nil
            && Logic.call(.main, for: garage, confirmed: true)?.service == "open_cover"
            && Logic.call(.level(50), for: garage, confirmed: true) == nil
            && Logic.actionable(garage) && !Logic.actionable(printer),
                     "a garage door moves only once confirmed, a sensor has no action")
        suite.expect(Logic.coverButtons(cover) == [.open, .stop, .close] && Logic.coverButtons(plug).isEmpty,
                     "a cover has up, stop and down buttons")
        let openClose = Logic.Entity(id: "cover.portail", kind: .cover, name: "Portail", state: "closed", deviceClass: "gate", features: 3)
        suite.expect(Logic.coverButtons(openClose) == [.open, .close]
            && Logic.call(.stop, for: openClose, confirmed: true) == nil
            && Logic.confirmText(.main, for: openClose, french: true) == "Recliquez pour ouvrir",
                     "a gate without stop has no stop button, and says what a second click does")
        let camera = Logic.Entity(id: "camera.imprimante_3d", kind: .camera, name: "Imprimante 3D", state: "idle")
        let chamber = Logic.Entity(id: "image.p1s_chambre", kind: .camera, name: "Chambre", state: "2026-11-24T12:00:00+00:00")
        let base = URL(string: "http://homeassistant.local:8123")!
        suite.expect(Logic.kind(domain: "camera") == .camera && Logic.kind(domain: "image") == .camera
            && Logic.pictureURL(base: base, entity: camera)?.absoluteString == "http://homeassistant.local:8123/api/camera_proxy/camera.imprimante_3d"
            && Logic.pictureURL(base: base, entity: chamber)?.absoluteString == "http://homeassistant.local:8123/api/image_proxy/image.p1s_chambre"
            && Logic.pictureURL(base: base, entity: cover) == nil,
                     "a camera's picture is asked from its proxy, without the token in the address")
        suite.expect(Logic.call(.main, for: camera, confirmed: true) == nil && !Logic.isOn(camera)
            && Logic.stateText(camera, french: true) == "Voir" && Logic.symbol(camera) == "video.fill"
            && Logic.kindLabel(camera, french: true) == "Caméra" && Logic.kindLabel(chamber, french: true) == "Image",
                     "a camera is shown, never commanded")
        suite.expect(Logic.viewerHeight(width: 492) == 270 + 34 + 8 && Logic.viewerHeight(width: 2000) == 400 + 34 + 8,
                     "an open camera makes the page 16:9 tall, within bounds")
        let start = Date(timeIntervalSince1970: 1_000)
        suite.expect(Logic.coverDirection(closed, last: nil, now: start) == .up
            && Logic.coverDirection(cover, last: nil, now: start) == .down
            && Logic.coverText(closed, last: nil, now: start, french: true) == "Fermé · Monter",
                     "a closed shutter offers to go up, an open one to go down")
        let raised = Logic.CoverRun(direction: .up, at: start)
        suite.expect(Logic.coverDirection(closed, last: raised, now: start.addingTimeInterval(1)) == .down
            && Logic.coverText(closed, last: raised, now: start.addingTimeInterval(1), french: true) == "Montée…"
            && Logic.coverDirection(closed, last: raised, now: start.addingTimeInterval(Logic.coverSettle + 1)) == .up,
                     "just after « up », the button offers « down » before Home Assistant answers")
        let halfway = Logic.Entity(id: "cover.volet_salon", kind: .cover, name: "Volet", state: "open", position: 40)
        let lowered = Logic.CoverRun(direction: .down, at: .distantPast)
        suite.expect(Logic.coverDirection(halfway, last: raised, now: start.addingTimeInterval(60)) == .down
            && Logic.coverDirection(halfway, last: lowered, now: start) == .up
            && Logic.coverDirection(halfway, last: nil, now: start) == .up
            && Logic.coverText(halfway, last: lowered, now: start, french: true) == "40 % · Monter",
                     "stopped part way, it offers the other way from its last run, or by position")
        let closing = Logic.Entity(id: "cover.volet_salon", kind: .cover, name: "Volet", state: "closing", position: 60)
        suite.expect(Logic.coverDirection(moving, last: nil, now: start) == .down && Logic.coverDirection(closing, last: nil, now: start) == .up,
                     "while it moves, the button offers the other way")
        let upOnly = Logic.Entity(id: "cover.store", kind: .cover, name: "Store", state: "open", position: 100, features: 1)
        suite.expect(Logic.coverDirection(upOnly, last: nil, now: start) == .up
            && Logic.command(for: .up) == .open && Logic.command(for: .down) == .close
            && Logic.commandSymbol(Logic.command(for: .down)) == "chevron.down",
                     "the arrow says what the click asks, and a cover that only rises offers to rise")
        suite.expect(Logic.movement(from: closed, to: halfway) == .up && Logic.movement(from: cover, to: halfway) == .down
            && Logic.movement(from: halfway, to: closing) == .down && Logic.movement(from: halfway, to: halfway) == nil,
                     "a run seen in Home Assistant (a press on the wall) is followed")
        let stopped = Logic.stopped(raised)
        suite.expect(stopped == Logic.CoverRun(direction: .up, at: .distantPast, stopped: true) && Logic.stopped(nil) == nil
            && Logic.coverDirection(halfway, last: stopped, now: start.addingTimeInterval(1)) == .down
            && Logic.coverDirection(closed, last: stopped, now: start.addingTimeInterval(1)) == .down
            && Logic.coverText(halfway, last: stopped, now: start.addingTimeInterval(1), french: true) == "40 % · Descendre",
                     "stopped going up, it offers to go down, even before Home Assistant reports where it stands")
        suite.expect(Logic.follows(lastAction: start, now: start.addingTimeInterval(Logic.coverQuiet - 1)) == false
            && Logic.follows(lastAction: start, now: start.addingTimeInterval(Logic.coverQuiet + 1))
            && Logic.follows(lastAction: nil, now: start),
                     "what Home Assistant reports right after a click or a stop is its echo, not a run of its own")
        suite.expect(Logic.kindLabel(cover, french: true) == "Volet" && Logic.kindLabel(plug, french: true) == "Prise"
            && Logic.kindLabel(openClose, french: true) == "Portail"
            && Logic.kindLabel(Logic.Entity(id: "switch.volet", kind: .toggle, name: "Volet", state: "off"), french: true) == "Interrupteur",
                     "the list says what kind each device is")
        let gone = Logic.Entity(id: "light.plafond", kind: .light, name: "Plafond", state: "unavailable")
        suite.expect(Logic.call(.main, for: gone) == nil, "an unavailable device is not asked anything")
        suite.expect(Logic.call(.main, for: Logic.Entity(id: "scene.soir", kind: .scene, name: "Soir", state: "unknown"))?.service == "turn_on"
            && Logic.call(.main, for: Logic.Entity(id: "button.pause", kind: .button, name: "Pause", state: "unknown"))?.service == "press",
                     "a scene turns on, a button is pressed")
        suite.expect(Logic.level(at: 0, width: 100) == 0 && Logic.level(at: 33, width: 100) == 35 && Logic.level(at: 140, width: 100) == 100,
                     "a drag's level goes by fives, within bounds")
        suite.expect(Logic.isOn(cover) && Logic.isOn(light) && !Logic.isOn(plug) && Logic.level(light) == 70 && Logic.level(plug) == nil,
                     "lit tiles and their levels")
    }

    private static func words(_ suite: TestSuite) {
        guard let cover = entity("cover.volet_salon"), let light = entity("light.plafond"),
              let printer = entity("sensor.imprimante_progression"), let temperature = entity("sensor.salon_temperature") else {
            return suite.expect(false, "the sample states read")
        }
        suite.expect(Logic.stateText(cover, french: true) == "Ouvert à 60 %" && Logic.stateText(cover, french: false) == "Open 60%",
                     "a cover says how open it is")
        suite.expect(Logic.stateText(light, french: true) == "Allumé · 70 %", "a light says its brightness")
        suite.expect(Logic.stateText(printer, french: true) == "42 %" && Logic.stateText(printer, french: false) == "42%"
            && Logic.stateText(temperature, french: true) == "21,5 °C" && Logic.stateText(temperature, french: false) == "21.5 °C",
                     "sensors show their value and unit")
        let duration = Logic.Entity(id: "sensor.reste", kind: .sensor, name: "Reste", state: "70", deviceClass: "duration", unit: "min")
        let status = Logic.Entity(id: "sensor.etat", kind: .sensor, name: "État", state: "printing")
        suite.expect(Logic.stateText(duration, french: true) == "1 h 10" && Logic.stateText(status, french: true) == "Impression"
            && Logic.stateText(status, french: false) == "Printing",
                     "durations read in hours, printers' states in words")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = ISO8601DateFormatter().date(from: "2026-11-24T10:00:00Z")!
        let end = Logic.Entity(id: "sensor.fin", kind: .sensor, name: "Fin", state: "2026-11-24T13:32:00+00:00", deviceClass: "timestamp")
        suite.expect(Logic.stateText(end, french: true, now: now, calendar: calendar) == "14:32", "a time today shows as hours")
        let door = Logic.Entity(id: "binary_sensor.porte", kind: .binarySensor, name: "Porte", state: "on", deviceClass: "door")
        suite.expect(Logic.stateText(door, french: true) == "Ouvert"
            && Logic.stateText(Logic.Entity(id: "light.x", kind: .light, name: "X", state: "unavailable"), french: true) == "Indisponible",
                     "doors open or closed, unavailable devices say so")
        suite.expect(Logic.symbol(cover) == "blinds.horizontal.open" && Logic.symbol(printer) == "printer.fill"
            && Logic.symbol(temperature) == "thermometer.medium",
                     "each device has its symbol")
    }

    private static func roomsAndFavorites(_ suite: TestSuite) {
        let areas: [[String: Any]] = [["area_id": "salon", "name": "Salon"], ["area_id": "bureau", "name": "Bureau"]]
        let devices: [[String: Any]] = [["id": "d1", "area_id": "bureau"]]
        let entries: [[String: Any]] = [["entity_id": "cover.volet_salon", "area_id": "salon"],
                                        ["entity_id": "switch.prise", "device_id": "d1", "area_id": NSNull()],
                                        ["entity_id": "sensor.salon_temperature", "hidden_by": "user"],
                                        ["entity_id": "cover.volet_chambre", "device_id": "fibaro", "hidden_by": "integration"],
                                        ["entity_id": "switch.volet_chambre", "device_id": "fibaro"],
                                        ["entity_id": "switch.volet_chambre_calibrage", "device_id": "fibaro", "entity_category": "config"],
                                        ["entity_id": "cover.a", "device_id": "two"], ["entity_id": "cover.b", "device_id": "two"],
                                        ["entity_id": "switch.two", "device_id": "two"],
                                        ["entity_id": "cover.cache", "device_id": "mine", "hidden_by": "user"],
                                        ["entity_id": "switch.cache", "device_id": "mine"]]
        let rooms = Logic.rooms(areas: areas, devices: devices, entities: entries)
        suite.expect(rooms.areaOfEntity == ["cover.volet_salon": "Salon", "switch.prise": "Bureau"]
            && rooms.hidden == ["sensor.salon_temperature", "cover.cache"],
                     "an entity's room is its own or its device's; hidden ones are noted")
        suite.expect(rooms.coverOfSwitch == ["switch.volet_chambre": "cover.volet_chambre"],
                     "a switch doubling its device's only shutter is known (the shutter hidden by the integration, not by hand), settings and two-shutter devices aside")
        suite.expect(Logic.replacingSwitches(["light.a", "switch.volet_chambre", "switch.prise"], rooms: rooms)
                        == ["light.a", "cover.volet_chambre", "switch.prise"]
            && Logic.replacingSwitches(["cover.volet_chambre", "switch.volet_chambre"], rooms: rooms) == ["cover.volet_chambre"],
                     "a favourite switch gives way to its shutter, in its place and once")
        let doubled: [String: Logic.Raw] = ["switch.volet_chambre": Logic.Raw(state: "off", attributes: [:]),
                                            "cover.volet_chambre": Logic.Raw(state: "closed", attributes: [:])]
        suite.expect(Logic.pickable(doubled, rooms: rooms).map(\.id) == ["cover.volet_chambre"],
                     "the list offers the shutter, not the switch doubling it")
        let picked = Logic.pickable(raws, rooms: rooms)
        suite.expect(picked.map(\.id) == ["switch.prise", "cover.volet_salon", "cover.garage", "sensor.imprimante_progression", "light.plafond"],
                     "devices to choose from: by room then name, without locks nor hidden ones")
        suite.expect(Logic.matches(picked[0], area: "Bureau", query: "PRISE bur") && Logic.matches(picked[1], area: "Salon", query: "volét")
            && !Logic.matches(picked[1], area: "Salon", query: "garage"),
                     "the search ignores case and accents")
        let favorites = [entity("cover.volet_salon"), entity("switch.prise"), entity("light.plafond")].compactMap { $0 }
        let groups = Logic.groups(favorites, areas: rooms.areaOfEntity, other: "Autres")
        suite.expect(groups.map(\.title) == ["Salon", "Bureau", "Autres"] && groups.map(\.entities.count) == [1, 1, 1],
                     "favourites go by room, those without one last")
        suite.expect(Logic.groups(Array(favorites.prefix(1)), areas: rooms.areaOfEntity, other: "Autres").map(\.title) == [nil],
                     "a single room needs no title")
        let ids = Logic.favorites("cover.a,Bad.ID,cover.a,light.b")
        suite.expect(ids == ["cover.a", "light.b"] && Logic.stored(Logic.toggling("switch.c", in: ids)) == "cover.a,light.b,switch.c"
            && Logic.toggling("cover.a", in: ids) == ["light.b"] && Logic.menuTiles("light.b,switch.z", favorites: ids) == ["light.b"],
                     "favourites are kept valid and once each; menu tiles are favourites")
        suite.expect(Logic.columns(width: 300) == 2 && Logic.columns(width: 420) == 3 && Logic.columns(width: 600) == 4,
                     "two to four columns as the island widens")
        let oneRow: CGFloat = 58 + 8
        let twoRooms: CGFloat = (20 + 58 * 2 + 8) + 12 + (20 + 58) + 8
        let single = Logic.pageHeight([(titled: false, count: 3)], width: 420)
        let twoTall = Logic.pageHeight([(titled: true, count: 4), (titled: true, count: 1)], width: 420)
        suite.expect(single == oneRow && twoTall == twoRooms && Logic.pageHeight([], width: 420) == 0,
                     "the page is as tall as its rooms' rows")
        suite.expect(Logic.searchTerms(french: true).contains("Maison") && Logic.searchTerms(french: false).contains("Home Assistant"),
                     "Settings' search finds the Home page")
        let rooms2: [(titled: Bool, count: Int)] = [(titled: true, count: 2), (titled: true, count: 1)]
        suite.expect(Logic.extraPlacement([], lastIsOther: false) == .alone
            && Logic.extraPlacement([(titled: false, count: 3)], lastIsOther: false) == .inLast
            && Logic.extraPlacement(rooms2, lastIsOther: true) == .inLast
            && Logic.extraPlacement(rooms2, lastIsOther: false) == .newGroup
            && Logic.adding(.inLast, to: rooms2).map(\.count) == [2, 2]
            && Logic.adding(.newGroup, to: rooms2).map(\.count) == [2, 1, 1],
                     "the printer's tile joins « Other », or makes one")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkHomeShowsPrinter] as? Bool == true
            && Defaults.registeredDefaults[DefaultsKey.forkHomeEnabled] as? Bool == false
            && Defaults.registeredDefaults[DefaultsKey.forkHomeFavorites] as? String == "",
                     "the Home page starts off, without favourites")
    }
}
