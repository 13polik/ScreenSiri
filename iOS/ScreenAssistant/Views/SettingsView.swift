import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    @EnvironmentObject var settings: AppSettings
    @State private var showResetAlert = false

    var body: some View {
        NavigationView {
            Form {
                // Backend Section
                Section(header: Text("AI Backend")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Backend URL")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("https://your-backend.com", text: $settings.backendURL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenAI API Key (fallback)")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        SecureField("sk-...", text: $settings.openAIKey)
                            .autocapitalization(.none)
                    }

                    Picker("Model", selection: $settings.selectedModel) {
                        Text("GPT-4o (Recommended)").tag("gpt-4o")
                        Text("GPT-4 Turbo").tag("gpt-4-turbo")
                        Text("GPT-4o Mini (Faster)").tag("gpt-4o-mini")
                    }
                }

                // Capture Section
                Section(header: Text("Screen Capture")) {
                    Picker("Quality", selection: $settings.captureQuality) {
                        ForEach(CaptureQuality.allCases) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                }

                // Voice Section
                Section(header: Text("Voice")) {
                    Toggle("Voice Responses", isOn: $settings.voiceEnabled)
                }

                // About Section
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                    Link("GitHub / Source Code", destination: URL(string: "https://github.com")!)
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                }

                // Danger Zone
                Section(header: Text("Danger Zone")) {
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label("Reset All Settings", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .alert("Reset Settings", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                settings.backendURL = ""
                settings.openAIKey  = ""
                settings.hasCompletedOnboarding = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all settings and restart onboarding.")
        }
    }
}
