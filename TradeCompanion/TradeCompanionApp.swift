import SwiftUI

@main
struct TradeCompanionApp: App {
    @State private var planner = TradePlannerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: planner)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)

        Settings {
            APISettingsView(model: planner)
        }
    }
}
