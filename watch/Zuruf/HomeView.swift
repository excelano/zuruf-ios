// HomeView.swift
// Zuruf
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var outbox = AppModel.shared.outbox

    var body: some View {
        NavigationStack(path: $model.talkPath) {
            List {
                Section {
                    Button {
                        model.showInbox = true
                    } label: {
                        HStack {
                            Label("Inbox", systemImage: "tray")
                            Spacer()
                            if model.unplayedCount > 0 {
                                Text("\(model.unplayedCount)")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    if !outbox.items.isEmpty {
                        Label("\(outbox.items.count) waiting to send", systemImage: "arrow.up.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(model.conversations) { conversation in
                        NavigationLink(value: conversation.recipient) {
                            Label(conversation.recipient.name, systemImage: conversation.systemImage)
                        }
                    }
                }
                if let error = model.refreshError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("Zuruf")
            .navigationDestination(for: Recipient.self) { recipient in
                TalkView(recipient: recipient)
            }
            .navigationDestination(isPresented: $model.showInbox) {
                InboxView()
            }
            .refreshable {
                await model.refresh()
            }
        }
    }
}
