// Outbox.swift
// AppCore
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

// Recorded clips wait here, on disk, until the server accepts them.
@MainActor
final class Outbox: ObservableObject {
    struct Item: Codable, Identifiable {
        let id: UUID
        let recipient: Recipient
        var attempts: Int

        var clientID: String {
            id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
    }

    @Published private(set) var items: [Item] = []
    private var isSending = false
    private var retryWait: Task<Void, Never>?
    private let directory: URL
    private let indexURL: URL

    init() {
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("outbox", isDirectory: true)
        indexURL = directory.appendingPathComponent("outbox.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            items = (try? JSONDecoder().decode([Item].self, from: data)) ?? []
        }
    }

    func enqueue(_ file: URL, to recipient: Recipient) {
        let item = Item(id: UUID(), recipient: recipient, attempts: 0)
        guard (try? FileManager.default.moveItem(at: file, to: fileURL(item))) != nil else { return }
        items.append(item)
        save()
        SendLog.shared.note("enqueued \(item.id.uuidString.prefix(8)), \(items.count) waiting")
        send()
    }

    func send() {
        guard !isSending else {
            retryWait?.cancel()
            return
        }
        isSending = true
        Task {
            await drain()
            isSending = false
        }
    }

    func removeAll() {
        items.forEach { try? FileManager.default.removeItem(at: fileURL($0)) }
        items = []
        save()
    }

    private func drain() async {
        while let item = items.first {
            guard let api = AppModel.shared.api else { return }
            guard FileManager.default.fileExists(atPath: fileURL(item).path) else {
                remove(item)
                continue
            }
            let tag = "upload \(item.id.uuidString.prefix(8)) try \(item.attempts + 1)"
            let started = Date.now
            SendLog.shared.note("\(tag) start")
            do {
                try await BackgroundTime.keep(reason: "Sending a message") {
                    try await api.uploadClip(file: self.fileURL(item), clientID: item.clientID, to: item.recipient)
                } expired: {
                    SendLog.shared.note("\(tag) ran out of background time after \(Self.seconds(since: started))")
                }
                SendLog.shared.note("\(tag) sent in \(Self.seconds(since: started))")
                remove(item)
                await AppModel.shared.refresh()
            } catch let error as APIError where error.isPermanent {
                SendLog.shared.note("\(tag) after \(Self.seconds(since: started)), dropped", error: error)
                remove(item)
            } catch {
                SendLog.shared.note("\(tag) after \(Self.seconds(since: started))", error: error)
                guard let index = items.firstIndex(where: { $0.id == item.id }) else { continue }
                items[index].attempts += 1
                save()
                let delay = min(pow(2, Double(items[index].attempts)), 300)
                let wait = Task { _ = try? await Task.sleep(for: .seconds(delay)) }
                retryWait = wait
                await wait.value
                retryWait = nil
            }
        }
    }

    private static func seconds(since date: Date) -> String {
        String(format: "%.1fs", Date.now.timeIntervalSince(date))
    }

    private func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: fileURL(item))
        items.removeAll { $0.id == item.id }
        save()
    }

    private func fileURL(_ item: Item) -> URL {
        directory.appendingPathComponent(item.id.uuidString).appendingPathExtension("m4a")
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: indexURL, options: .atomic)
    }
}
