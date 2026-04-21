import SwiftUI

// MARK: - Root View (Tab Container)

struct ContentView: View {
    var body: some View {
        TabView {
            PlanView()
                .tabItem {
                    Label("Plan", systemImage: "calendar.badge.plus")
                }
            ChatView()
                .tabItem {
                    Label("Advisor", systemImage: "bubble.left.and.bubble.right.fill")
                }
        }
        .tint(.orange)
    }
}

// MARK: - Plan View

struct PlanView: View {
    @StateObject private var vm: PlanViewModel

    nonisolated init(vm: PlanViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    @MainActor
    init() {
        _vm = StateObject(wrappedValue: PlanViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    heroHeader

                    VStack(spacing: 20) {
                        inputSection
                        generateButton

                        if vm.isLoading {
                            loadingView
                        } else if let error = vm.errorMessage {
                            errorView(message: error)
                        } else if let plan = vm.plan {
                            resultsView(plan: plan)
                        } else {
                            emptyState
                        }
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Course Advisor")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text("Plan your next semester")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 28)
        .background(
            LinearGradient(
                colors: [Color(red: 0.72, green: 0.1, blue: 0.1), Color.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tell us about yourself")
                .font(.headline)
                .padding(.top, 4)

            InputCard(
                label: "Major",
                placeholder: "e.g. Computer Science",
                icon: "graduationcap.fill",
                text: $vm.major
            )
            InputCard(
                label: "Completed Courses",
                placeholder: "e.g. CS 1114, MATH 1225",
                icon: "checkmark.circle.fill",
                text: $vm.completedCoursesText,
                hint: "Separate courses with commas"
            )
            InputCard(
                label: "Preferences",
                placeholder: "e.g. lighter workload, internship focus",
                icon: "slider.horizontal.3",
                text: $vm.preferences,
                hint: "Optional — helps us tailor recommendations"
            )
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button {
            Task { await vm.generatePlan() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                Text("Generate My Plan")
                    .fontWeight(.semibold)
            }
            .font(.body)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(vm.canSubmit ? Color.orange : Color.gray.opacity(0.3))
            .foregroundColor(vm.canSubmit ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!vm.canSubmit)
        .animation(.easeInOut(duration: 0.2), value: vm.canSubmit)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.orange.opacity(0.7))
            Text("Your plan will appear here")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Enter your major above and tap Generate to get personalized course recommendations.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(.orange)
            Text("Building your academic plan...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("This may take a moment")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 40)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Something went wrong")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Check your connection and try again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Results

    private func resultsView(plan: PlanResponse) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Summary banner
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("\(plan.recommended_courses.count) courses recommended for next semester")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Recommended courses
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recommended Courses", icon: "book.closed.fill", color: .orange)
                ForEach(Array(plan.recommended_courses.enumerated()), id: \.element.id) { index, course in
                    CourseCard(course: course, index: index + 1)
                }
            }

            // Reasoning
            if !plan.reasoning.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Advisor Notes", icon: "text.bubble.fill", color: .blue)
                    ReasoningCard(text: plan.reasoning)
                }
            }

            // Warnings
            if !plan.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Heads Up", icon: "exclamationmark.triangle.fill", color: .orange)
                    ForEach(plan.warnings, id: \.self) { warning in
                        WarningCard(text: warning)
                    }
                }
            }
        }
    }
}

// MARK: - Reusable Components

struct InputCard: View {
    let label: String
    let placeholder: String
    let icon: String
    @Binding var text: String
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            TextField(placeholder, text: $text)
                .padding(12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(color)
    }
}

struct CourseCard: View {
    let course: RecommendedCourse
    var index: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.orange)
                .clipShape(Circle())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(course.code)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                Text(course.name)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(course.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct ReasoningCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineSpacing(4)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.15), lineWidth: 1))
    }
}

struct WarningCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.footnote)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Previews

#Preview("Tabs") {
    ContentView()
}

#Preview("Plan — Empty") {
    PlanView()
}

#Preview("Plan — Results") {
    let vm = PlanViewModel()
    vm.plan = PlanResponse(
        recommended_courses: [
            RecommendedCourse(code: "CS 2114", name: "Software Design and Data Structures", reason: "Core requirement building on CS 1114"),
            RecommendedCourse(code: "MATH 2214", name: "Introduction to Differential Equations", reason: "Required math course for CS major"),
            RecommendedCourse(code: "CS 2505", name: "Computer Organization I", reason: "Fundamental understanding of computer architecture")
        ],
        reasoning: "Based on completing CS 1114 and MATH 1225, you're ready for the next core CS courses.",
        warnings: ["CS 2114 has high demand — register early"]
    )
    return PlanView(vm: vm)
}

#Preview("Plan — Loading") {
    let vm = PlanViewModel()
    vm.isLoading = true
    return PlanView(vm: vm)
}

#Preview("Plan — Error") {
    let vm = PlanViewModel()
    vm.errorMessage = "Network connection failed"
    return PlanView(vm: vm)
}
