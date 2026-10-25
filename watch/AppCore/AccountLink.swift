// AccountLink.swift
// AppCore
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import WatchConnectivity
#if os(iOS)
import UIKit
#endif

// Keeps a paired watch and phone on one account and one "Play automatically"
// setting. Whichever joins passes the account to the other, which signs in as
// a device of its own; deleting the account on one signs the other out. The
// application context holds only the latest of these, and reaches the other
// app whenever it next runs. The phone also sends the watch its transcripts,
// and makes one when the watch asks.
@MainActor
final class AccountLink: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = AccountLink()

    private static let accountKey = "account"
    private static let signedOutKey = "signedOutUserID"
    private static let playAutomaticallyKey = "playAutomatically"
    private static let playAutomaticallyChangedAtKey = "playAutomaticallyChangedAt"
    private nonisolated static let transcriptsKey = "transcripts"
    private nonisolated static let transcribeKey = "transcribe"
    private nonisolated static let transcriptKey = "transcript"

    // A phone paired with a watch that has Zuruf installed.
    @Published private(set) var hasWatch = false
    // A watch whose phone has Zuruf installed and can be reached now.
    @Published private(set) var canAskPhone = false

    func activate() {
        guard WCSession.isSupported(), !DemoMode.isActive else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // Leaves any sign-out notice in place: one sent just before a new join
    // must still reach the other device, which may hold the deleted account.
    func share(_ account: Account) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        update { $0[Self.accountKey] = data }
    }

    func shareSignOut(of userID: String) {
        update {
            $0[Self.accountKey] = nil
            $0[Self.signedOutKey] = userID
        }
    }

    func setPlayAutomatically(_ isOn: Bool) {
        ClipNotification.setPlayAutomatically(isOn, changedAt: Date().timeIntervalSince1970)
        update { _ in }
    }

    // Each update replaces the whole context, so it starts from the last one
    // sent. Fails while the other app is not installed, which is fine: the
    // context is sent again on every launch.
    private func update(_ change: (inout [String: Any]) -> Void) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        var context = WCSession.default.applicationContext
        change(&context)
        context[Self.playAutomaticallyKey] = ClipNotification.playAutomatically
        context[Self.playAutomaticallyChangedAtKey] = ClipNotification.playAutomaticallyChangedAt
        try? WCSession.default.updateApplicationContext(context)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            updateHasWatch()
            updateCanAskPhone()
            await receive(context)
            if let account = AppModel.shared.account {
                share(account)
            } else {
                update { _ in }
            }
            #if os(iOS)
            Transcripts.shared.shareAgainWithWatch()
            #endif
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in await receive(context) }
    }

    // Reads the other device's latest context again, for an account shared
    // while this one was still signed in to a deleted account.
    func catchUp() async {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        await receive(WCSession.default.receivedApplicationContext)
    }

    // The received context is the other app's latest, which may be old news,
    // so the setting only applies when it changed after this one did.
    private func receive(_ context: [String: Any]) async {
        if let isOn = context[Self.playAutomaticallyKey] as? Bool,
           let changedAt = context[Self.playAutomaticallyChangedAtKey] as? Double,
           changedAt > ClipNotification.playAutomaticallyChangedAt {
            ClipNotification.setPlayAutomatically(isOn, changedAt: changedAt)
        }
        if let userID = context[Self.signedOutKey] as? String {
            AppModel.shared.signedOutElsewhere(userID)
        }
        if let data = context[Self.accountKey] as? Data,
           let account = try? JSONDecoder().decode(Account.self, from: data) {
            await AppModel.shared.adopt(account)
        }
    }

    #if os(watchOS)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let texts = userInfo[Self.transcriptsKey] as? [String: String] else { return }
        Task { @MainActor in Transcripts.shared.add(texts) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in updateCanAskPhone() }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor in updateCanAskPhone() }
    }

    // Asks the phone for a clip's transcript, which wakes the iPhone app.
    func requestTranscript(of clipID: String) async -> String? {
        let text: String? = await withCheckedContinuation { continuation in
            WCSession.default.sendMessage([Self.transcribeKey: clipID]) { reply in
                continuation.resume(returning: reply[Self.transcriptKey] as? String)
            } errorHandler: { _ in
                continuation.resume(returning: nil)
            }
        }
        if let text {
            Transcripts.shared.add([clipID: text])
        }
        return text
    }
    #endif

    private func updateCanAskPhone() {
        #if os(watchOS)
        canAskPhone = WCSession.default.isCompanionAppInstalled && WCSession.default.isReachable
        #endif
    }

    private func updateHasWatch() {
        #if os(iOS)
        hasWatch = WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
        #endif
    }

    #if os(iOS)
    // The watch asking for a transcript, from its notification. The phone may
    // be in the background, so the work runs in a background task.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let clipID = message[Self.transcribeKey] as? String else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            let task = UIApplication.shared.beginBackgroundTask()
            let text = await Transcripts.shared.transcript(of: clipID)
            replyHandler(text.map { [Self.transcriptKey: $0] } ?? [:])
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    // Replaces any batch still waiting to reach the watch, since each holds
    // every transcript of a received clip.
    func shareTranscripts(_ texts: [String: String]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, hasWatch else { return }
        for transfer in WCSession.default.outstandingUserInfoTransfers where transfer.userInfo[Self.transcriptsKey] != nil {
            transfer.cancel()
        }
        WCSession.default.transferUserInfo([Self.transcriptsKey: texts])
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    // Called when the phone switches to another paired watch.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            updateHasWatch()
            if let account = AppModel.shared.account {
                share(account)
            }
            Transcripts.shared.shareAgainWithWatch()
        }
    }
    #endif
}
