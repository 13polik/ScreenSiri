import SwiftUI
import AppIntents

// MARK: - OnboardingView
// Shown once on first launch. Explains the app, requests permissions,
// and collects the API key / backend URL.

struct OnboardingView: View {

    @EnvironmentObject var settings: AppSettings
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomePage()
                .tag(0)

            PermissionsPage(onNext: { currentPage = 2 })
                .tag(1)

            ConfigPage(onDone: {
                settings.hasCompletedOnboarding = true
            })
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .ignoresSafeArea()
        .animation(.easeInOut, value: currentPage)
    }
}

// MARK: - WelcomePage

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "eye.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 12) {
                Text("ScreenSiri")
                    .font(.largeTitle.bold())

                Text("Your AI assistant that sees your screen and guides you — just like having a smart friend watching over your shoulder.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "eye.fill",        color: .blue,   title: "Sees Your Screen",    subtitle: "Uses screen recording you control")
                FeatureRow(icon: "brain",            color: .purple, title: "Powered by GPT-4o",   subtitle: "Understands context & remembers your session")
                FeatureRow(icon: "mic.fill",         color: .green,  title: "Voice First",         subtitle: "Ask questions and hear answers naturally")
                FeatureRow(icon: "bolt.fill",        color: .orange, title: "Works via Siri",      subtitle: "\"Hey Siri, help me here\" — that's all")
            }
            .padding(.horizontal)

            Spacer()

            Text("Swipe to continue →")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
        }
        .padding()
    }
}

// MARK: - PermissionsPage

struct PermissionsPage: View {
    var onNext: () -> Void
    @State private var micGranted     = false
    @State private var speechGranted  = false
    @State private var isRequesting   = false
    @State private var shortcutAdded  = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: [.green, .blue], startPoint: .top, endPoint: .bottom))

            VStack(spacing: 8) {
                Text("Permissions")
                    .font(.largeTitle.bold())
                Text("ScreenSiri needs a few permissions to work. You stay in control at all times.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 16) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "To hear your questions",
                    granted: micGranted
                )
                PermissionRow(
                    icon: "waveform",
                    title: "Speech Recognition",
                    subtitle: "To transcribe what you say",
                    granted: speechGranted
                )
                PermissionRow(
                    icon: "record.circle",
                    title: "Screen Recording",
                    subtitle: "Requested when you start a session — you see the red indicator",
                    granted: false,
                    isOptional: true
                )

                // ── Siri Shortcut row ──────────────────────────────────────────
                SiriShortcutRow(isAdded: $shortcutAdded)
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button(action: requestPermissions) {
                    HStack {
                        if isRequesting { ProgressView().tint(.white) }
                        Text(isRequesting ? "Requesting…" : "Grant Permissions")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(isRequesting)

                if micGranted && speechGranted {
                    Button("Continue →") { onNext() }
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .padding()
    }

    private func requestPermissions() {
        isRequesting = true
        Task {
            let granted = await SpeechService.shared.requestPermissions()
            await MainActor.run {
                micGranted    = granted
                speechGranted = granted
                isRequesting  = false
            }
        }
    }
}

// MARK: - SiriShortcutRow
// One-tap setup: registers App Shortcuts and opens the Shortcuts app
// so the user can verify / customise phrases immediately.

struct SiriShortcutRow: View {
    @Binding var isAdded: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "mic.circle.fill")
                .font(.title2)
                .foregroundColor(isAdded ? .green : .purple)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Siri & Shortcuts")
                        .font(.headline)
                    if isAdded {
                        Text("(added)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                Text("\"Hey Siri, help me here with ScreenSiri\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: addSiriShortcut) {
                Text(isAdded ? "Open" : "Add")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isAdded ? Color.green : Color.purple)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func addSiriShortcut() {
        // Refresh the App Shortcuts registry so Siri picks up the phrases immediately.
        if #available(iOS 16.4, *) {
            ScreenSiriShortcuts.updateAppShortcutParameters()
        }
        isAdded = true

        // Open Shortcuts so the user can see / customise their phrase right away.
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - ConfigPage

struct ConfigPage: View {
    var onDone: () -> Void
    @EnvironmentObject var settings: AppSettings
    @State private var backendURL = ""
    @State private var openAIKey  = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 60)

                Image(systemName: "server.rack")
                    .font(.system(size: 64))
                    .foregroundStyle(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))

                VStack(spacing: 8) {
                    Text("Connect to AI")
                        .font(.largeTitle.bold())
                    Text("Connect your backend (recommended) or enter an OpenAI key for quick testing.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 20) {

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Backend URL (Recommended)", systemImage: "server.rack")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("https://your-backend.com", text: $backendURL)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        Text("Deploy the included FastAPI backend and paste its URL here. Keeps your API key safe.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Label("OpenAI API Key (Quick Test)", systemImage: "key.fill")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        SecureField("sk-...", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                        Text("Direct key use — fine for testing, but not recommended for production. Never share this key.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                Button(action: saveAndContinue) {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canContinue ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .disabled(!canContinue)
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            backendURL = settings.backendURL
            openAIKey  = settings.openAIKey
        }
    }

    private var canContinue: Bool {
        !backendURL.isEmpty || !openAIKey.isEmpty
    }

    private func saveAndContinue() {
        settings.backendURL = backendURL
        settings.openAIKey  = openAIKey
        onDone()
    }
}

// MARK: - Sub-components

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let granted: Bool
    var isOptional: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(granted ? .green : .blue)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.headline)
                    if isOptional {
                        Text("(auto-requested)").font(.caption).foregroundColor(.orange)
                    }
                }
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
