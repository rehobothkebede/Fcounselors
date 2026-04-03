import Foundation
import Combine

@MainActor
final class PlanViewModel: ObservableObject {

    // MARK: - Inputs
    @Published var major: String = ""
    @Published var completedCoursesText: String = ""   // comma-separated
    @Published var preferences: String = ""

    // MARK: - Outputs
    @Published var plan: PlanResponse? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Computed

    var completedCourses: [String] {
        completedCoursesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var constraints: [String] {
        preferences.isEmpty ? [] : [preferences]
    }

    var canSubmit: Bool {
        !major.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    // MARK: - Actions

    func generatePlan() async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        plan = nil

        let body = PlanRequest(
            completed_courses: completedCourses,
            major: major.trimmingCharacters(in: .whitespaces),
            constraints: constraints
        )

        do {
            plan = try await APIService.fetchPlan(request: body)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            // Fake data for preview
            self.plan = PlanResponse(
                recommended_courses: [
                    RecommendedCourse(code: "CS 1114", name: "Intro to Software Design", reason: "Starter course"),
                ],
                reasoning: "Preview mode data",
                warnings: []
            )
            return
        }
    }
}
