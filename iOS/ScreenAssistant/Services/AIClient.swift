import Foundation
import UIKit

// MARK: - AIClient
//
// Sends screen frames + memory context to either:
//   A) Your FastAPI backend (recommended — keeps API keys secure)
//   B) OpenAI directly (fallback for local dev / testing)
//
// The backend handles prompt construction, Gemini pre-processing,
// and GPT-4o reasoning. The app just sends image + query + memory.

final class AIClient {

    static let shared = AIClient()
    private init() {}

    private let session = URLSession.shared
    private var settings: AppSettings { AppSettings.shared }

    // MARK: - Main API Call

    /// Analyzes the current screen with GPT-4o vision.
    /// Routes to backend if configured, otherwise direct OpenAI.
    func analyze(image: UIImage, query: String) async throws -> AIResponse {
        let quality = settings.captureQuality
        guard let base64 = image.base64JPEG(quality: quality.compressionQuality) else {
            throw AIError.imageEncodingFailed
        }

        let memoryPayload = MemoryManager.shared.memoryPayload()

        if !settings.backendURL.isEmpty && settings.backendURL != "http://localhost:8000" {
            // Route to your FastAPI backend
            return try await callBackend(
                base64Image: base64,
                query: query,
                memory: memoryPayload
            )
        } else if !settings.openAIKey.isEmpty {
            // Direct OpenAI call (fallback / local dev)
            return try await callOpenAIDirect(
                base64Image: base64,
                query: query,
                memory: memoryPayload
            )
        } else {
            throw AIError.notConfigured
        }
    }

    // MARK: - Backend Route

    private func callBackend(base64Image: String,
                              query: String,
                              memory: [String: Any]) async throws -> AIResponse {
        guard let url = URL(string: "\(settings.backendURL)/analyze") else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "image":      base64Image,
            "user_query": query,
            "memory":     memory,
            "model":      settings.selectedModel
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.httpError(httpResponse.statusCode, errorBody)
        }

        return try JSONDecoder().decode(AIResponse.self, from: data)
    }

    // MARK: - Direct OpenAI Route (Dev / Fallback)

    private func callOpenAIDirect(base64Image: String,
                                   query: String,
                                   memory: [String: Any]) async throws -> AIResponse {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Build context from memory
        let memoryContext = buildMemoryContext(from: memory)

        let systemPrompt = """
        You are a screen-aware AI assistant helping a user navigate their iPhone.

        You can see exactly what's on their screen right now.

        \(memoryContext)

        Guidelines:
        - Be concise and direct (2-3 sentences max for voice)
        - Give actionable, step-by-step guidance
        - Reference specific UI elements you can see
        - Remember what the user is trying to accomplish
        - Speak naturally, as if you're right next to them
        """

        let conversationHistory = (memory["conversation_history"] as? [[String: Any]]) ?? []
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Add recent conversation history
        for turn in conversationHistory.suffix(6) {
            messages.append(turn)
        }

        // Current message with image
        messages.append([
            "role": "user",
            "content": [
                [
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]
                ],
                [
                    "type": "text",
                    "text": query
                ]
            ]
        ])

        let body: [String: Any] = [
            "model":      settings.selectedModel,
            "messages":   messages,
            "max_tokens": 300,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, errorBody)
        }

        // Parse OpenAI response
        guard let json      = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices   = json["choices"] as? [[String: Any]],
              let message   = choices.first?["message"] as? [String: Any],
              let content   = message["content"] as? String else {
            throw AIError.parsingFailed
        }

        // Wrap in AIResponse
        return AIResponse(
            guidance:            content,
            screenSummary:       nil,
            currentStep:         nil,
            nextExpectedAction:  nil,
            confidence:          nil
        )
    }

    // MARK: - Helpers

    private func buildMemoryContext(from memory: [String: Any]) -> String {
        var parts: [String] = []

        if let task = memory["task"] as? String {
            parts.append("Current task: \(task)")
        }
        if let step = memory["current_step"] as? String {
            parts.append("Current step: \(step)")
        }
        if let summary = memory["last_screen_summary"] as? String {
            parts.append("Previous screen: \(summary)")
        }
        if let action = memory["last_action"] as? String {
            parts.append("Last action: \(action)")
        }
        if let next = memory["next_expected_action"] as? String {
            parts.append("Expected next: \(next)")
        }

        return parts.isEmpty ? "" : "Context:\n" + parts.joined(separator: "\n")
    }

    // MARK: - Streaming API (text input path)

    /// Streams token-by-token responses from OpenAI for the text-input chat path.
    /// If `image` is provided (active screen session) it is included as a vision message.
    /// Falls back to non-streaming backend route if no direct key is present.
    func analyzeStreaming(image: UIImage?, query: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // No direct key — wrap the existing blocking call as a single-yield stream
                    if settings.openAIKey.isEmpty {
                        guard let img = image else { throw AIError.notConfigured }
                        let response = try await self.analyze(image: img, query: query)
                        continuation.yield(response.guidance)
                        continuation.finish()
                        return
                    }

                    let url = URL(string: "https://api.openai.com/v1/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(settings.openAIKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60

                    let memoryPayload = MemoryManager.shared.memoryPayload()
                    let memoryContext = buildMemoryContext(from: memoryPayload)
                    let history = (memoryPayload["conversation_history"] as? [[String: Any]]) ?? []

                    let systemPrompt = """
                    You are a screen-aware AI assistant helping a user navigate their iPhone.
                    \(memoryContext)
                    Guidelines:
                    - Be concise and direct
                    - Give actionable guidance
                    - Reference specific UI elements you can see
                    - Speak naturally
                    """

                    var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
                    for turn in history.suffix(6) { messages.append(turn) }

                    if let img = image,
                       let base64 = img.base64JPEG(quality: settings.captureQuality.compressionQuality) {
                        messages.append([
                            "role": "user",
                            "content": [
                                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]],
                                ["type": "text", "text": query]
                            ]
                        ])
                    } else {
                        messages.append(["role": "user", "content": query])
                    }

                    let body: [String: Any] = [
                        "model":       settings.selectedModel,
                        "messages":    messages,
                        "stream":      true,
                        "max_tokens":  500,
                        "temperature": 0.7
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" { break }
                        guard let data = jsonStr.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let token = chunk.choices.first?.delta.content else { continue }
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }
}

// MARK: - AIError

enum AIError: Error, LocalizedError {
    case notConfigured
    case imageEncodingFailed
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Please configure your backend URL or OpenAI API key in Settings."
        case .imageEncodingFailed:
            return "Failed to encode screen capture."
        case .invalidURL:
            return "Invalid backend URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .httpError(let code, let body):
            return "Server error \(code): \(body)"
        case .parsingFailed:
            return "Failed to parse AI response."
        }
    }
}
