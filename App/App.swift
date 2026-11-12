import SwiftUI
import AppCore
import BackgroundTasks
import UIKit
import UserNotifications

/// App delegate whose only job is the background-relaunch case: when iOS wakes the
/// app in the background to deliver new HealthKit data (no SwiftUI scene becomes
/// active), re-establish the movement observer so the inactivity nudge re-arms
/// against the user's real last movement, and run the throttled
/// `BackgroundRefresh` on that wake and on one infrequent `BGAppRefreshTask`.
/// In-app foreground/Settings paths are driven by `OtterpaceModel` via
/// `ContentView`; this covers the closed-app case.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var monitor: MovementActivityMonitor?
    private let pushRegistration = PushRegistrationService()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Never observe in a scenario/isolation capture, and only when the user has
        // turned on a reminder that depends on real data. The goal nudge counts
        // now: it is armed from a live step read rather than pre-scheduled, so a
        // goal-only user still needs this observer to wake the app.
        guard !HealthSource.isScenarioSeeded() else { return true }
        registerBackgroundRefresh()
        let settings = ReminderSettings.load()
        if settings.inactivityEnabled || settings.goalEnabled {
            // Each observer wake also runs the throttled background refresh, so the
            // cached dashboard and heartbeat ride a wake iOS already gives us.
            let monitor = MovementActivityMonitor(source: HealthSource.make(), scheduler: MovementReminderScheduler(),
                                                  onWake: { await BackgroundRefresh.run() })
            monitor.start(settings: settings)
            self.monitor = monitor
        }
        registerForPushIfEligible()
        return true
    }

    // MARK: Background refresh (one infrequent BGAppRefreshTask)

    /// Register the handler (must happen before launch finishes) and ask for the
    /// next run each time the app leaves the foreground.
    private func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundRefresh.taskIdentifier, using: nil) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            self?.handleBackgroundRefresh(task)
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.scheduleBackgroundRefresh()
        }
    }

    /// Request the next run no sooner than `RefreshPolicy.backgroundTaskSpacing`
    /// (4h). iOS treats it as a floor and applies its own budget; submitting again
    /// replaces any pending request rather than stacking them.
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundRefresh.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: RefreshPolicy.backgroundTaskSpacing)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()   // keep exactly one future run queued
        let work = Task { @MainActor in
            await BackgroundRefresh.run()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        // Out of time: stop and report; the next scheduled run picks it up.
        task.expirationHandler = { work.cancel() }
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
