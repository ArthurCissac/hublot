// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// What a clipboard card says about its content.
enum ForkClipboardCardTests {
    typealias Info = ForkClipboardCardInfo

    static func run(_ suite: TestSuite) {
        suite.expect(Info.detail(forText: "https://www.apple.com/fr/mac/") == .link(domain: "apple.com")
            && Info.detail(forText: "  http://docs.example.org:8080/a?b=c \n") == .link(domain: "docs.example.org"),
               "a web address reads as its site, without www and without its port")
        suite.expect(Info.detail(forText: "voir https://apple.com demain") == .text(characters: 29)
            && Info.linkDomain("ftp://files.example.com") == nil && Info.linkDomain("apple.com") == nil,
               "a sentence that contains an address, or an address that is not a web one, stays text")
        suite.expect(Info.detail(forText: "#FF8000") == .color(red: 1, green: 128.0 / 255, blue: 0),
               "a colour value reads as its colour")
        suite.expect(Info.detail(forText: "café 👍🏽") == .text(characters: 6),
               "characters are counted as a reader counts them, an emoji with its skin tone as one")

        // Icon colours: premultiplied RGBA bytes.
        let orange: [UInt8] = [240, 120, 20, 255, 230, 110, 10, 255, 0, 0, 0, 0]
        let average = Info.averageColor(rgba: orange)
        suite.expect(average.map { abs($0.red - 235.0 / 255) < 0.01 && abs($0.blue - 15.0 / 255) < 0.01 } == true,
               "the icon's colour is the average of its visible pixels, transparent ones ignored")
        suite.expect(Info.averageColor(rgba: [0, 0, 0, 0, 0, 0, 0, 0]) == nil, "an empty icon has no colour")
        suite.expect(Info.bandColor(rgba: orange) != nil, "a coloured icon tints its card's band")
        suite.expect(Info.bandColor(rgba: [128, 128, 128, 255, 120, 120, 120, 255]) == nil,
               "a grey icon leaves the band neutral")
    }
}
