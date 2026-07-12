import SwiftUI

/// Top-level tab shell: Home · History · Insights. Onboarding covers everything on
/// first launch until the user sets a deadline + wake speed.
struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            DashboardView()
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
        }
        .background(Theme.night0.ignoresSafeArea())
        .fullScreenCover(isPresented: $showOnboarding) { OnboardingView() }
        .onAppear { showOnboarding = !app.hasOnboarded }
    }
}
