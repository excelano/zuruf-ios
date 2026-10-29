// NotificationService.swift
// PhoneNotificationService
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import UserNotifications

// Transcribes the clip before the notification shows and puts the text in
// its body. Without a transcript in time, the notification shows unchanged.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var transcription: Task<Void, Never>?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
              let clipID = content.userInfo["clip_id"] as? String,
              let account = AccountStore.load(),
              content.userInfo["server_id"] as? String == account.serverID else {
            contentHandler(request.content)
            return
        }
        self.contentHandler = contentHandler
        self.content = content

        transcription = Task {
            let api = ZurufAPI(account: account)
            async let contacts = try? api.contacts()
            if let data = try? await api.audio(clipID: clipID) {
                let file = FileManager.default.temporaryDirectory.appending(path: "\(clipID).m4a")
                defer { try? FileManager.default.removeItem(at: file) }
                if (try? data.write(to: file)) != nil,
                   let text = try? await Transcriber.transcribe(file, expecting: await contacts?.transcriptionWords ?? []),
                   !text.isEmpty,
                   !Task.isCancelled {
                    content.body = text
                }
            }
            finish()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        transcription?.cancel()
        finish()
    }

    private func finish() {
        guard let content, let contentHandler else { return }
        self.contentHandler = nil
        contentHandler(content)
    }
}
