// ZurufPhoneApp.swift
// Phone
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import UserNotifications

@main
struct ZurufPhoneApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
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
                    clipsChanged(clips)
                }
            }
            .onChange(of: model.account == nil) { _, signedOut in
                if signedOut {
                    UNUserNotificationCenter.current().setBadgeCount(0)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }
}

// Transcribes new clips and sets the badge to the unplayed count, whether the
// list changed in the app or after a notification woke it.
@MainActor
private func clipsChanged(_ clips: ClipList) {
    Transcripts.shared.update(for: clips)
    UNUserNotificationCenter.current().setBadgeCount(clips.received.filter { $0.playedAt == nil }.count)
}

// Every clip's notification comes to this phone, which iOS shows here or
// passes to the watch.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        ClipNotification.registerCategory()
        // Saving again moves an account kept before the shared Keychain group
        // into it, where the notification service extension can read it.
        if let account = AccountStore.load() {
            try? AccountStore.save(account)
        }
        AccountLink.shared.activate()
        Task { @MainActor in
            AppModel.shared.outbox.send()
            await AppModel.shared.requestNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await AppModel.shared.apnsTokenReceived(token) }
    }

    // A notification woke the app: fetch the new clip and transcribe it before
    // iOS suspends the app again. The completion handler form, because the
    // async one hands the non-Sendable payload across actors.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            completionHandler(await catchUp())
        }
    }

    private func catchUp() async -> UIBackgroundFetchResult {
        await AppModel.shared.refresh()
        guard let clips = AppModel.shared.clips else { return .failed }
        clipsChanged(clips)
        await Transcripts.shared.finish()
        return .newData
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Task { @MainActor in await AppModel.shared.refresh() }
        return [.banner, .list, .sound]
    }

    // Tapping a clip's alert opens its conversation, where it can be played
    // and answered.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let clipID = ClipNotification.clipID(in: response.notification.request.content) else { return }
        await AppModel.shared.reply(toClip: clipID)
    }
}
