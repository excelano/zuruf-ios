// Reactions.swift
// AppCore
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

// The set people know from Messages. The server accepts only these.
enum ReactionPalette {
    static let emoji = ["👍", "👎", "❤️", "😂", "‼️", "❓"]
}

// One emoji on a clip, with how many people chose it.
struct ReactionChip: Identifiable {
    let emoji: String
    let count: Int

    var id: String { emoji }
}

extension [Reaction] {
    // In the order each emoji was first chosen.
    var chips: [ReactionChip] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for reaction in self {
            if counts[reaction.emoji] == nil {
                order.append(reaction.emoji)
            }
            counts[reaction.emoji, default: 0] += 1
        }
        return order.map { ReactionChip(emoji: $0, count: counts[$0] ?? 1) }
    }
}

extension ReceivedClip {
    func reaction(of userID: String) -> String? {
        reactions.first { $0.userId == userID }?.emoji
    }
}
