// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The keys pressed during a recording, shown in the video. They are turned
/// into upstream's own captions when the editor first opens the recording, so
/// they are previewed, exported, moved, edited or deleted like any caption,
/// and undoing that first step takes them all away. Pure choices: the keys
/// come in as plain values.
enum ForkRecorderKeys {
    struct Press: Equatable {
        /// Seconds into the recording, pauses left out.
        let time: Double
        let label: String
        /// A key that types a character, as opposed to a shortcut or a key such as Return.
        let isTyping: Bool
    }

    struct Caption: Equatable {
        let text: String
        let start: Double
        let end: Double
    }

    /// How long a caption stays when nothing follows it.
    static let holdDuration: Double = 1.2
    /// Typing within this gap of the previous key joins the same caption.
    static let typingGap: Double = 0.8
    static let longestTypedText = 32
    static let captionSize: Double = 0.045

    /// What a key press reads as, or nil when it is not shown: with
    /// `allKeys` off only shortcuts are, keys held with Command or Control.
    static func label(keyCode: Int, characters: String?, command: Bool, option: Bool, control: Bool, shift: Bool,
                      allKeys: Bool, spaceName: String) -> (text: String, isTyping: Bool)? {
        let special = specialKeyName(keyCode: keyCode, spaceName: spaceName)
        let isShortcut = command || control
        guard isShortcut || allKeys else { return nil }
        var modifiers = ""
        if control { modifiers += "⌃" }
        if option { modifiers += "⌥" }
        if shift { modifiers += "⇧" }
        if command { modifiers += "⌘" }
        if let special { return (modifiers + special, false) }
        guard let characters, let first = characters.first, !first.isNewline, characters.count == 1 else { return nil }
        if isShortcut { return (modifiers + String(first).uppercased(), false) }
        // Typed text reads as typed, Shift and Option included in the character itself.
        return (String(first), true)
    }

    /// The names of keys that type no character.
    static func specialKeyName(keyCode: Int, spaceName: String) -> String? {
        switch keyCode {
        case 36, 76: return "↩"
        case 48: return "⇥"
        case 49: return spaceName
        case 51: return "⌫"
        case 117: return "⌦"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "↖"
        case 119: return "↘"
        case 116: return "⇞"
        case 121: return "⇟"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return nil
        }
    }

    /// The captions for a recording's presses: one per shortcut, typing
    /// joined into words. A caption ends when the next one starts, so they
    /// never stack, and none runs past the recording.
    static func captions(for presses: [Press], duration: Double) -> [Caption] {
        guard duration > 0 else { return [] }
        var groups: [(text: String, start: Double, last: Double, typing: Bool)] = []
        for press in presses.sorted(by: { $0.time < $1.time }) where press.time >= 0 && press.time < duration {
            if press.isTyping, let previous = groups.last, previous.typing,
               press.time - previous.last <= typingGap, previous.text.count < longestTypedText {
                groups[groups.count - 1].text += press.label
                groups[groups.count - 1].last = press.time
            } else {
                groups.append((press.label, press.time, press.time, press.isTyping))
            }
        }
        var captions: [Caption] = []
        for (index, group) in groups.enumerated() {
            var end = min(duration, group.last + holdDuration)
            if index + 1 < groups.count { end = min(end, groups[index + 1].start) }
            // Upstream drops a caption shorter than a fifth of a second: too brief to read anyway.
            guard end - group.start >= 0.2 else { continue }
            let text = group.text.trimmingCharacters(in: .whitespaces).isEmpty ? group.text : group.text
            captions.append(Caption(text: text, start: group.start, end: end))
        }
        return captions
    }

    /// Whether a recording's video belongs to the keys captured between
    /// `start` and `end`: its file appeared while they were being captured.
    static func belongs(videoCreated: Date, start: Date, end: Date) -> Bool {
        videoCreated >= start.addingTimeInterval(-10) && videoCreated <= end.addingTimeInterval(10)
    }
}
