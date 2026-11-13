// ReactionViews.swift
// Phone
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

// The row of emoji a long-press on a received clip opens. The one already
// chosen is highlighted, and choosing it again takes it back.
struct ReactionBar: View {
    let selected: String?
    let onReact: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ReactionPalette.emoji, id: \.self) { emoji in
                Button {
                    onReact(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .padding(6)
                        .background(selected == emoji ? Color.accentColor.opacity(0.3) : .clear, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }
}

// The reactions on a clip, as small overlapping capsules that hang off the
// bubble's corner. The same emoji from several people shows once with a count.
struct ReactionCluster: View {
    let chips: [ReactionChip]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(chips) { chip in
                HStack(spacing: 2) {
                    Text(chip.emoji)
                        .font(.system(size: 13))
                    if chip.count > 1 {
                        Text("\(chip.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(chip.isMine ? Color.black : .secondary)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(chip.isMine ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .overlay(Capsule().stroke(Color(.systemBackground), lineWidth: 1.5))
            }
        }
        .allowsHitTesting(false)
    }
}
