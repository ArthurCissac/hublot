// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// What a clipboard card says about its content, under its preview: a
/// text's length, a link's site, a colour's value, a picture's size, a
/// number of files. And the colour a card's band takes from its app's icon.
/// Pure choices.
enum ForkClipboardCardInfo {
    enum Detail: Equatable {
        case text(characters: Int)
        case link(domain: String)
        case color(red: Double, green: Double, blue: Double)
        case image(width: Int, height: Int)
        case files(count: Int)
    }

    /// The detail for a text: a link when the whole text is one web address,
    /// a colour when the whole text is one colour, otherwise its length in
    /// characters as a reader counts them.
    static func detail(forText text: String) -> Detail {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let domain = linkDomain(trimmed) { return .link(domain: domain) }
        if let color = ColorValue(text: trimmed) { return .color(red: color.red, green: color.green, blue: color.blue) }
        return .text(characters: text.count)
    }

    /// The site of a text that is a single web address, without "www.";
    /// nil for anything else, a sentence that contains one included.
    static func linkDomain(_ text: String) -> String? {
        guard !text.isEmpty, !text.contains(where: \.isWhitespace),
              let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// The average colour of an icon's visible pixels, from RGBA bytes,
    /// ignoring what is transparent; nil when nothing shows.
    static func averageColor(rgba: [UInt8]) -> (red: Double, green: Double, blue: Double)? {
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        var index = 0
        while index + 3 < rgba.count {
            let alpha = Double(rgba[index + 3]) / 255
            if alpha > 0.1 {
                // Premultiplied bytes: dividing by alpha gives the colour back.
                red += Double(rgba[index]) / 255
                green += Double(rgba[index + 1]) / 255
                blue += Double(rgba[index + 2]) / 255
                weight += alpha
            }
            index += 4
        }
        guard weight > 0 else { return nil }
        return (min(1, red / weight), min(1, green / weight), min(1, blue / weight))
    }

    /// The band's colour: upstream's way of taking a lively colour from a
    /// picture, which gives nothing for an icon without a colour of its own.
    static func bandColor(rgba: [UInt8]) -> NotchArtworkTint? {
        guard let average = averageColor(rgba: rgba) else { return nil }
        return NotchArtworkTint.from(red: average.red, green: average.green, blue: average.blue)
    }
}
