// Transcriber.swift
// Shared
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

#if os(iOS)
import AVFoundation
import Speech

// Transcribes an audio file on this iPhone in its own language.
enum Transcriber {
    // SpeechTranscriber where the hardware and language have it, otherwise
    // DictationTranscriber. Words, such as names, are favored over others
    // that sound like them.
    static func transcribe(_ file: URL, expecting words: [String]) async throws -> String {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            return try await analyze(file, with: transcriber, expecting: words) {
                try await transcriber.results.reduce(into: []) { $0.append(String($1.text.characters)) }
            }
        }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else {
            throw CocoaError(.featureUnsupported)
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
        return try await analyze(file, with: transcriber, expecting: words) {
            try await transcriber.results.reduce(into: []) { $0.append(String($1.text.characters)) }
        }
    }

    private static func analyze(_ file: URL, with module: any SpeechModule, expecting words: [String],
                                results: @escaping @Sendable () async throws -> [String]) async throws -> String {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        if !words.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = words
            try await analyzer.setContext(context)
        }
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
}
#endif
