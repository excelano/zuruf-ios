// HomeView.swift
// Phone
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack(path: $model.talkPath) {
            List {
                ForEach(conversations) { conversation in
                    ContactRow(recipient: conversation.recipient, systemImage: conversation.systemImage)
                }
                if let error = model.refreshError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Zuruf")
            .navigationDestination(for: Recipient.self) { recipient in
                ConversationView(recipient: recipient)
            }
            .toolbar {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .refreshable {
                await model.refresh()
            }
        }
    }

    // People and groups together, the latest conversation first, then those
    // with no clips by name. Bots come last, so testing with Echo does not
    // push people down.
    private var conversations: [ConversationEntry] {
        guard let contacts = model.contacts else { return [] }
        let entries = contacts.groups.map {
            ConversationEntry(recipient: .group(id: $0.id, name: $0.name), systemImage: "person.2", isBot: false)
        } + contacts.users.map {
            ConversationEntry(recipient: .person(id: $0.id, name: $0.displayName),
                              systemImage: $0.isBot ? "arrow.uturn.backward" : "person", isBot: $0.isBot)
        }
        return entries.sorted { a, b in
            if a.isBot != b.isBot {
                return !a.isBot
            }
            switch (model.clips?.lastActivity(with: a.recipient), model.clips?.lastActivity(with: b.recipient)) {
            case let (aDate?, bDate?): return aDate > bDate
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.recipient.name.localizedStandardCompare(b.recipient.name) == .orderedAscending
            }
        }
    }
}

private struct ConversationEntry: Identifiable {
    let recipient: Recipient
    let systemImage: String
    let isBot: Bool

    var id: String { recipient.key }
}

private struct ContactRow: View {
    let recipient: Recipient
    let systemImage: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationLink(value: recipient) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipient.name)
                    if let lastActivity = model.clips?.lastActivity(with: recipient) {
                        Text(lastActivity, format: .relative(presentation: .named))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let unplayed = model.clips?.unplayedCount(from: recipient), unplayed > 0 {
                    Text("\(unplayed)")
                        .font(.footnote.bold().monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
            }
        }
    }
}
