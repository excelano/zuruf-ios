// Reactions.swift
// AppCore
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

// The set people know from Messages. The server accepts only these.
enum ReactionPalette {
    static let emoji = ["👍", "👎", "❤️", "😂", "‼️", "❓"]
}

// One emoji on a clip, with how many people chose it and whether one of
// them is this account.
struct ReactionChip: Identifiable {
    let emoji: String
    let count: Int
    let isMine: Bool

    var id: String { emoji }
}

extension [Reaction] {
    // In the order each emoji was first chosen.
    func chips(mine userID: String?) -> [ReactionChip] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for reaction in self {
            if counts[reaction.emoji] == nil {
                order.append(reaction.emoji)
            }
            counts[reaction.emoji, default: 0] += 1
        }
        return order.map { emoji in
            ReactionChip(emoji: emoji, count: counts[emoji] ?? 1,
                         isMine: contains { $0.emoji == emoji && $0.userId == userID })
        }
    }
}

extension ReceivedClip {
    func reaction(of userID: String) -> String? {
        reactions.first { $0.userId == userID }?.emoji
    }
}
