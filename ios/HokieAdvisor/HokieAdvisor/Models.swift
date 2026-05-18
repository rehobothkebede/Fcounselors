import Foundation

// MARK: - Advisor / Plan

struct PlanRequest: Encodable {
    let completed_courses: [String]
    let major: String
    let constraints: [String]
    let in_progress_courses: [String]
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

// MARK: - Transcript

struct TranscriptCourse: Decodable, Identifiable, Equatable {
    var id: String { "\(code)-\(semester ?? "")-\(grade ?? "")" }
    let code: String
    let name: String
    let credits: Double?
    let grade: String?
    let semester: String?
}

struct InProgressCourse: Decodable, Identifiable, Equatable {
    var id: String { code }
    let code: String
    let name: String
    let credits: Double?
}

struct TranscriptResponse: Decodable, Equatable {
    let courses: [TranscriptCourse]
    let in_progress_courses: [InProgressCourse]
    let course_count: Int?
    let warnings: [String]
}

// MARK: - Tutoring

struct TutoringRequest: Encodable {
    let struggling_courses: [String]
    let completed_courses: [String]
    let major: String
}

struct TutoringResource: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let type: String
    let description: String
    let link: String?
}

struct TutoringResponse: Decodable {
    let resources: [TutoringResource]
    let tips: [String]
    let encouragement: String
}
