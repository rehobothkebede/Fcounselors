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
    @Published var plannedCourses: [InProgressCourse] = []
    @Published var inProgressGrades: [String: String] = [:]
    @Published var major: String = "Computer Science"
    @Published var hasTranscript: Bool = false
    @Published var passingAllClasses: Bool? = nil
    @Published var strugglingCourses: [String] = []
    @Published var transcriptNotes: [String] = []
    @Published var preferredColorScheme: ColorScheme? = nil

    // MARK: - Semester Awareness

    var currentVTSemester: String? {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let day = cal.component(.day, from: now)
        // Spring: Jan 15 – May 10
        if (month == 1 && day >= 15) || (month >= 2 && month <= 4) || (month == 5 && day <= 10) {
            return "Spring \(year)"
        }
        // Summer: May 20 – Aug 10
        if (month == 5 && day >= 20) || month == 6 || month == 7 || (month == 8 && day <= 10) {
            return "Summer \(year)"
        }
        // Fall: Aug 25 – Dec 14
        if (month == 8 && day >= 25) || (month >= 9 && month <= 11) || (month == 12 && day <= 14) {
            return "Fall \(year)"
        }
        return nil
    }

    var isSemesterInSession: Bool { currentVTSemester != nil }

    // Courses whose semester matches right now (or have no semester tag — assume current)
    var activeSemesterCourses: [InProgressCourse] {
        guard isSemesterInSession else { return [] }
        return inProgressCourses.filter { course in
            guard let sem = course.semester else { return true }
            return sem == currentVTSemester
        }
    }

    // Courses the student pre-registered for but haven't started yet
    var registeredUpcomingCourses: [InProgressCourse] {
        let fromUpcomingField = plannedCourses
        let futureTagged = inProgressCourses.filter { course in
            guard let sem = course.semester else { return false }
            return sem != currentVTSemester
        }
        // If not in session, ALL in-progress are future-registered
        let fromInProgress = isSemesterInSession ? futureTagged : inProgressCourses
        let combined = fromInProgress + fromUpcomingField
        var seen = Set<String>()
        return combined.filter { seen.insert($0.code).inserted }
    }

    var completedCourseCodes: [String] {
        transcriptCourses.map { $0.code }
    }

    var inProgressSummary: [String] {
        let active = activeSemesterCourses
        let activeLines = active.compactMap { course -> String? in
            guard let grade = inProgressGrades[course.code] else {
                return "\(course.code) (currently enrolled, no grade reported)"
            }
            return "\(course.code) (currently enrolled, grade: \(grade))"
        }
        let upcomingLines = registeredUpcomingCourses.map {
            "\($0.code) (registered for upcoming semester — not yet in progress)"
        }
        // Fall back to all in-progress if semester detection yields nothing active
        if active.isEmpty && !inProgressCourses.isEmpty && isSemesterInSession {
            return inProgressCourses.compactMap { course in
                guard let grade = inProgressGrades[course.code] else {
                    return "\(course.code) (currently enrolled, no grade reported)"
                }
                return "\(course.code) (currently enrolled, grade: \(grade))"
            } + upcomingLines
        }
        return activeLines + upcomingLines
    }

    var totalCredits: Double {
        transcriptCourses.compactMap { $0.credits }.reduce(0, +)
    }

    var calculatedGPA: Double? {
        var totalPoints: Double = 0
        var totalCredits: Double = 0
        for course in transcriptCourses {
            guard let g = course.grade, let pts = gradePoints(g), let cr = course.credits else { continue }
            totalPoints += pts * cr
            totalCredits += cr
        }
        guard totalCredits > 0 else { return nil }
        return totalPoints / totalCredits
    }

    private func gradePoints(_ grade: String) -> Double? {
        switch grade {
        case "A+", "A": return 4.0
        case "A-":       return 3.7
        case "B+":       return 3.3
        case "B":        return 3.0
        case "B-":       return 2.7
        case "C+":       return 2.3
        case "C":        return 2.0
        case "C-":       return 1.7
        case "D+":       return 1.3
        case "D":        return 1.0
        case "D-":       return 0.7
        case "F":        return 0.0
        default:         return nil
        }
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
