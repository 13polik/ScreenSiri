import Foundation
import Combine

// MARK: - MemoryManager
//
// Manages the in-memory session state across multiple interactions.
// For MVP this is purely in-memory (reset on app kill).
// Future: persist to CoreData / CloudKit.

@MainActor
final class MemoryManager: ObservableObject {

    static let shared = MemoryManager()

    // MARK: Published

    @Published private(set) var memory = SessionMemory()
    @Published private(set) var interactionCount: Int = 0

    private init() {}

    // MARK: - Public API

    /// Call this after every user question is sent
    func recordUserQuery(_ query: String) {
        memory.addTurn(role: .user, content: query)
        interactionCount += 1
    }

    /// Call this after every AI response is received
    func recordAssistantResponse(_ response: String, aiResponse: AIResponse) {
        memory.addTurn(role: .assistant, content: response)
        memory.update(from: aiResponse)
    }

    /// Infers the user's current task from query (lightweight heuristic)
    func inferTask(from query: String) {
        let lowercased = query.lowercased()
        let taskKeywords: [String: String] = [
            "book": "Booking",
            "buy": "Shopping",
            "send": "Messaging",
            "search": "Searching",
            "find": "Searching",
            "play": "Media",
            "navigate": "Navigation",
            "call": "Calling",
            "open": "App Navigation",
            "share": "Sharing"
        ]
        for (keyword, taskName) in taskKeywords {
            if lowercased.contains(keyword) {
                memory.setTask(taskName)
                return
            }
        }
    }

    /// Updates the last screen summary from a quick Gemini pass
    func updateScreenContext(_ summary: String) {
        memory.lastScreenSummary = summary
    }

    /// Marks what the user just did (for context continuity)
    func recordUserAction(_ action: String) {
        memory.updateLastAction(action)
    }

    /// Resets session — call when user explicitly starts a new session
    func resetSession() {
        memory.reset()
        interactionCount = 0
    }

    // MARK: - Serialization

    /// Returns memory dict ready to attach to API request
    func memoryPayload() -> [String: Any] {
        memory.toDict()
    }

    // MARK: - Computed Helpers

    var hasContext: Bool {
        memory.task != nil || !memory.conversationHistory.isEmpty
    }

    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(memory.startedAt)
    }

    var lastFewTurns: [ConversationTurn] {
        Array(memory.conversationHistory.suffix(6))
    }
}
