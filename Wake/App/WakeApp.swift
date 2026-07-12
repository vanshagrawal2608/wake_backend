import SwiftUI

@main
struct WakeApp: App {
    // Single source of truth, injected into the environment.
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)   // Wake commits to the night world
                .tint(Theme.accent)
        }
    }
}
