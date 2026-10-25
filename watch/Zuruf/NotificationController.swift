// NotificationController.swift
// Zuruf
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AVFoundation
import SwiftUI
import UserNotifications
import WatchKit

final class NotificationController: WKUserNotificationHostingController<NotificationView> {
    private var content: UNNotificationContent?

    override class var isInteractive: Bool { true }

    override var body: NotificationView {
        NotificationView(content: content)
    }

    override func didReceive(_ notification: UNNotification) {
        content = notification.request.content
    }
}

struct NotificationView: View {
    // Long enough for the notification sound to finish, so it does not duck the clip.
    private static let autoplayDelay: Duration = .seconds(1.5)

    let content: UNNotificationContent?
    @AppStorage(ClipNotification.playAutomaticallyKey) private var playAutomatically = true
    @ObservedObject private var player = ClipPlayer.shared
    @ObservedObject private var transcripts = Transcripts.shared
    @ObservedObject private var link = AccountLink.shared
    @State private var transcription = Transcription.idle

    private enum Transcription {
        case idle, waiting, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content?.title ?? "")
                .font(.headline)
            Text(content?.body ?? "")
                .font(.footnote)
            if let clipID {
                // The transcript takes Transcribe's place, so Play does not
                // move under a finger that just tapped Transcribe.
                if let transcript = transcripts.texts[clipID] {
                    if !transcript.isEmpty {
                        Text(transcript)
                    }
                } else if link.canAskPhone {
                    Button {
                        transcribe(clipID)
                    } label: {
                        Label(transcribeTitle, systemImage: "text.quote")
                    }
                    .disabled(transcription == .waiting)
                }
                Button {
                    play(clipID, category: .playback)
                } label: {
                    Label(player.loadingClipID == clipID ? "Loading…" : "Play", systemImage: "play.fill")
                }
            }
        }
        .task {
            guard let clipID, playAutomatically, ClipNotification.claimAutoplay(of: clipID) else { return }
            try? await Task.sleep(for: Self.autoplayDelay)
            play(clipID, category: .ambient)
        }
    }

    private var clipID: String? {
        content.flatMap(ClipNotification.clipID(in:))
    }

    private var transcribeTitle: String {
        switch transcription {
        case .idle: "Transcribe"
        case .waiting: "Transcribing…"
        case .failed: "Couldn't transcribe"
        }
    }

    private func transcribe(_ clipID: String) {
        transcription = .waiting
        Task {
            transcription = await AccountLink.shared.requestTranscript(of: clipID) == nil ? .failed : .idle
        }
    }

    private func play(_ clipID: String, category: AVAudioSession.Category) {
        player.play(clipID: clipID, attachment: content?.attachments.first?.url, category: category)
    }
}
