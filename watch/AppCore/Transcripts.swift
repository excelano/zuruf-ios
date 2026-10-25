// Transcripts.swift
// AppCore
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
#if os(iOS)
import AVFoundation
import Speech
#endif

// Transcripts of clips, keyed by clip. The phone makes them in its own
// language, of sent and received clips, and sends those of received clips to
// the paired watch, which keeps them too. They never reach the server.
@MainActor
final class Transcripts: ObservableObject {
    static let shared = Transcripts()

    @Published private(set) var texts: [String: String]
    private let fileURL = URL.applicationSupportDirectory.appending(path: "transcripts.json")

    #if os(iOS)
    @Published private(set) var transcribingClipID: String?
    private var queue: [String] = []
    private var drainTask: Task<Void, Never>?
    private var failed: Set<String> = []
    private var receivedClipIDs: Set<String>?
    private var sharedWithWatch: [String: String]?
    #endif

    init() {
        texts = DemoMode.isActive ? DemoMode.transcripts
            : (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    // Drops the transcripts of clips that are gone from the server. The phone
    // also transcribes the clips that have none yet, newest first, one at a
    // time; a clip that fails is tried again the next time the app launches.
    func update(for clips: ClipList) {
        guard !DemoMode.isActive else { return }
        let dated = clips.received.map { ($0.id, $0.createdAt) } + clips.sent.map { ($0.id, $0.createdAt) }
        let ids = Set(dated.map(\.0))
        if texts.keys.contains(where: { !ids.contains($0) }) {
            texts = texts.filter { ids.contains($0.key) }
            save()
        }
        #if os(iOS)
        receivedClipIDs = Set(clips.received.map(\.id))
        shareWithWatch()
        queue = dated.sorted { $0.1 > $1.1 }
            .map(\.0)
            .filter { texts[$0] == nil && !failed.contains($0) && $0 != transcribingClipID }
        guard drainTask == nil else { return }
        drainTask = Task {
            await drain()
            drainTask = nil
        }
        #endif
    }

    func removeAll() {
        #if os(iOS)
        queue = []
        #endif
        texts = [:]
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(texts).write(to: fileURL, options: .atomic)
    }

    #if os(watchOS)
    // Transcripts the phone sent, which may include clips this watch has not
    // listed yet.
    func add(_ received: [String: String]) {
        texts.merge(received) { $1 }
        save()
    }
    #endif

    #if os(iOS)
    // Waits until every clip queued so far is transcribed or has failed.
    func finish() async {
        await drainTask?.value
    }

    // A clip's transcript, made now if there is none yet, for the watch.
    func transcript(of clipID: String) async -> String? {
        if let text = texts[clipID] {
            return text
        }
        guard let text = await transcribe(clipID) else { return nil }
        texts[clipID] = text
        save()
        shareWithWatch()
        return text
    }

    // Sends the transcripts of received clips to the watch whenever they
    // change, once this launch has seen the clip list.
    private func shareWithWatch() {
        guard let receivedClipIDs else { return }
        let received = texts.filter { receivedClipIDs.contains($0.key) }
        guard received != sharedWithWatch else { return }
        sharedWithWatch = received
        AccountLink.shared.shareTranscripts(received)
    }

    // For a watch that may have none of them, such as one that just installed
    // Zuruf.
    func shareAgainWithWatch() {
        sharedWithWatch = nil
        shareWithWatch()
    }

    private func drain() async {
        while !queue.isEmpty {
            let clipID = queue.removeFirst()
            guard texts[clipID] == nil else { continue }
            transcribingClipID = clipID
            if let text = await transcribe(clipID) {
                texts[clipID] = text
                save()
                shareWithWatch()
            } else {
                failed.insert(clipID)
            }
        }
        transcribingClipID = nil
    }

    private func transcribe(_ clipID: String) async -> String? {
        guard let data = try? await AppModel.shared.api?.audio(clipID: clipID) else { return nil }
        let file = FileManager.default.temporaryDirectory.appending(path: "\(clipID).m4a")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try data.write(to: file)
            return try await Self.transcribe(file)
        } catch {
            return nil
        }
    }

    // SpeechTranscriber where the hardware and language have it, otherwise
    // DictationTranscriber.
    private nonisolated static func transcribe(_ file: URL) async throws -> String {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            return try await analyze(file, with: transcriber) {
                try await transcriber.results.reduce(into: []) { $0.append(String($1.text.characters)) }
            }
        }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else {
            throw CocoaError(.featureUnsupported)
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
        return try await analyze(file, with: transcriber) {
            try await transcriber.results.reduce(into: []) { $0.append(String($1.text.characters)) }
        }
    }

    private nonisolated static func analyze(_ file: URL, with module: any SpeechModule,
                                            results: @escaping @Sendable () async throws -> [String]) async throws -> String {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        let collected = Task { try await results() }
        let audio = try AVAudioFile(forReading: file)
        if let end = try await analyzer.analyzeSequence(from: audio) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collected.value
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    #endif
}
