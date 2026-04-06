import Foundation
import Combine
import AVFoundation
import UIKit

// MARK: - InteractionManager
//
// Orchestrates the full interaction loop:
//   1. User triggers (voice / shortcut / tap)
//   2. Capture current frame
//   3. Listen for user's question (or use default)
//   4. Send to AI
//   5. Speak response
//   6. Update memory
//   7. Dismiss UI, return user to their app

@MainActor
final class InteractionManager: ObservableObject {

    static let shared = InteractionManager()

    // MARK: Dependencies

    private let session   = SessionManager.shared
    private let memory    = MemoryManager.shared
    private let speech    = SpeechService.shared
    private let ai        = AIClient.shared

    // MARK: Published State

    @Published private(set) var phase: InteractionPhase = .idle
    @Published private(set) var lastResponse: String?
    @Published private(set) var lastError: String?
    @Published var isAssistantVisible: Bool = false

    /// Chat history shown in the overlay bubble list
    @Published private(set) var messages: [ChatMessage] = []
    /// True while a streaming response is being received
    @Published private(set) var isStreaming: Bool = false

    private init() {}

    // MARK: - Main Entry Point

    /// Called from the App Intent, Back Tap, or in-app button.
    /// `query`: if nil, we listen for speech first.
    func handleInteraction(query: String? = nil) async {
        guard session.state.isActive else {
            lastError = "Session is not active. Start the session first."
            return
        }

        phase = .capturing
        isAssistantVisible = true

        // 1. Grab the current frame
        guard let frame = session.captureCurrentFrame() else {
            lastError = SessionError.noFrameAvailable.localizedDescription
            phase = .idle
            return
        }

        // 2. Get or listen for query
        let finalQuery: String
        if let providedQuery = query, !providedQuery.isEmpty {
            finalQuery = providedQuery
        } else {
            phase = .listening
            do {
                finalQuery = try await speech.listenForQuestion(timeout: 8.0)
            } catch {
                // If no speech detected, fall back to summarize
                finalQuery = "What's on my screen right now? Give me a brief summary."
            }
        }

        // 3. Infer task context from query
        memory.inferTask(from: finalQuery)
        memory.recordUserQuery(finalQuery)
        messages.append(ChatMessage(role: .user, content: finalQuery))

        // 4. Call AI
        phase = .thinking
        do {
            let response = try await ai.analyze(image: frame, query: finalQuery)

            // 5. Update memory + messages
            memory.recordAssistantResponse(response.guidance, aiResponse: response)
            lastResponse = response.guidance
            messages.append(ChatMessage(role: .assistant, content: response.guidance))

            // 6. Speak response
            phase = .speaking
            await speech.speak(response.guidance)

            phase = .idle

            // 7. Auto-dismiss after speaking
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            isAssistantVisible = false

        } catch {
            lastError = error.localizedDescription
            phase = .error
            messages.append(ChatMessage(role: .assistant, content: "Sorry, something went wrong."))
            await speech.speak("Sorry, I encountered an error.")
            isAssistantVisible = false
        }
    }

    /// Quick screen summary — no voice question, just describe what's visible
    func summarizeScreen() async {
        await handleInteraction(query: "Briefly describe what's on my screen right now. Be concise.")
    }

    // MARK: - Text Input Path

    /// Sends a typed message, streams tokens into the `messages` array.
    /// Works with or without an active screen session.
    func sendTextMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        messages.append(ChatMessage(role: .user, content: trimmed))
        isAssistantVisible = true
        phase = .thinking
        isStreaming = true

        memory.inferTask(from: trimmed)
        memory.recordUserQuery(trimmed)

        // Optionally attach the current frame if a screen session is active
        let frame = session.state.isActive ? session.captureCurrentFrame() : nil

        // Append a placeholder assistant message; we'll fill it token by token
        messages.append(ChatMessage(role: .assistant, content: ""))
        let assistantIndex = messages.count - 1

        do {
            for try await token in ai.analyzeStreaming(image: frame, query: trimmed) {
                messages[assistantIndex].content += token
            }
            isStreaming = false
            let finalContent = messages[assistantIndex].content

            memory.recordAssistantResponse(finalContent, aiResponse: AIResponse(
                guidance: finalContent,
                screenSummary: nil,
                currentStep: nil,
                nextExpectedAction: nil,
                confidence: nil
            ))
            lastResponse = finalContent

            if AppSettings.shared.voiceEnabled {
                phase = .speaking
                await speech.speak(finalContent)
            }
            phase = .idle

        } catch {
            isStreaming = false
            messages[assistantIndex].content = "Sorry, something went wrong."
            lastError = error.localizedDescription
            phase = .error
        }
    }

    // MARK: - Clear chat history

    func clearMessages() {
        messages = []
    }

    /// Stop current interaction (e.g., user taps dismiss)
    func cancel() {
        speech.stopSpeaking()
        isStreaming = false
        phase = .idle
        isAssistantVisible = false
    }
}

// MARK: - InteractionPhase

enum InteractionPhase: Equatable {
    case idle
    case capturing
    case listening
    case thinking
    case speaking
    case error

    var displayText: String {
        switch self {
        case .idle:      return "Ready"
        case .capturing: return "Reading screen…"
        case .listening: return "Listening…"
        case .thinking:  return "Thinking…"
        case .speaking:  return "Speaking…"
        case .error:     return "Something went wrong"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:      return "mic.fill"
        case .capturing: return "camera.fill"
        case .listening: return "waveform"
        case .thinking:  return "brain"
        case .speaking:  return "speaker.wave.3.fill"
        case .error:     return "exclamationmark.triangle.fill"
        }
    }

    var isWorking: Bool {
        self == .capturing || self == .thinking
    }
}
