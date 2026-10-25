// ClipTranscript.swift
// Zuruf
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

// A clip's transcript, or, while the watch has none and the phone can be
// reached, a Transcribe button in its place. The text takes the button's
// place, so what follows does not move under a finger that just tapped it.
struct ClipTranscript: View {
    let clipID: String
    @ObservedObject private var transcripts = Transcripts.shared
    @ObservedObject private var link = AccountLink.shared
    @State private var transcription = Transcription.idle

    private enum Transcription {
        case idle, waiting, failed
    }

    var body: some View {
        if let transcript = transcripts.texts[clipID] {
            if !transcript.isEmpty {
                Text(transcript)
            }
        } else if link.canAskPhone {
            Button {
                transcribe()
            } label: {
                Label(title, systemImage: "text.quote")
            }
            .disabled(transcription == .waiting)
        }
    }

    private var title: String {
        switch transcription {
        case .idle: "Transcribe"
        case .waiting: "Transcribing…"
        case .failed: "Couldn't transcribe"
        }
    }

    private func transcribe() {
        transcription = .waiting
        Task {
            transcription = await link.requestTranscript(of: clipID) == nil ? .failed : .idle
        }
    }
}
