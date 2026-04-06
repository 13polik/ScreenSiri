import SwiftUI

@main
struct ScreenSiriApp: App {

    @StateObject private var settings       = AppSettings.shared
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var interaction    = InteractionManager.shared
    @StateObject private var memory         = MemoryManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(sessionManager)
                .environmentObject(interaction)
                .environmentObject(memory)
        }
    }
}

// MARK: - RootView
// Decides whether to show Onboarding or the main app

struct RootView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if !settings.hasCompletedOnboarding {
            OnboardingView()
        } else {
            ContentView()
        }
    }
}
