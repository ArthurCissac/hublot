// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

enum ForkTileLayoutTests {
    typealias Logic = ForkTileLayoutLogic

    static func run(_ suite: TestSuite) {
        suite.expect(Logic.parse(" fork.tasks, panel.darkMode,,fork.tasks ,") == ["fork.tasks", "panel.darkMode"]
            && Logic.parse(nil).isEmpty && Logic.parse("").isEmpty,
                     "the stored order is read once per name, blanks dropped")
        suite.expect(Logic.encode(["fork.tasks", "panel.darkMode"]) == "fork.tasks,panel.darkMode"
            && Logic.parse(Logic.encode(["a", "b", "c"])) == ["a", "b", "c"],
                     "the order is written back as it reads")
        suite.expect(Logic.forkKey("tasks") == "fork.tasks" && Logic.panelKey("darkMode") == "panel.darkMode",
                     "the fork's and upstream's tiles are named apart")

        let known = ["fork.a", "fork.b", "fork.new", "panel.x", "panel.y"]
        suite.expect(Logic.ordered(stored: [], known: known) == known,
                     "with nothing stored, the tiles keep their default order")
        suite.expect(Logic.ordered(stored: ["panel.y", "fork.b", "gone", "fork.a", "panel.x"], known: known)
            == ["panel.y", "fork.b", "fork.new", "fork.a", "panel.x"],
                     "a new tile lands right after its neighbour; a forgotten one is dropped")
        suite.expect(Logic.ordered(stored: ["panel.y"], known: ["fork.a", "panel.y"]) == ["fork.a", "panel.y"],
                     "a new tile with nothing before it goes first")
        let mixed = Logic.ordered(stored: ["panel.x", "fork.a"], known: known)
        suite.expect(Set(mixed) == Set(known) && mixed.count == known.count,
                     "every known tile appears once")

        let order = ["a", "b", "c", "d"]
        suite.expect(Logic.move("a", onto: "c", in: order) == ["b", "c", "a", "d"]
            && Logic.move("d", onto: "b", in: order) == ["a", "d", "b", "c"],
                     "a dragged tile takes the target's place, the others shift")
        suite.expect(Logic.move("a", onto: "a", in: order) == order && Logic.move("z", onto: "a", in: order) == order
            && Logic.move("a", onto: "z", in: order) == order,
                     "a drag onto itself or an unknown tile changes nothing")
        suite.expect(Logic.moveToEnd("b", in: order) == ["a", "c", "d", "b"] && Logic.moveToEnd("z", in: order) == order,
                     "a tile can go to the very end")

        let split = Logic.split(["a", "b", "c", "d"]) { $0 == "b" || $0 == "d" }
        suite.expect(split.shown == ["a", "c"] && split.hidden == ["b", "d"],
                     "shown and hidden tiles each keep the order's sequence")

        suite.expect(Logic.jiggleAngle > 0 && Logic.jiggleAngle < 3 && Logic.jiggleDuration > 0.05 && Logic.jiggleDuration < 0.3,
                     "the swing is slight and quick")
        suite.expect(Logic.jiggleDelay(index: 0) == 0 && Logic.jiggleDelay(index: 1) != Logic.jiggleDelay(index: 2)
            && Logic.jiggleDelay(index: 5) == 0,
                     "neighbouring tiles swing a little apart")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkTileOrder] as? String == "",
                     "no hand-made order until the user arranges the tiles")
    }
}
