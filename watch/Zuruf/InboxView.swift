// InboxView.swift
// Zuruf
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if let received = model.clips?.received, !received.isEmpty {
                Section("Received") {
                    ForEach(received) { clip in
                        NavigationLink {
                            ClipView(clipID: clip.id)
                        } label: {
                            ReceivedRow(clip: clip)
                        }
                        .swipeActions {
                            if clip.playedAt == nil {
                                Button("Mark as Read", systemImage: "envelope.open") {
                                    Task { await model.markPlayed(clip.id) }
                                }
                                .tint(.accentColor)
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.deleteClip(clip.id) }
                            }
                        }
                    }
                }
            }
            if let sent = model.clips?.sent, !sent.isEmpty {
                Section("Sent") {
                    ForEach(sent) { clip in
                        SentRow(clip: clip)
                    }
                }
            }
            if model.clips.map({ $0.received.isEmpty && $0.sent.isEmpty }) ?? true {
                Text("No messages")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Inbox")
        .refreshable {
            await model.refresh()
        }
    }
}

private struct ReceivedRow: View {
    let clip: ReceivedClip
    @ObservedObject private var transcripts = Transcripts.shared

    var body: some View {
        HStack {
            Circle()
                .fill(clip.playedAt == nil ? Color.accentColor : .clear)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading) {
                Text(clip.senderName)
                if let groupName = clip.groupName {
                    Text(groupName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let transcript = transcripts.texts[clip.id], !transcript.isEmpty {
                    Text(transcript)
                        .font(.footnote)
                        .lineLimit(2)
                }
                if !clip.reactions.isEmpty {
                    Text(reactionSummary(clip.reactions))
                        .font(.footnote)
                }
                Text(clip.createdAt, format: .relative(presentation: .named))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SentRow: View {
    let clip: SentClip
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("To \(model.recipientName(of: clip))")
            Text(playedSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !clip.reactions.isEmpty {
                Text(reactionSummary(clip.reactions))
                    .font(.footnote)
            }
        }
    }

    private var playedSummary: String {
        let names = clip.playedBy.compactMap { model.contacts?.name(ofUser: $0.userId) }
        return names.isEmpty ? "Not played yet" : "Played by " + names.formatted(.list(type: .and))
    }
}

// The same emoji from several people shows once with a count.
private func reactionSummary(_ reactions: [Reaction]) -> String {
    reactions.chips(mine: nil).map { $0.count > 1 ? "\($0.emoji)\($0.count)" : $0.emoji }.joined(separator: " ")
}

struct ClipView: View {
    let clipID: String
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var player = ClipPlayer.shared

    var body: some View {
        if let clip = model.clips?.received.first(where: { $0.id == clipID }) {
            content(clip)
        }
    }

    private func content(_ clip: ReceivedClip) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(clip.senderName)
                    .font(.headline)
                Text(Duration.milliseconds(clip.durationMs), format: .time(pattern: .minuteSecond))
                    .foregroundStyle(.secondary)
                ClipTranscript(clipID: clip.id)
                Button {
                    player.play(clipID: clip.id, attachment: nil, category: .playback)
                } label: {
                    Label(player.loadingClipID == clip.id ? "Loading…" : "Play", systemImage: "play.fill")
                }
                // Inbox and this view are pushed outside the talk path, so a
                // value link would land beneath them; leave the inbox instead.
                Button {
                    model.showInbox = false
                    model.talk(to: clip.replyRecipient)
                } label: {
                    Label("Reply", systemImage: "mic.fill")
                }
                ReactionGrid(selected: model.account.flatMap { clip.reaction(of: $0.userID) }) { emoji in
                    Task { await model.react(emoji, to: clip.id) }
                }
            }
        }
    }
}

// The emoji to react with, three to a row. The one already chosen is
// highlighted, and choosing it again takes it back.
private struct ReactionGrid: View {
    let selected: String?
    let onReact: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(ReactionPalette.emoji, id: \.self) { emoji in
                Button {
                    onReact(emoji)
                } label: {
                    Text(emoji)
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(selected == emoji ? .accentColor : nil)
                .accessibilityLabel(selected == emoji ? "Remove \(emoji)" : "React \(emoji)")
            }
        }
    }
}
