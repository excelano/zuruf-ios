// TalkWidget.swift
// ZurufWidgets
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import WidgetKit

@main
struct ZurufWidgets: WidgetBundle {
    var body: some Widget {
        TalkWidget()
        TalkToWidget()
    }
}

struct TalkEntry: TimelineEntry {
    let date: Date
    let recipient: Recipient?
    // The face editor's gallery shows the last-recipient widget as itself, not
    // as whoever was last, which would look like that person's Talk to widget.
    var isLastRecipientPreview = false
}

// The app reloads this timeline whenever it sends a clip to someone new.
struct TalkProvider: TimelineProvider {
    func placeholder(in context: Context) -> TalkEntry {
        TalkEntry(date: .now, recipient: nil, isLastRecipientPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TalkEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(TalkEntry(date: .now, recipient: LastRecipient.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TalkEntry>) -> Void) {
        completion(Timeline(entries: [TalkEntry(date: .now, recipient: LastRecipient.load())], policy: .never))
    }
}

struct TalkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Talk", provider: TalkProvider()) { entry in
            TalkWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Talk")
        .description("Opens Zuruf ready to talk to whoever you last talked to.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct TalkWidgetView: View {
    let entry: TalkEntry
    // Tells apart circles for different people, where the last-recipient
    // circle shows only the microphone.
    var showsInitials = false
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        content
            .widgetURL(entry.recipient.flatMap(TalkLink.url(for:)))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "mic.fill")
                .font(.title2)
                .widgetLabel(entry.isLastRecipientPreview ? "Last person" : entry.recipient?.name ?? "Zuruf")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Zuruf", systemImage: "mic.fill")
                    .font(.headline)
                Text(talkTo ?? "Open to talk")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label(talkTo ?? "Zuruf", systemImage: "mic.fill")
        default:
            ZStack {
                if renderingMode == .fullColor {
                    Circle().fill(Self.yellow)
                } else {
                    AccessoryWidgetBackground()
                }
                Group {
                    if showsInitials, let recipient = entry.recipient {
                        Text(recipient.initials)
                            .font(.title3.bold())
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                    }
                }
                .foregroundStyle(renderingMode == .fullColor ? Self.ink : .primary)
            }
        }
    }

    private var talkTo: String? {
        entry.isLastRecipientPreview ? "Talk to last person" : entry.recipient.map { "Talk to \($0.name)" }
    }

    // The app icon's colors.
    private static let yellow = Color(red: 0xFA / 255, green: 0xCC / 255, blue: 0x15 / 255)
    private static let ink = Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255)
}
