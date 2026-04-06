import Foundation

// MARK: - ChatMessage
// A single turn in the assistant chat conversation.
// Stored as a value type so @Published array mutations trigger SwiftUI updates.

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date()) {
        self.id        = id
        self.role      = role
        self.content   = content
        self.timestamp = timestamp
    }
}

enum ChatRole: Equatable {
    case user
    case assistant
}
