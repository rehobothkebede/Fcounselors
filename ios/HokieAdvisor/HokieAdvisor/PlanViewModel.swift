import Combine
import Foundation

@MainActor
final class DegreeAuditViewModel: ObservableObject {
    @Published var audit: DegreeAuditResponse? = nil
    @Published var isAuditLoading: Bool = false
    @Published var auditErrorMessage: String? = nil

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
}

@MainActor
final class DarsAuditViewModel: ObservableObject {
    @Published var audit: DarsAuditResponse? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var importedFileName: String? = nil

    func upload(fileData: Data, mimeType: String, fileName: String) async {
        isLoading = true
        errorMessage = nil
        do {
            audit = try await APIService.uploadDarsAudit(fileData: fileData, mimeType: mimeType, fileName: fileName)
            importedFileName = fileName
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func clear() {
        audit = nil
        errorMessage = nil
        importedFileName = nil
    }
}