import SwiftUI

// MARK: - HomeView
// The main dashboard. Shows session status, quick actions,
// and a prominent "Start Session" CTA.

struct HomeView: View {

    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var memory: MemoryManager
    @EnvironmentObject var interaction: InteractionManager

    @State private var showError   = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // Session Status Card
                    SessionStatusCard()

                    // Quick Actions
                    if sessionManager.state.isActive {
                        QuickActionsGrid()
                    }

                    // Session Context (if active)
                    if memory.hasContext && sessionManager.state.isActive {
                        ContextCard()
                    }

                    // Shortcut Setup Tip
                    ShortcutTipCard()

                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("ScreenSiri")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - SessionStatusCard

struct SessionStatusCard: View {

    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 16) {

            // Status indicator
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(statusColor.opacity(0.3), lineWidth: 4)
                            .scaleEffect(sessionManager.state.isActive ? 1.5 : 1.0)
                            .animation(sessionManager.state.isActive ?
                                .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default,
                                value: sessionManager.state.isActive)
                    )
                Text(sessionManager.state.displayName)
                    .font(.headline)
                Spacer()
            }

            // CTA Button
            Button(action: toggleSession) {
                HStack {
                    Image(systemName: sessionManager.state.isActive ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                    Text(sessionManager.state.isActive ? "End Session" : "Start Session")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(sessionManager.state.isActive ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .disabled(sessionManager.state == .starting || sessionManager.state == .stopping)

            if sessionManager.state.isActive {
                HStack {
                    Image(systemName: "record.circle").foregroundColor(.red).font(.caption)
                    Text("Screen recording is active — the red dot in the status bar is normal.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    private var statusColor: Color {
        switch sessionManager.state {
        case .active:   return .green
        case .starting: return .orange
        case .error:    return .red
        default:        return .gray
        }
    }

    private func toggleSession() {
        Task {
            if sessionManager.state.isActive {
                await sessionManager.stopSession()
                MemoryManager.shared.resetSession()
            } else {
                do {
                    try await sessionManager.startSession()
                } catch {
                    // Error is surfaced via sessionManager.errorMessage
                }
            }
        }
    }
}

// MARK: - QuickActionsGrid

struct QuickActionsGrid: View {

    @EnvironmentObject var interaction: InteractionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {

                QuickActionButton(
                    icon: "mic.fill",
                    title: "Ask a Question",
                    color: .blue
                ) {
                    Task { await interaction.handleInteraction() }
                }

                QuickActionButton(
                    icon: "eye.fill",
                    title: "Summarize Screen",
                    color: .purple
                ) {
                    Task { await interaction.summarizeScreen() }
                }

                QuickActionButton(
                    icon: "arrow.right.circle.fill",
                    title: "Next Step",
                    color: .green
                ) {
                    Task {
                        await interaction.handleInteraction(
                            query: "What should I do next?"
                        )
                    }
                }

                QuickActionButton(
                    icon: "questionmark.circle.fill",
                    title: "What Is This?",
                    color: .orange
                ) {
                    Task {
                        await interaction.handleInteraction(
                            query: "What is on my screen? Explain it briefly."
                        )
                    }
                }
            }
        }
    }
}

// MARK: - ContextCard

struct ContextCard: View {
    @EnvironmentObject var memory: MemoryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Session Context", systemImage: "brain")
                .font(.headline)

            if let task = memory.memory.task {
                ContextRow(label: "Task", value: task)
            }
            if let step = memory.memory.currentStep {
                ContextRow(label: "Step", value: step)
            }
            if let next = memory.memory.nextExpectedAction {
                ContextRow(label: "Next", value: next)
            }

            Text("\(memory.interactionCount) interactions this session")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

// MARK: - ShortcutTipCard

struct ShortcutTipCard: View {
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Set Up Siri Shortcut", systemImage: "mic.circle.fill")
                    .font(.headline)
                Spacer()
                Button(showDetails ? "Hide" : "How?") {
                    withAnimation { showDetails.toggle() }
                }
                .font(.caption.bold())
                .foregroundColor(.blue)
            }

            Text("Say \"Hey Siri, help me here\" to trigger the assistant from any app.")
                .font(.body)
                .foregroundColor(.secondary)

            if showDetails {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text("Setup Steps:")
                        .font(.caption.bold())
                    StepLabel(number: "1", text: "Open the Shortcuts app")
                    StepLabel(number: "2", text: "Tap + → Search "ScreenSiri"")
                    StepLabel(number: "3", text: "Add "Assist Me" shortcut")
                    StepLabel(number: "4", text: "Assign a Siri phrase like "help me here"")
                    StepLabel(number: "5", text: "For Back Tap: Settings → Accessibility → Touch → Back Tap")
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.08), Color.purple.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Sub-components

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(14)
        }
    }
}

struct ContextRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.caption)
        }
    }
}

struct StepLabel: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Color.blue)
                .clipShape(Circle())
            Text(text)
                .font(.caption)
        }
    }
}

// MARK: - HistoryView (placeholder)

struct HistoryView: View {
    @EnvironmentObject var memory: MemoryManager

    var body: some View {
        NavigationView {
            Group {
                if memory.memory.conversationHistory.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No interactions yet")
                            .font(.headline)
                        Text("Start a session and ask the assistant something.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List(memory.lastFewTurns) { turn in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(turn.role == .user ? "You" : "Assistant")
                                .font(.caption.bold())
                                .foregroundColor(turn.role == .user ? .blue : .purple)
                            Text(turn.content)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}
