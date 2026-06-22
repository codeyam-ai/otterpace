import SwiftUI

// Root of the RunBuddy app. Reads the seeded `TodayState` at launch and shows
// either the day-one "Connect Apple Health" hero (production default) or the
// full Today dashboard once activity data is available.

public struct ContentView: View {
    @StateObject private var model = RunBuddyModel()

    // Scenario-only override: when a preview scenario seeds `rbPreviewMode`, the
    // app renders the Buddy style/loader showcase instead of the normal flow.
    private let previewMode = UserDefaults.standard.string(forKey: "rbPreviewMode") ?? ""

    // Which tab is selected at launch. Scenarios seed `rbStartTab="coach"` to land
    // directly on the Ask Coach chat; default (and production) opens on Today.
    @State private var tab: MainTab

    public init() {
        let seeded = UserDefaults.standard.string(forKey: "rbStartTab") ?? ""
        _tab = State(initialValue: MainTab(raw: seeded))
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.bgTop, Palette.bgBottom],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if !previewMode.isEmpty {
                BuddyPreviewHost(mode: previewMode)
            } else if model.today.healthKitConnected {
                connectedTabs
            } else {
                ConnectHero(onConnect: { model.connect() })
            }
        }
    }

    // Today + Ask Coach behind a bottom tab bar. The Coach card on Today also
    // jumps here by flipping `tab` to `.coach`.
    private var connectedTabs: some View {
        TabView(selection: $tab) {
            TodayDashboard(model: model, onAskCoach: { tab = .coach })
                .tag(MainTab.today)
                .tabItem { Label("Today", systemImage: "sun.max.fill") }

            AskCoachView(model: model)
                .tag(MainTab.coach)
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right.fill") }
        }
        .tint(Palette.brand)
    }
}

// The app's two top-level destinations.
public enum MainTab: String, Hashable {
    case today, coach

    public init(raw: String) {
        self = MainTab(rawValue: raw.lowercased()) ?? .today
    }
}
