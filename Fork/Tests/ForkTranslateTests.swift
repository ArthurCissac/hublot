// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// Translation of the selected text (ForkTranslateLogic).
enum ForkTranslateTests {
    typealias Logic = ForkTranslateLogic

    static func run(_ suite: TestSuite) {
        let selected = Logic.request(selection: "  Hello world \n", clipboard: "ignored")
        suite.expect(selected == Logic.Request(text: "Hello world", source: .selection, truncated: false),
               "the selection comes first, without the spaces around it")
        suite.expect(Logic.request(selection: nil, clipboard: "Bonjour")?.source == .clipboard
            && Logic.request(selection: "   ", clipboard: "Bonjour")?.source == .clipboard
            && Logic.request(selection: "42 — 17", clipboard: "Bonjour")?.text == "Bonjour",
               "with no words selected, the clipboard's text is translated")
        suite.expect(Logic.request(selection: nil, clipboard: nil) == nil
            && Logic.request(selection: "", clipboard: "1 234,56") == nil,
               "with no words anywhere, there is nothing to translate")
        let long = String(repeating: "a", count: Logic.maxCharacters + 10)
        let cut = Logic.request(selection: long, clipboard: nil)
        suite.expect(cut?.text.count == Logic.maxCharacters && cut?.truncated == true,
               "a very long text is cut, and says so")

        suite.expect(Logic.detectedLanguage("Bonjour, je voudrais réserver une table pour ce soir.") == "fr"
            && Logic.detectedLanguage("Could you send me the invoice by Friday, please?") == "en",
               "the text's language is recognised")
        suite.expect(Logic.target(forDetected: "fr") == "en" && Logic.target(forDetected: "fr-CA") == "en",
               "French goes to English")
        suite.expect(Logic.target(forDetected: "en") == "fr" && Logic.target(forDetected: "es") == "fr"
            && Logic.target(forDetected: nil) == "fr",
               "every other language, or an unclear one, goes to French")

        suite.expect(Logic.canReplace(Logic.Request(text: "x", source: .selection, truncated: false))
            && !Logic.canReplace(Logic.Request(text: "x", source: .clipboard, truncated: false))
            && !Logic.canReplace(Logic.Request(text: "x", source: .typed, truncated: false)),
               "only a selection can be replaced by its translation")

        suite.expect(Logic.request(typed: "  Good morning ") == Logic.Request(text: "Good morning", source: .typed, truncated: false)
            && Logic.request(typed: "   ") == nil && Logic.request(typed: "2026") == nil,
               "a text typed in the page is translated, as long as it holds words")

        let marked = "mesure [Début de la mise en surbrillance]environ 12,7 cm[Fin de la mise en surbrillance], avec"
        suite.expect(Logic.request(selection: marked, clipboard: nil)?.text == "mesure environ 12,7 cm, avec"
            && Logic.cleaned("is [start of highlight]about[End of highlight] 5") == "is about 5"
            && Logic.cleaned("[Note] stays") == "[Note] stays",
               "the highlight markers apps built on Chrome add are not translated, other brackets stay")
        suite.expect(Logic.request(selection: "[Début de la mise en surbrillance][Fin de la mise en surbrillance]", clipboard: "Hello")?.source == .clipboard,
               "a selection made only of markers counts as no selection")

        suite.expect(Logic.preferred(stored: "auto") == nil && Logic.preferred(stored: nil) == nil
            && Logic.preferred(stored: "xx") == nil && Logic.preferred(stored: "es") == "es"
            && Logic.preferred(stored: "zh-Hant") == "zh-Hant",
               "auto, nothing or an unknown code mean the automatic direction")
        suite.expect(Logic.languages.first == "fr" && Logic.languages.contains("en") && Set(Logic.languages).count == Logic.languages.count,
               "the menu lists each language once, French first")
        suite.expect(Logic.target(forDetected: "en", preferred: "es") == "es"
            && Logic.target(forDetected: nil, preferred: "de") == "de"
            && Logic.target(forDetected: "fr", preferred: "ja") == "ja",
               "with a language chosen, every text goes to it")
        suite.expect(Logic.target(forDetected: "es", preferred: "es") == "fr"
            && Logic.target(forDetected: "pt", preferred: "pt-BR") == "fr"
            && Logic.target(forDetected: "fr-CA", preferred: "fr") == "en",
               "a text already in the chosen language goes to French, or to English when French is chosen")
        suite.expect(Logic.target(forDetected: "fr", preferred: nil) == "en" && Logic.target(forDetected: "it", preferred: nil) == "fr",
               "without a language chosen, the direction stays automatic")
        suite.expect(!Logic.sameLanguage("zh-Hans", "zh-Hant") && Logic.sameLanguage("zh_Hans", "zh-Hans")
            && Logic.sameLanguage("EN-gb", "en"),
               "regions do not split a language, the two Chinese scripts stay apart")

        suite.expect(Logic.showsInIsland(islandEnabled: true, pageShown: true)
            && !Logic.showsInIsland(islandEnabled: false, pageShown: true)
            && !Logic.showsInIsland(islandEnabled: true, pageShown: false),
               "the island shows the translation when its page is there, the panel otherwise")
        let on = UserDefaults(suiteName: "ForkTranslateTests.on")!
        let off = UserDefaults(suiteName: "ForkTranslateTests.off")!
        on.set(true, forKey: DefaultsKey.forkTranslateEnabled)
        off.set(false, forKey: DefaultsKey.forkTranslateEnabled)
        suite.expect(Logic.pageAvailable(in: on) && Logic.islandControlAvailable(in: on)
            && !Logic.pageAvailable(in: off) && !Logic.islandControlAvailable(in: off),
               "the page and the island's button follow the translation's switch")
        on.removePersistentDomain(forName: "ForkTranslateTests.on")
        off.removePersistentDomain(forName: "ForkTranslateTests.off")

        let short = Logic.panelHeight(original: "Hi", translated: "Salut")
        let tall = Logic.panelHeight(original: long, translated: long)
        suite.expect(short == 270 && tall == 560 && Logic.panelHeight(original: String(repeating: "word ", count: 60), translated: nil) > short,
               "the panel grows with the text, then scrolls")

        for key in [DefaultsKey.forkTranslateEnabled, DefaultsKey.forkTranslateShortcutEnabled] {
            suite.expect(Defaults.registeredDefaults[key] as? Bool == true && SettingsBackupSupport.exportKeys().contains(key),
                   "\(key) is on out of the box and travels in backups")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkTranslateTarget] as? String == Logic.automatic
            && SettingsBackupSupport.exportKeys().contains(DefaultsKey.forkTranslateTarget),
               "the chosen language starts automatic and travels in backups")
    }
}
