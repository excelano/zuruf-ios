// HomeView.swift
// Phone
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(model.conversations) { conversation in
                    ContactRow(recipient: conversation.recipient, systemImage: conversation.systemImage)
                }
                if let error = model.refreshError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Zuruf")
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
        } detail: {
            if let recipient = model.talkPath.last {
                ConversationView(recipient: recipient)
                    .id(recipient)
            } else {
                ContentUnavailableView("No Conversation Selected", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }

    /// The open conversation, kept in the model's path so a notification can open one.
    private var selection: Binding<Recipient?> {
        Binding {
            model.talkPath.last
        } set: { recipient in
            model.talkPath = recipient.map { [$0] } ?? []
        }
    }
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
