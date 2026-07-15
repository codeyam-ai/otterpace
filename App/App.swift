import SwiftUI
import AppCore
import UIKit
import UserNotifications

/// App delegate whose only job is the background-relaunch case: when iOS wakes the
/// app in the background to deliver new HealthKit data (no SwiftUI scene becomes
/// active), re-establish the movement observer so the inactivity nudge re-arms
/// against the user's real last movement. In-app foreground/Settings paths are
/// driven by `OtterpaceModel` via `ContentView`; this covers the closed-app case.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var monitor: MovementActivityMonitor?
    private let pushRegistration = PushRegistrationService()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Never observe in a scenario/isolation capture, and only when the user has
        // turned the inactivity reminder on.
        guard !HealthSource.isScenarioSeeded() else { return true }
        let settings = ReminderSettings.load()
        if settings.inactivityEnabled {
            let monitor = MovementActivityMonitor(source: HealthSource.make(), scheduler: MovementReminderScheduler())
            monitor.start(settings: settings)
            self.monitor = monitor
        }
        registerForPushIfEligible()
        return true
    }

    /// Ask iOS for an APNs token only when server push is opted into: signed in,
    /// health sync on, and the OS notification permission already granted. The
    /// token lands in `didRegisterForRemoteNotificationsWithDeviceToken` below,
    /// which registers it with the backend. Any gate off → we never register, so
    /// the on-device nudge (prerequisite plan) stays the only reminder.
    func registerForPushIfEligible() {
        guard AccountSessionStore().token() != nil, SyncConsentStore().healthSyncEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await pushRegistration.register(deviceToken: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Best-effort: leave server push off; the on-device nudge still works.
    }
}

@main
struct SwiftUIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            // Otterpace is a light-only design (cream/coral Palette). Pin the
            // color scheme so system surfaces (TabView, SecureField, scroll
            // backgrounds, default Text) never flip dark on a Dark Mode device.
            //
            // In component-isolation captures the launch env selects a single
            // view via CodeyamIsolationHost; otherwise the app boots normally.
            // ThemedAppRoot owns the selected theme, injects it, and pins the
            // color scheme to the theme (light for Default/Fieldnote/Garden,
            // dark for Bolt/Orbit) so system chrome matches the painted surfaces.
            ThemedAppRoot {
                CodeyamIsolationHost.root() ?? AnyView(ContentView())
            }
        }
    }
}
