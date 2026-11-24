// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Closing the lid in the closed-lid mode puts the external displays to sleep too.
enum ForkLidDisplaySleepTests {
    static func run(_ suite: TestSuite) {
        typealias Logic = ForkLidDisplaySleepLogic

        suite.expect(Logic.isArmed(enabled: true, clamshellActive: true, featureAvailable: true)
            && !Logic.isArmed(enabled: false, clamshellActive: true, featureAvailable: true)
            && !Logic.isArmed(enabled: true, clamshellActive: false, featureAvailable: true)
            && !Logic.isArmed(enabled: true, clamshellActive: true, featureAvailable: false),
                     "the lid is watched only in the closed-lid mode, with the setting on")

        var watch = Logic.LidWatch()
        let first = watch.read(false)
        let closing = watch.read(true)
        let again = watch.read(true)
        let opening = watch.read(false)
        suite.expect(first == .none && closing == .closed && again == .none && opening == .opened,
                     "closing and opening are told apart, repeated readings are not changes")

        var alreadyShut = Logic.LidWatch()
        let shutAtStart = [alreadyShut.read(true), alreadyShut.read(true)]
        suite.expect(shutAtStart == [.none, .none],
                     "a lid already shut when the watch starts leaves the external display on")
        let thenReal = [alreadyShut.read(false), alreadyShut.read(true)]
        suite.expect(thenReal == [.opened, .closed], "and the next real closing counts")

        var noLid = Logic.LidWatch()
        let noLidReadings = [noLid.read(nil), noLid.read(nil)]
        suite.expect(noLidReadings == [.none, .none] && noLid.lastClosed == nil,
                     "a Mac without a lid never acts")
        var unreadable = Logic.LidWatch()
        _ = unreadable.read(false)
        let unreadableReadings = [unreadable.read(nil), unreadable.read(true)]
        suite.expect(unreadableReadings == [.none, .closed],
                     "an unreadable lid keeps the last state it saw")

        suite.expect(Logic.shouldSleep(scheduled: 4, current: 4, armed: true, lidClosed: true),
                     "after the delay, a lid still shut puts the displays to sleep")
        suite.expect(!Logic.shouldSleep(scheduled: 4, current: 5, armed: true, lidClosed: true)
            && !Logic.shouldSleep(scheduled: 4, current: 4, armed: true, lidClosed: false)
            && !Logic.shouldSleep(scheduled: 4, current: 4, armed: false, lidClosed: true)
            && !Logic.shouldSleep(scheduled: 4, current: 4, armed: true, lidClosed: nil),
                     "not once the lid opened again, the mode ended or the lid cannot be read")
        suite.expect(Logic.settleDelay >= 2 && Logic.settleDelay <= 5,
                     "a few seconds, the time macOS takes to move to the external display")
        suite.expect(Logic.pmsetPath == "/usr/bin/pmset" && Logic.pmsetArguments == ["displaysleepnow"],
                     "the displays sleep as with the hot corner, the Mac keeps running")

        suite.expect(Logic.holdsDisplaysAsleep(slept: true, lidClosed: true)
            && !Logic.holdsDisplaysAsleep(slept: true, lidClosed: false)
            && !Logic.holdsDisplaysAsleep(slept: false, lidClosed: true),
                     "the pointer nudge waits only while the displays sleep with the lid shut")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkLidSleepsDisplays] as? Bool == true,
                     "on by default")
    }
}
