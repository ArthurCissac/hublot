// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The background sound's and Todoist's own pages in the island: their keys,
/// names, availability, and the wave opening its page.
enum ForkIslandPagesTests {
    static func run(_ suite: TestSuite) {
        let keys = NotchModule.allCases.map(\.shortcutKey)
        suite.expect(Set(keys).count == keys.count && NotchModule.ambient.shortcutKey == "u" && NotchModule.tasks.shortcutKey == "k",
                     "every island page keeps its own key, the two new ones included")
        suite.expect(NotchCompactActivity.ambient.module == .ambient,
                     "a click on the background sound's wave opens its own page")
        suite.expect(ForkTodoistLogic.title(french: true) == "Tâches" && ForkTodoistLogic.title(french: false) == "Tasks"
            && !ForkAmbientLogic.pageSummary(french: true).isEmpty && !ForkTodoistLogic.pageSummary(french: false).isEmpty,
                     "both pages have a name and a summary in French and English")
        let name = "ForkIslandPagesTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: DefaultsKey.forkAmbientEnabled)
        defaults.set(true, forKey: DefaultsKey.forkTodoistEnabled)
        suite.expect(!NotchModule.ambient.isAvailable(in: defaults) && NotchModule.tasks.isAvailable(in: defaults),
                     "a page shows only while its feature is on")
    }
}
