import SwiftUI

// MARK: - ContentView
// The main shell after onboarding. Contains tab navigation
// and the always-present AssistantPanel overlay.

struct ContentView: View {

    @EnvironmentObject var interaction: InteractionManager

    var body: some View {
        ZStack {
            // Main tab navigation
            TabView {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }

                HistoryView()
                    .tabItem { Label("History", systemImage: "clock.fill") }

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .tint(.blue)

            // Overlay assistant panel — appears during interactions
            if interaction.isAssistantVisible {
                AssistantPanelView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(99)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: interaction.isAssistantVisible)
            }
        }
    }
}
