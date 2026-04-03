import Foundation

// MARK: - Request

struct PlanRequest: Encodable {
    let completed_courses: [String]
    let major: String
    let constraints: [String]
}

// MARK: - Response

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
