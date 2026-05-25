import Foundation

// MARK: - Degree Audit

struct DegreeAuditRequest: Encodable {
    let major: String
    let transcript: [TranscriptEntry]
    let inProgressCourses: [String]

    enum CodingKeys: String, CodingKey {
        case major, transcript
        case inProgressCourses = "in_progress_courses"
    }
}

struct DegreeAuditResponse: Decodable {
    let major: String
    let degree: String
    let catalogYear: String
    let totalRequiredCredits: Double
    let completedCredits: Double
    let percentComplete: Int
    let completeBucketCount: Int
    let totalBucketCount: Int
    let buckets: [AuditBucket]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case major, degree, buckets, warnings
        case catalogYear = "catalog_year"
        case totalRequiredCredits = "total_required_credits"
        case completedCredits = "completed_credits"
        case percentComplete = "percent_complete"
        case completeBucketCount = "complete_bucket_count"
        case totalBucketCount = "total_bucket_count"
    }
}

struct AuditBucket: Decodable, Identifiable {
    let id: String
    let title: String
    let status: String
    let requiredCredits: Double
    let completedCredits: Double
    let requiredCount: Int?
    let completedCount: Int?
    let matchedCourses: [String]
    let missingItems: [String]
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, status, notes
        case requiredCredits = "required_credits"
        case completedCredits = "completed_credits"
        case requiredCount = "required_count"
        case completedCount = "completed_count"
        case matchedCourses = "matched_courses"
        case missingItems = "missing_items"
    }
}

// MARK: - Chat

struct ChatMessage: Identifiable, Codable {
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

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var date: Date
    var messages: [ChatMessage]

    init(id: UUID = UUID(), title: String = "New Chat", date: Date = Date(), messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.date = date
        self.messages = messages
    }
}

struct ChatMemory: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var date: Date

    init(id: UUID = UUID(), content: String, date: Date = Date()) {
        self.id = id
        self.content = content
        self.date = date
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
    let transcriptNotes: [String]
    let chatMemories: [String]

    enum CodingKeys: String, CodingKey {
        case messages, major, transcript
        case inProgressCourses = "in_progress_courses"
        case transcriptNotes = "transcript_notes"
        case chatMemories = "chat_memories"
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
    let semester: String?   // which semester this enrollment is for; nil = assume current
}

struct TranscriptResponse: Decodable, Equatable {
    let courses: [TranscriptCourse]
    let in_progress_courses: [InProgressCourse]
    let planned_courses: [InProgressCourse]?   // pre-registered future-semester courses
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
