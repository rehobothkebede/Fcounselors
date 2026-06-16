import Combine
import Foundation

@MainActor
final class DegreeAuditViewModel: ObservableObject {
    @Published var audit: DegreeAuditResponse? = nil
    @Published var isAuditLoading: Bool = false
    @Published var auditErrorMessage: String? = nil

    #if DEBUG
    func loadVisualQASampleAudit(major: String) {
        audit = DegreeAuditResponse.visualQASample(major: major)
        auditErrorMessage = nil
        isAuditLoading = false
    }
    #endif

    func runAudit(transcript: [TranscriptCourse], major: String, inProgressCourses: [String] = []) async {
        guard !major.trimmingCharacters(in: .whitespaces).isEmpty, !transcript.isEmpty else { return }
        isAuditLoading = true
        auditErrorMessage = nil

        let entries = transcript.map {
            TranscriptEntry(code: $0.code, name: $0.name, grade: $0.grade, semester: $0.semester, credits: $0.credits)
        }
        let body = DegreeAuditRequest(
            major: major.trimmingCharacters(in: .whitespaces),
            transcript: entries,
            inProgressCourses: inProgressCourses
        )

        do {
            audit = try await APIService.fetchDegreeAudit(request: body)
        } catch {
            auditErrorMessage = error.localizedDescription
        }

        isAuditLoading = false
    }

    func loadCachedAudit(_ cachedAudit: DegreeAuditResponse?) {
        guard let cachedAudit else { return }
        audit = cachedAudit
        auditErrorMessage = nil
        isAuditLoading = false
    }
}

#if DEBUG
extension DegreeAuditResponse {
    static func visualQASample(major: String) -> DegreeAuditResponse {
        DegreeAuditResponse(
            major: major.isEmpty ? "Computer Science" : major,
            degree: "BS Computer Science",
            catalogYear: "2025-2026",
            totalRequiredCredits: 123,
            completedCredits: 20,
            percentComplete: 16,
            completeBucketCount: 3,
            totalBucketCount: 12,
            buckets: [
                AuditBucket(
                    id: "intro-sequence",
                    title: "Intro CS sequence",
                    status: "complete",
                    requiredCredits: 6,
                    completedCredits: 6,
                    requiredCount: 2,
                    completedCount: 2,
                    matchedCourses: ["CS 1114", "CS 2114"],
                    missingItems: [],
                    notes: ["Foundation courses are complete."]
                ),
                AuditBucket(
                    id: "math-core",
                    title: "Math core",
                    status: "in_progress",
                    requiredCredits: 17,
                    completedCredits: 8,
                    requiredCount: 5,
                    completedCount: 2,
                    matchedCourses: ["MATH 1225", "MATH 1226", "MATH 2114 in progress"],
                    missingItems: ["MATH 2204", "STAT 4705"],
                    notes: ["Linear algebra is currently in progress."]
                ),
                AuditBucket(
                    id: "systems",
                    title: "Systems requirement",
                    status: "attention",
                    requiredCredits: 6,
                    completedCredits: 0,
                    requiredCount: 2,
                    completedCount: 0,
                    matchedCourses: ["CS 2505 in progress"],
                    missingItems: ["CS 2506"],
                    notes: ["Finish CS 2505 before planning CS 2506."]
                ),
                AuditBucket(
                    id: "pathways",
                    title: "Pathways and writing",
                    status: "complete",
                    requiredCredits: 6,
                    completedCredits: 6,
                    requiredCount: nil,
                    completedCount: nil,
                    matchedCourses: ["ENGL 1105", "COMM 1016"],
                    missingItems: [],
                    notes: ["Keep official DARS as the final source of truth."]
                ),
                AuditBucket(
                    id: "upper-division",
                    title: "Upper-division CS",
                    status: "incomplete",
                    requiredCredits: 21,
                    completedCredits: 0,
                    requiredCount: 7,
                    completedCount: 0,
                    matchedCourses: [],
                    missingItems: ["CS 3114", "CS 3214", "CS electives"],
                    notes: ["Plan these after the data structures path is underway."]
                ),
            ],
            warnings: [
                "Sample audit for visual QA only. Verify real schedules against official Virginia Tech DARS."
            ]
        )
    }
}
#endif

@MainActor
final class DarsAuditViewModel: ObservableObject {
    @Published var audit: DarsAuditResponse? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var importedFileName: String? = nil

    @discardableResult
    func upload(fileData: Data, mimeType: String, fileName: String) async -> DarsAuditResponse? {
        isLoading = true
        errorMessage = nil
        do {
            audit = try await APIService.uploadDarsAudit(fileData: fileData, mimeType: mimeType, fileName: fileName)
            importedFileName = fileName
            isLoading = false
            return audit
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isLoading = false
            return nil
        }
    }

    func loadCachedAudit(_ cachedAudit: DarsAuditResponse?) {
        guard let cachedAudit else { return }
        audit = cachedAudit
        importedFileName = "Saved DARS audit"
        errorMessage = nil
        isLoading = false
    }

    func clear() {
        audit = nil
        errorMessage = nil
        importedFileName = nil
    }
}
