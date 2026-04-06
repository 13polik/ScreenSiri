import SwiftUI

// MARK: - AssistantPanelView
//
// Full-screen overlay that feels like a Siri-style sheet:
//   - Blurred, dimmed background of the captured screen (or solid dark fallback)
//   - A bottom panel that expands as a conversation grows
//   - Scrollable chat bubble list (user right / assistant left)
//   - Text input bar with send + voice buttons — auto-focused on appear
//   - Compact animated orb + status in the header

struct AssistantPanelView: View {

    @EnvironmentObject var interaction: InteractionManager
    @EnvironmentObject var sessionManager: SessionManager

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private var hasChatContent: Bool { !interaction.messages.isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundLayer
            panelLayer
        }
        .ignoresSafeArea()
        .onAppear {
            // Small delay lets the spring animation settle first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isInputFocused = true
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if let frame = sessionManager.captureCurrentFrame() {
            Image(uiImage: frame)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .blur(radius: 20)
                .overlay(Color.black.opacity(0.4))
        } else {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
        }
    }

    // MARK: - Panel

    private var panelLayer: some View {
        VStack(spacing: 0) {
            headerBar

            if hasChatContent {
                messageList
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .opacity
                    ))
            }

            inputBar
        }
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: hasChatContent)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Miniature voice orb
            MiniOrb(phase: interaction.phase)

            Text(interaction.phase.displayText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .animation(.easeInOut(duration: 0.2), value: interaction.phase)

            Spacer()

            if hasChatContent {
                Button(action: { interaction.clearMessages() }) {
                    Image(systemName: "trash")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, hasChatContent ? 8 : 18)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(interaction.messages) { message in
                        let isLastAssistant = message == interaction.messages.last
                            && message.role == .assistant
                        ChatBubble(
                            message: message,
                            showTyping: isLastAssistant && interaction.isStreaming
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 300)
            .onChange(of: interaction.messages) { msgs in
                guard let last = msgs.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask anything…", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .font(.body)
                .foregroundColor(.primary)
                .tint(.blue)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit { sendMessage() }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.15))
                )

            // Voice button
            Button(action: startVoiceInput) {
                Image(systemName: interaction.phase == .listening
                    ? "waveform.circle.fill"
                    : "mic.circle.fill")
                    .font(.title2)
                    .foregroundColor(interaction.phase == .listening ? .green : .white.opacity(0.8))
                    .symbolEffect(.pulse, isActive: interaction.phase == .listening)
            }
            .disabled(interaction.isStreaming)

            // Send button — fades in when there is text
            if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .disabled(interaction.isStreaming)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await interaction.sendTextMessage(text) }
    }

    private func startVoiceInput() {
        Task { await interaction.handleInteraction() }
    }

    private func dismiss() {
        isInputFocused = false
        interaction.cancel()
    }
}

// MARK: - ChatBubble

struct ChatBubble: View {
    let message: ChatMessage
    let showTyping: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user { Spacer(minLength: 48) }

            Group {
                if showTyping && message.content.isEmpty {
                    TypingIndicator()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(message.role == .user ? .white : .white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(bubbleFill)
            )

            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var bubbleFill: AnyShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.blue, Color.indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(Color.white.opacity(0.14))
        }
    }
}

// MARK: - TypingIndicator
// Three-dot bounce animation shown while the assistant is thinking/streaming

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 7, height: 7)
                    .offset(y: animating ? -5 : 0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.14),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - MiniOrb
// Compact version of VoiceOrb used in the panel header

struct MiniOrb: View {
    let phase: InteractionPhase
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(orbColor)
            .frame(width: 10, height: 10)
            .scaleEffect(pulsing && shouldPulse ? 1.4 : 1.0)
            .animation(
                shouldPulse
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
            .onAppear { pulsing = true }
            .onChange(of: phase) { _ in pulsing = true }
    }

    private var orbColor: Color {
        switch phase {
        case .idle:      return .gray
        case .capturing: return .blue
        case .listening: return .green
        case .thinking:  return .purple
        case .speaking:  return .orange
        case .error:     return .red
        }
    }

    private var shouldPulse: Bool { phase != .idle && phase != .error }
}

// MARK: - VoiceOrb (kept for backwards compat / other uses)

struct VoiceOrb: View {

    let phase: InteractionPhase
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(orbColor.opacity(Double(3 - i) * 0.1), lineWidth: 2)
                    .frame(width: CGFloat(80 + i * 24), height: CGFloat(80 + i * 24))
                    .scaleEffect(isAnimating && shouldPulse ? 1.0 + CGFloat(i) * 0.08 : 1.0)
                    .animation(
                        shouldPulse
                            ? .easeInOut(duration: 0.8 + Double(i) * 0.2).repeatForever(autoreverses: true)
                            : .default,
                        value: isAnimating
                    )
            }
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColor.opacity(0.9), orbColor.opacity(0.5)],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 45
                    )
                )
                .frame(width: 80, height: 80)
                .scaleEffect(isAnimating && shouldPulse ? 1.05 : 1.0)
                .animation(
                    shouldPulse
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: isAnimating
                )
            Image(systemName: phase.systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.degrees(phase.isWorking && isAnimating ? 360 : 0))
                .animation(
                    phase.isWorking
                        ? .linear(duration: 2).repeatForever(autoreverses: false)
                        : .default,
                    value: isAnimating
                )
        }
        .onAppear { isAnimating = true }
        .onChange(of: phase) { _ in isAnimating = true }
    }

    private var orbColor: Color {
        switch phase {
        case .idle:      return .gray
        case .capturing: return .blue
        case .listening: return .green
        case .thinking:  return .purple
        case .speaking:  return .orange
        case .error:     return .red
        }
    }

    private var shouldPulse: Bool { phase != .idle && phase != .error }
}
