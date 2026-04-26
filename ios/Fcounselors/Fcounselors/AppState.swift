import Foundation
import SwiftUI
import Combine

struct SemesterGroup: Identifiable {
    var id: String { semester }
    let semester: String
    let courses: [TranscriptCourse]
}

@MainActor
final class AppState: ObservableObject {
    @Published var transcriptCourses: [TranscriptCourse] = []
    @Published var inProgressCourses: [InProgressCourse] = []
    @Published var inProgressGrades: [String: String] = [:]
    @Published var major: String = ""
    @Published var hasTranscript: Bool = false
    @Published var passingAllClasses: Bool? = nil
    @Published var strugglingCourses: [String] = []
    @Published var preferredColorScheme: ColorScheme? = nil

    var completedCourseCodes: [String] {
        transcriptCourses.map { $0.code }
    }

    var inProgressSummary: [String] {
        inProgressCourses.compactMap { course in
            guard let grade = inProgressGrades[course.code] else {
                return "\(course.code) (currently enrolled, no grade reported)"
            }
            return "\(course.code) (currently enrolled, grade: \(grade))"
        }
    }

    var totalCredits: Double {
        transcriptCourses.compactMap { $0.credits }.reduce(0, +)
    }

    var needsTutoringSupport: Bool {
        passingAllClasses == false && !strugglingCourses.isEmpty
    }

    var semesterGroups: [SemesterGroup] {
        let grouped = Dictionary(grouping: transcriptCourses) { $0.semester ?? "Unknown" }
        let sortedKeys = grouped.keys.sorted { sortSemester($0) > sortSemester($1) }
        return sortedKeys.map { SemesterGroup(semester: $0, courses: grouped[$0]!) }
    }

    private func sortSemester(_ s: String) -> Int {
        if s.lowercased() == "transfer" { return -1 }
        let parts = s.split(separator: " ")
        guard parts.count == 2, let year = Int(parts[1]) else { return -2 }
        let seasonVal: Int
        switch parts[0].lowercased() {
        case "fall": seasonVal = 3
        case "summer": seasonVal = 2
        case "spring": seasonVal = 1
        default: seasonVal = 0
        }
        return year * 10 + seasonVal
    }
}
