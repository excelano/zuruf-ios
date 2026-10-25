// TalkToWidget.swift
// ZurufWidgets
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents
import SwiftUI
import WidgetKit

struct RecipientEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Person or Group"
    static let defaultQuery = RecipientQuery()

    let id: String
    let name: String

    init(_ recipient: Recipient) {
        id = recipient.key
        name = recipient.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct RecipientQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RecipientEntity] {
        SavedRecipients.load().filter { identifiers.contains($0.key) }.map(RecipientEntity.init)
    }

    func suggestedEntities() async throws -> [RecipientEntity] {
        SavedRecipients.load().map(RecipientEntity.init)
    }
}

struct TalkToIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Talk to"

    @Parameter(title: "Person or Group")
    var recipient: RecipientEntity?

    init() {}

    init(_ recipient: Recipient) {
        self.recipient = RecipientEntity(recipient)
    }
}

// The app reloads this timeline, and the recommendations, whenever the people
// and groups on the server change.
struct TalkToProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TalkEntry {
        TalkEntry(date: .now, recipient: nil)
    }

    func snapshot(for intent: TalkToIntent, in context: Context) async -> TalkEntry {
        entry(for: intent)
    }

    func timeline(for intent: TalkToIntent, in context: Context) async -> Timeline<TalkEntry> {
        Timeline(entries: [entry(for: intent)], policy: .never)
    }

    // watchOS offers each recommendation as a complication of its own.
    func recommendations() -> [AppIntentRecommendation<TalkToIntent>] {
        SavedRecipients.load().map { AppIntentRecommendation(intent: TalkToIntent($0), description: "Talk to \($0.name)") }
    }

    // Looked up again so a renamed group shows its new name, and someone no
    // longer on the server shows nobody.
    private func entry(for intent: TalkToIntent) -> TalkEntry {
        let recipient = intent.recipient.flatMap { entity in SavedRecipients.load().first { $0.key == entity.id } }
        return TalkEntry(date: .now, recipient: recipient)
    }
}

struct TalkToWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TalkTo", intent: TalkToIntent.self, provider: TalkToProvider()) { entry in
            TalkWidgetView(entry: entry, showsInitials: true)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Talk to")
        .description("Opens Zuruf ready to talk to a person or group you choose.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
