import SwiftUI

/// Top-level tab shell. Three destinations, no clutter — matches the mockup.
struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Tonight", systemImage: "moon.stars") }

            WakeSequenceView()
                .tabItem { Label("Wake", systemImage: "sun.horizon") }

            DashboardView()
                .tabItem { Label("Insights", systemImage: "chart.bar") }
        }
        .background(Theme.night0.ignoresSafeArea())
    }
}
