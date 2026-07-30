import SwiftUI
import UserNotifications

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
                    // Foreground pass: end lapsed sessions and clear expired
                    // limits, then re-apply shields, since clearing an
                    // exhausted limit changes what should be shielded.
                    // refresh() surfaces an unlock request written by the
                    // shield action extension.
                    if phase == .active {
                        SessionManager.shared.endExpiredSessions()
                        TimeLimitManager.shared.clearLapsedExhausted()
                        SessionManager.shared.refreshShields()
                        appState.refresh()
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

// Routes unlock-notification taps into the capture flow.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
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

    // Show the unlock notification even if PlusOne is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
