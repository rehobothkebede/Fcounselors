import Foundation

// MARK: - Advisor / Plan

struct PlanRequest: Encodable {
    let completed_courses: [String]
    let major: String
    let constraints: [String]
}

struct PlanResponse: Decodable {
    let recommended_courses: [RecommendedCourse]
    let reasoning: String
    let warnings: [String]
}

struct RecommendedCourse: Decodable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let reason: String
}

// MARK: - Chat

struct ChatMessage: Identifiable {
    let id: UUID
    let role: String   // "user" or "assistant"
    let content: String

    init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

struct ChatRequest: Encodable {
    let messages: [ChatPayload]
    let major: String
}

struct ChatPayload: Encodable {
    let role: String
    let content: String
}

struct ChatResponse: Decodable {
    let reply: String
}
