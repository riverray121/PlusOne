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
                    if phase == .active {
                        SessionManager.shared.endExpiredSessions()
                        appState.refresh()
                        if appState.pendingUnlock != nil {
                            appState.showCapture = true
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .plusOneOpenCapture)) { _ in
                    appState.refresh()
                    appState.showCapture = true
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
        .sheet(isPresented: $appState.showCapture) {
            CaptureView()
        }
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
