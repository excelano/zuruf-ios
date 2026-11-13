// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

@MainActor
final class SendLog: ObservableObject {
    static let shared = SendLog()
    private static let maxLines = 300

    @Published private(set) var lines: [String]
    private let fileURL = URL.applicationSupportDirectory.appending(path: "send.log")

    init() {
        lines = (try? String(contentsOf: fileURL, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
    }

    func note(_ text: String) {
        lines.append("\(Date.now.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second())) \(text)")
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func note(_ text: String, error: Error) {
        let nsError = error as NSError
        var detail = "\(nsError.domain) \(nsError.code)"
        if let urlError = error as? URLError, let reason = urlError.networkUnavailableReason {
            detail += " unavailable=\(reason.rawValue)"
        }
        note("\(text) failed: \(detail) \(error.localizedDescription)")
    }
}
