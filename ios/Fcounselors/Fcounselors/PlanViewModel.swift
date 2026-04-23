import Combine
import Foundation

@MainActor
final class PlanViewModel: ObservableObject {
    // MARK: - Input (from AppState via PlanView)
    @Published var preferences: String = ""

    // MARK: - Outputs
    @Published var plan: PlanResponse? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Actions

    func generatePlan(completedCourses: [String], major: String, constraints: [String] = []) async {
        guard !major.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        plan = nil

        var allConstraints = constraints
        if !preferences.trimmingCharacters(in: .whitespaces).isEmpty {
            allConstraints.append(preferences.trimmingCharacters(in: .whitespaces))
        }

        let body = PlanRequest(
            completed_courses: completedCourses,
            major: major.trimmingCharacters(in: .whitespaces),
            constraints: allConstraints
        )

        do {
            plan = try await APIService.fetchPlan(request: body)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
