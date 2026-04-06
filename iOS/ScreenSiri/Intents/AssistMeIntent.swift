import AppIntents
import UIKit
import AVFoundation

// MARK: - AssistMeIntent
//
// The core App Intent that powers Siri and Shortcuts integration.
//
// Shortcut flow:
//   1. User says "Hey Siri, help me here" (or Back Tap triggers shortcut)
//   2. This intent fires
//   3. App opens briefly (or runs in background if session is already active)
//   4. Screen is captured (if session active), or user provides screenshot
//   5. AI responds via voice
//   6. App dismisses, user returns to what they were doing
//
// IMPORTANT: iOS does not allow App Intents to start screen recording.
// The session MUST already be active. The intent checks for this and
// opens the app to start a session if needed.

@available(iOS 16.0, *)
struct AssistMeIntent: AppIntent {

    static var title: LocalizedStringResource = "Ask About My Screen"
    static var description = IntentDescription(
        "Captures what's on your screen and lets you ask GPT-4o a question about it — then reads the answer aloud.",
        categoryName: "Screen Assistant"
    )

    // MARK: Parameters

    @Parameter(
        title: "Your Question",
        description: "What do you want to know? Leave blank to summarize the screen.",
        requestValueDialog: "What would you like to know about your screen?"
    )
    var question: String?

    // MARK: Paramater Summary (shown in Shortcuts editor)

    static var parameterSummary: some ParameterSummary {
        When(\.$question, .hasAnyValue) {
            Summary("Ask \(\.$question) about my screen")
        } otherwise: {
            Summary("Summarize my screen")
        }
    }

    // MARK: Perform

    @MainActor
    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let session = SessionManager.shared

        // Ensure session is active
        guard session.state.isActive else {
            throw IntentError.sessionNotActive
        }

        // Ensure we have a frame
        guard let frame = session.captureCurrentFrame() else {
            throw IntentError.noFrameAvailable
        }

        // Get or use provided query
        let finalQuery = question ?? "Briefly describe what's on my screen right now."

        // Update memory
        let memory = MemoryManager.shared
        memory.inferTask(from: finalQuery)
        memory.recordUserQuery(finalQuery)

        // Call AI
        let response = try await AIClient.shared.analyze(image: frame, query: finalQuery)

        // Update memory with response
        memory.recordAssistantResponse(response.guidance, aiResponse: response)

        // Speak the response
        await SpeechService.shared.speak(response.guidance)

        // Return value + dialog for Shortcuts
        return .result(
            value: response.guidance,
            dialog: IntentDialog(stringLiteral: response.guidance),
            view: IntentResultView(response: response.guidance)
        )
    }
}

// MARK: - SummarizeScreenIntent
// A simpler, no-parameter variant — ideal for Back Tap or one-tap shortcut

@available(iOS 16.0, *)
struct SummarizeScreenIntent: AppIntent {

    static var title: LocalizedStringResource = "Summarize My Screen"
    static var description = IntentDescription(
        "Instantly tells you what's on your screen — no question needed.",
        categoryName: "Screen Assistant"
    )

    @MainActor
    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let session = SessionManager.shared

        guard session.state.isActive else {
            throw IntentError.sessionNotActive
        }
        guard let frame = session.captureCurrentFrame() else {
            throw IntentError.noFrameAvailable
        }

        let response = try await AIClient.shared.analyze(
            image: frame,
            query: "What's on my screen? Give me a 1-2 sentence summary."
        )

        await SpeechService.shared.speak(response.guidance)

        return .result(
            value: response.guidance,
            dialog: IntentDialog(stringLiteral: response.guidance)
        )
    }
}

// MARK: - StartSessionIntent
// Lets users start the recording session via a Shortcut

@available(iOS 16.0, *)
struct StartSessionIntent: AppIntent {

    static var title: LocalizedStringResource = "Start ScreenSiri Session"
    static var description = IntentDescription(
        "Starts the screen capture session so the AI assistant can see your screen.",
        categoryName: "Screen Assistant"
    )

    // This intent needs to open the app since recording can't start from extension
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let session = SessionManager.shared

        if session.state.isActive {
            return .result(dialog: "Session is already active!")
        }

        do {
            try await session.startSession()
            return .result(dialog: "Session started. ScreenSiri is now watching your screen.")
        } catch {
            throw IntentError.couldNotStartSession
        }
    }
}

// MARK: - IntentError

enum IntentError: Error, LocalizedError {
    case sessionNotActive
    case noFrameAvailable
    case couldNotStartSession

    var errorDescription: String? {
        switch self {
        case .sessionNotActive:
            return "ScreenSiri session is not active. Open the app and tap 'Start Session' first, or add the 'Start ScreenSiri Session' shortcut before this one."
        case .noFrameAvailable:
            return "Could not capture the screen. Make sure the session is active and try again."
        case .couldNotStartSession:
            return "Could not start the screen session. Please open the app manually."
        }
    }
}

// MARK: - IntentResultView
// The snippet shown in the Shortcuts result bubble

@available(iOS 16.0, *)
struct IntentResultView: View {
    let response: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                )
            Text(response)
                .font(.body)
                .lineLimit(4)
        }
        .padding()
    }
}
