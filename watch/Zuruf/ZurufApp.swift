// ZurufApp.swift
// Zuruf
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import UserNotifications
import WatchConnectivity
import WatchKit

@main
struct ZurufApp: App {
    @WKApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if model.account == nil {
                    OnboardingView()
                } else {
                    HomeView()
                }
            }
            .environmentObject(model)
            .onChange(of: model.clips) { _, clips in
                if let clips {
                    Transcripts.shared.update(for: clips)
                }
            }
            .onOpenURL { url in
                if let recipient = TalkLink.recipient(from: url) {
                    model.talk(to: recipient)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
        WKNotificationScene(controller: NotificationController.self, category: ClipNotification.category)
    }
}

final class AppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        ClipNotification.registerCategory()
        AccountLink.shared.activate()
        Task { @MainActor in
            AppModel.shared.outbox.send()
            await AppModel.shared.requestNotifications()
        }
    }

    // Transcripts from the phone can arrive while the app is in the
    // background; the task stays open until they are in.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard let task = task as? WKWatchConnectivityRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }
            Task {
                while WCSession.default.hasContentPending {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await AppModel.shared.apnsTokenReceived(token) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Task { @MainActor in await AppModel.shared.refresh() }
        return [.banner, .list, .sound]
    }

    // Reply opens the sender's talk screen, and the title strip opens the
    // inbox, which has the clip at the top.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let clipID = ClipNotification.clipID(in: response.notification.request.content) else { return }
        switch response.actionIdentifier {
        case ClipNotification.replyAction:
            await AppModel.shared.reply(toClip: clipID)
        case UNNotificationDefaultActionIdentifier:
            await MainActor.run {
                AppModel.shared.talkPath = []
                AppModel.shared.showInbox = true
            }
        default:
            break
        }
    }
}
