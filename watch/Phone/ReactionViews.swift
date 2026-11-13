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

// The reactions on a clip, at the size of its Play button. The same emoji
// from several people shows once with a count.
private struct ReactionCluster: View {
    let chips: [ReactionChip]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(chips) { chip in
                HStack(spacing: 2) {
                    Text(chip.emoji)
                        .font(.title)
                    if chip.count > 1 {
                        Text("\(chip.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    // Hangs a clip's reactions off the bubble's top corner on the given side,
    // with room above the bubble for them.
    func reactions(_ reactions: [Reaction], on edge: HorizontalEdge) -> some View {
        overlay(alignment: edge == .leading ? .topLeading : .topTrailing) {
            if !reactions.isEmpty {
                ReactionCluster(chips: reactions.chips)
                    .offset(x: edge == .leading ? -12 : 12, y: -24)
            }
        }
        .padding(.top, reactions.isEmpty ? 0 : 18)
    }
}
