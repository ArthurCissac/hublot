// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import Foundation

/// The fork's cards on the AI page (ForkAgentCards): a session waiting for
/// an answer, the time spent on each project, the projects to pick up
/// again. They live among upstream's cards, so they can be hidden and moved
/// like them; the waiting one shows first, and only while a session waits.
enum ForkAgentCardsLogic {
    /// Set by ForkClaudeSessions once it runs; tests keep the default.
    static var sessionWaits: () -> Bool = { false }

    static func arranged(_ cards: [NotchAgentCard], waiting: Bool = sessionWaits()) -> [NotchAgentCard] {
        let rest = cards.filter { $0 != .forkWaiting }
        return waiting && cards.contains(.forkWaiting) ? [.forkWaiting] + rest : rest
    }

    static func symbol(_ card: NotchAgentCard) -> String {
        switch card {
        case .forkWaiting: return ForkClaudeSessionsLogic.noticeSymbol
        case .forkTime: return "clock"
        case .forkResume: return "arrow.uturn.backward.circle"
        default: return card.symbol
        }
    }

    static func title(_ card: NotchAgentCard, french: Bool) -> String {
        switch card {
        case .forkWaiting: return french ? "En attente" : "Waiting"
        case .forkTime: return french ? "Temps par projet" : "Time per project"
        case .forkResume: return french ? "Reprendre" : "Pick up again"
        default: return card.rawValue
        }
    }
}
