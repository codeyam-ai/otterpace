import SwiftUI
import AppCore
import UIKit

/// App delegate whose only job is the background-relaunch case: when iOS wakes the
/// app in the background to deliver new HealthKit data (no SwiftUI scene becomes
/// active), re-establish the movement observer so the inactivity nudge re-arms
/// against the user's real last movement. In-app foreground/Settings paths are
/// driven by `OtterpaceModel` via `ContentView`; this covers the closed-app case.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var monitor: MovementActivityMonitor?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Never observe in a scenario/isolation capture, and only when the user has
        // turned the inactivity reminder on.
        guard !HealthSource.isScenarioSeeded() else { return true }
        let settings = ReminderSettings.load()
        guard settings.inactivityEnabled else { return true }
        let monitor = MovementActivityMonitor(source: HealthSource.make(), scheduler: MovementReminderScheduler())
        monitor.start(settings: settings)
        self.monitor = monitor
        return true
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
            (CodeyamIsolationHost.root() ?? AnyView(ContentView()))
                .preferredColorScheme(.light)
        }
    }
}
