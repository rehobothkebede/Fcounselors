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
    let role: String
    var content: String
    var isStreaming: Bool

    init(id: UUID = UUID(), role: String, content: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
    }
}

struct TranscriptEntry: Encodable {
    let code: String
    let name: String
    let grade: String?
    let semester: String?
    let credits: Double?
}

struct ChatRequest: Encodable {
    let messages: [ChatPayload]
    let major: String
    let transcript: [TranscriptEntry]
    let inProgressCourses: [String]

    enum CodingKeys: String, CodingKey {
        case messages, major, transcript
        case inProgressCourses = "in_progress_courses"
    }
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
