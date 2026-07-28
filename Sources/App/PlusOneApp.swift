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
                    // Foreground pass: expire lapsed sessions and surface any
                    // unlock request written by the shield action extension.
                    // refresh() opens the capture flow when a request exists.
                    if phase == .active {
                        SessionManager.shared.endExpiredSessions()
                        // Settings changed in older builds can leave stale
                        // store state; re-assert current policy.
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
            #if LITE
            // Lite build: no Screen Time, so onboarding has nothing to set up.
            HomeView()
            #else
            if appState.onboarded {
                HomeView()
            } else {
                OnboardingView()
            }
            #endif
        }
        #if LITE
        .sheet(isPresented: $appState.showCapture) {
            CaptureView(target: nil)
        }
        #else
        .sheet(item: $appState.captureRequest, onDismiss: { appState.captureDidDismiss() }) { request in
            CaptureView(target: request.target)
        }
        #endif
    }
}

extension Notification.Name {
    static let plusOneOpenCapture = Notification.Name("plusOneOpenCapture")
}

// Routes unlock-notification taps into the capture flow.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
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
