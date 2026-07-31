import SwiftUI
import UserNotifications
import CloudKit

@main
struct PlusOneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onChange(of: scenePhase) { phase in
                    // Shields are re-applied only after due changes, lapsed
                    // sessions and expired limits land, since each of those
                    // changes what should be shielded. refresh() then surfaces
                    // an unlock request written by the shield action extension.
                    if phase == .active {
                        ProtectionGate.shared.applyDue()
                        SessionManager.shared.endExpiredSessions()
                        TimeLimitManager.shared.clearLapsedExhausted()
                        SessionManager.shared.refreshShields()
                        appState.refresh()
                        Task { await FriendSync.shared.sync() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .plusOneOpenCapture)) { _ in
                    appState.refresh()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.onboarded {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .sheet(item: $appState.captureRequest, onDismiss: { appState.captureDidDismiss() }) { request in
            CaptureView(target: request.target)
        }
    }
}

extension Notification.Name {
    static let plusOneOpenCapture = Notification.Name("plusOneOpenCapture")
}

// Routes unlock-notification taps into the capture flow, CloudKit pushes
// into FriendSync, and share acceptance into the companion pairing flow.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Silent registration (no user prompt); CloudKit subscription pushes
        // need it on both sides of a pairing.
        application.registerForRemoteNotifications()
        return true
    }

    // The share-acceptance callback only reaches a scene delegate, so one is
    // injected here; SwiftUI keeps managing the window.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let handled = await FriendSync.shared.handleRemoteNotification(userInfo)
            completionHandler(handled ? .newData : .noData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == AppGroup.unlockNotificationId {
            NotificationCenter.default.post(name: .plusOneOpenCapture, object: nil)
        }
        completionHandler()
    }

    // Unlock prompts and limit warnings are worth seeing while PlusOne is
    // open, so foregrounded notifications present instead of being suppressed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            FriendSync.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }
}
