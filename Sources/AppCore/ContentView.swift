import SwiftUI

// Root of the RunBuddy app. Reads the seeded `TodayState` at launch and shows
// either the day-one "Connect Apple Health" hero (production default) or the
// full Today dashboard once activity data is available.

public struct ContentView: View {
    @StateObject private var model = RunBuddyModel()

    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.bgTop, Palette.bgBottom],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if model.today.healthKitConnected {
                TodayDashboard(model: model)
            } else {
                ConnectHero(onConnect: { model.connect() })
            }
        }
    }
}
