import Foundation

// MARK: - SessionMemory
// The memory object passed to the AI with every request.
// Keeps track of what the user is doing across multiple interactions.

struct SessionMemory: Codable {

    // MARK: Properties

    var task: String?
    var currentStep: String?
    var lastScreenSummary: String?
    var lastUserAction: String?
    var nextExpectedAction: String?
    var conversationHistory: [ConversationTurn]
    var sessionID: String
    var startedAt: Date
    var updatedAt: Date

    // MARK: Init

    init() {
        self.sessionID            = UUID().uuidString
        self.startedAt            = Date()
        self.updatedAt            = Date()
        self.conversationHistory  = []
    }

    // MARK: Mutation helpers

    mutating func addTurn(role: ConversationRole, content: String) {
        let turn = ConversationTurn(role: role, content: content, timestamp: Date())
        conversationHistory.append(turn)
        // Keep last 20 turns to avoid token explosion
        if conversationHistory.count > 20 {
            conversationHistory.removeFirst(conversationHistory.count - 20)
        }
        updatedAt = Date()
    }

    mutating func update(from response: AIResponse) {
        self.currentStep          = response.currentStep ?? currentStep
        self.lastScreenSummary    = response.screenSummary
        self.nextExpectedAction   = response.nextExpectedAction
    }

    mutating func updateLastAction(_ action: String) {
        self.lastUserAction = action
        self.updatedAt = Date()
    }

    mutating func setTask(_ newTask: String) {
        if task == nil || task != newTask {
            task = newTask
            currentStep = nil
            nextExpectedAction = nil
        }
    }

    /// Resets the memory for a brand new session
    mutating func reset() {
        task                = nil
        currentStep         = nil
        lastScreenSummary   = nil
        lastUserAction      = nil
        nextExpectedAction  = nil
        conversationHistory = []
        sessionID           = UUID().uuidString
        startedAt           = Date()
        updatedAt           = Date()
    }

    // MARK: Serialization

    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "session_id": sessionID,
            "conversation_history": conversationHistory.map {
                ["role": $0.role.rawValue, "content": $0.content]
            }
        ]
        if let task         = task         { dict["task"] = task }
        if let step         = currentStep  { dict["current_step"] = step }
        if let summary      = lastScreenSummary  { dict["last_screen_summary"] = summary }
        if let action       = lastUserAction     { dict["last_action"] = action }
        if let next         = nextExpectedAction { dict["next_expected_action"] = next }
        return dict
    }
}

// MARK: - ConversationTurn

struct ConversationTurn: Codable, Identifiable {
    let id: UUID
    let role: ConversationRole
    let content: String
    let timestamp: Date

    init(role: ConversationRole, content: String, timestamp: Date = Date()) {
        self.id        = UUID()
        self.role      = role
        self.content   = content
        self.timestamp = timestamp
    }
}

// MARK: - ConversationRole

enum ConversationRole: String, Codable {
    case user      = "user"
    case assistant = "assistant"
    case system    = "system"
}

// MARK: - AIResponse
// The decoded response from the backend

struct AIResponse: Codable {
    let guidance: String
    let screenSummary: String?
    let currentStep: String?
    let nextExpectedAction: String?
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case guidance
        case screenSummary       = "screen_summary"
        case currentStep         = "current_step"
        case nextExpectedAction  = "next_expected_action"
        case confidence
    }
}

// MARK: - AnalyzeRequest
// What we send to the backend

struct AnalyzeRequest: Codable {
    let image: String          // base64 JPEG
    let userQuery: String
    let memory: [String: AnyCodable]
    let model: String

    enum CodingKeys: String, CodingKey {
        case image
        case userQuery = "user_query"
        case memory
        case model
    }
}

// MARK: - AnyCodable helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal    = try? container.decode(Int.self)    { value = intVal; return }
        if let doubleVal = try? container.decode(Double.self) { value = doubleVal; return }
        if let boolVal   = try? container.decode(Bool.self)   { value = boolVal; return }
        if let stringVal = try? container.decode(String.self) { value = stringVal; return }
        if let arrVal    = try? container.decode([AnyCodable].self) { value = arrVal.map(\.value); return }
        if let dictVal   = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues(\.value); return
        }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool:   try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as [Any]:
            try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]:
            try container.encode(v.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
