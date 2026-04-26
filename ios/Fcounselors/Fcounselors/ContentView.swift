import SwiftUI
import Combine

// MARK: - Markdown Helper

extension String {
    var markdown: AttributedString {
        (try? AttributedString(markdown: self)) ?? AttributedString(self)
    }
}

// MARK: - Design System

extension Color {
    static let vtBurgundy = Color(red: 0.525, green: 0.122, blue: 0.255)
    static let vtBurgundyDark = Color(red: 0.315, green: 0.073, blue: 0.153)
    static let vtBurgundyMuted = Color(red: 0.525, green: 0.122, blue: 0.255).opacity(0.12)
}

extension LinearGradient {
    static let vtHeader = LinearGradient(
        colors: [Color.vtBurgundyDark, Color.vtBurgundy],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            TranscriptView()
                .tabItem { Label("Transcript", systemImage: "doc.text.magnifyingglass") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar.badge.plus") }
            ChatView()
                .tabItem { Label("Advisor", systemImage: "bubble.left.and.bubble.right.fill") }
        }
        .tint(Color.vtBurgundy)
    }
}

// MARK: - Plan View

struct PlanView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = PlanViewModel()
    @StateObject private var tutoringVM = TutoringViewModel()
    @State private var showTutoringSheet = false

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
            .sheet(isPresented: $showTutoringSheet) {
                TutoringSheet(vm: tutoringVM)
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Course Plan")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("Next semester, powered by your transcript")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                if appState.hasTranscript {
                    VStack(spacing: 2) {
                        Text("\(appState.transcriptCourses.count)")
                            .font(.title2).fontWeight(.bold).foregroundStyle(.white)
                        Text("courses").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(10)
                    .background(.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 28)
        .background(LinearGradient.vtHeader)
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            transcriptStatusBanner

            Text("Your Details")
                .font(.headline)
                .padding(.top, 4)

            InputCard(
                label: "Major",
                placeholder: "e.g. Computer Science",
                icon: "graduationcap.fill",
                text: $appState.major,
                accentColor: .vtBurgundy
            )
            InputCard(
                label: "Preferences",
                placeholder: "e.g. lighter workload, internship focus",
                icon: "slider.horizontal.3",
                text: $vm.preferences,
                hint: "Optional — helps us tailor recommendations",
                accentColor: .vtBurgundy
            )

            if appState.needsTutoringSupport {
                tutoringBanner
            }
        }
    }

    private var transcriptStatusBanner: some View {
        Group {
            if appState.hasTranscript {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(appState.transcriptCourses.count) courses loaded from transcript")
                            .font(.subheadline).fontWeight(.medium)
                        Text("Completed history will be used automatically")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(appState.totalCredits)) cr")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.2), lineWidth: 1))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(Color.vtBurgundy)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No transcript imported")
                            .font(.subheadline).fontWeight(.medium)
                        Text("Go to the Transcript tab to import your course history")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color.vtBurgundyMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.vtBurgundy.opacity(0.3), lineWidth: 1))
            }
        }
    }

    private var tutoringBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Academic Support Available")
                    .font(.subheadline).fontWeight(.medium)
                Text("Get tutoring resources for: \(appState.strugglingCourses.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("View") {
                Task {
                    await tutoringVM.load(
                        strugglingCourses: appState.strugglingCourses,
                        completedCourses: appState.completedCourseCodes,
                        major: appState.major
                    )
                    showTutoringSheet = true
                }
            }
            .font(.caption).fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.orange)
            .clipShape(Capsule())
        }
        .padding(14)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        let canSubmit = !appState.major.trimmingCharacters(in: .whitespaces).isEmpty && !vm.isLoading

        return Button {
            var constraints: [String] = []
            if appState.needsTutoringSupport {
                constraints.append("student is struggling in: \(appState.strugglingCourses.joined(separator: ", "))")
            }
            Task {
                await vm.generatePlan(
                    completedCourses: appState.completedCourseCodes,
                    major: appState.major,
                    constraints: constraints,
                    inProgressCourses: appState.inProgressSummary
                )
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                Text("Generate My Plan")
                    .fontWeight(.semibold)
            }
            .font(.body)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(canSubmit ? Color.vtBurgundy : Color.gray.opacity(0.3))
            .foregroundColor(canSubmit ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSubmit)
        .animation(.easeInOut(duration: 0.2), value: canSubmit)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Color.vtBurgundy.opacity(0.7))
            Text("Your plan will appear here")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(appState.hasTranscript
                 ? "Enter your major above and tap Generate to get personalized recommendations."
                 : "Import your transcript first, then come back here to generate your plan.")
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
                .tint(Color.vtBurgundy)
            Text("Building your academic plan...")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("This may take a moment")
                .font(.caption).foregroundStyle(.tertiary)
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
                    .font(.subheadline).fontWeight(.semibold)
                Text("Check your connection and try again.")
                    .font(.caption).foregroundStyle(.secondary)
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
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("\(plan.recommended_courses.count) courses recommended for next semester")
                    .font(.subheadline).fontWeight(.medium)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recommended Courses", icon: "book.closed.fill", color: .vtBurgundy)
                ForEach(Array(plan.recommended_courses.enumerated()), id: \.element.id) { index, course in
                    CourseCard(course: course, index: index + 1)
                }
            }

            if !plan.reasoning.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Advisor Notes", icon: "text.bubble.fill", color: .blue)
                    ReasoningCard(text: plan.reasoning)
                }
            }

            if !plan.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Heads Up", icon: "exclamationmark.triangle.fill", color: .orange)
                    ForEach(plan.warnings, id: \.self) { WarningCard(text: $0) }
                }
            }

            if appState.needsTutoringSupport {
                Button {
                    Task {
                        await tutoringVM.load(
                            strugglingCourses: appState.strugglingCourses,
                            completedCourses: appState.completedCourseCodes,
                            major: appState.major
                        )
                        showTutoringSheet = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.questionmark")
                        Text("Get Academic Support")
                            .fontWeight(.semibold)
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

// MARK: - Tutoring View Model

@MainActor
final class TutoringViewModel: ObservableObject {
    @Published var response: TutoringResponse? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    func load(strugglingCourses: [String], completedCourses: [String], major: String) async {
        guard !strugglingCourses.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            response = try await APIService.fetchTutoring(
                request: TutoringRequest(
                    struggling_courses: strugglingCourses,
                    completed_courses: completedCourses,
                    major: major
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Tutoring Sheet

struct TutoringSheet: View {
    @ObservedObject var vm: TutoringViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.3).tint(Color.vtBurgundy)
                        Text("Finding resources for you...").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let response = vm.response {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !response.encouragement.isEmpty {
                                Text(response.encouragement.markdown)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineSpacing(4)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.vtBurgundyMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.vtBurgundy.opacity(0.25), lineWidth: 1))
                            }

                            if !response.resources.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeader(title: "Resources", icon: "building.columns.fill", color: .vtBurgundy)
                                    ForEach(response.resources) { resource in
                                        TutoringResourceCard(resource: resource)
                                    }
                                }
                            }

                            if !response.tips.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader(title: "Study Tips", icon: "lightbulb.fill", color: .orange)
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(response.tips, id: \.self) { tip in
                                            HStack(alignment: .top, spacing: 10) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.vtBurgundy)
                                                    .font(.footnote)
                                                    .padding(.top, 2)
                                                Text(tip.markdown)
                                                    .font(.subheadline)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                                }
                            }
                        }
                        .padding()
                    }
                } else if let error = vm.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Academic Support")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.vtBurgundy)
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct TutoringResourceCard: View {
    let resource: TutoringResource

    private var typeIcon: String {
        switch resource.type {
        case "tutoring": return "person.2.fill"
        case "study_group": return "person.3.fill"
        case "office_hours": return "clock.fill"
        case "online": return "globe"
        case "writing_center": return "pencil.and.scribble"
        case "ai_tutor": return "brain.head.profile"
        default: return "book.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: typeIcon)
                .font(.subheadline)
                .foregroundStyle(Color.vtBurgundy)
                .frame(width: 36, height: 36)
                .background(Color.vtBurgundyMuted)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(resource.name)
                    .font(.subheadline).fontWeight(.semibold)
                Text(resource.description)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Reusable Components

struct InputCard: View {
    let label: String
    let placeholder: String
    let icon: String
    @Binding var text: String
    var hint: String? = nil
    var accentColor: Color = .vtBurgundy

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(accentColor)
                Text(label)
                    .font(.caption).fontWeight(.semibold)
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
                    .font(.caption2).foregroundStyle(.tertiary)
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
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.vtBurgundy)
                .clipShape(Circle())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(course.code)
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(Color.vtBurgundy)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.vtBurgundyMuted)
                    .clipShape(Capsule())
                Text(course.name)
                    .font(.body).fontWeight(.semibold)
                Text(course.reason)
                    .font(.footnote).foregroundStyle(.secondary)
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

// MARK: - Block Markdown Renderer

struct MarkdownBody: View {
    let text: String
    var baseFont: Font = .subheadline
    var baseColor: Color = .primary

    private enum Block {
        case heading(Int, String)
        case bullet(String)
        case numbered(Int, String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var pending = ""
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
            } else if t.hasPrefix("### ") {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.heading(3, String(t.dropFirst(4))))
            } else if t.hasPrefix("## ") {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.heading(2, String(t.dropFirst(3))))
            } else if t.hasPrefix("# ") {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.heading(1, String(t.dropFirst(2))))
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.bullet(String(t.dropFirst(2))))
            } else {
                let parts = t.components(separatedBy: ". ")
                if parts.count >= 2, let num = Int(parts[0]), parts[0].count <= 3 {
                    if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                    result.append(.numbered(num, parts.dropFirst().joined(separator: ". ")))
                } else {
                    pending += pending.isEmpty ? t : " \(t)"
                }
            }
        }
        if !pending.isEmpty { result.append(.paragraph(pending)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let content):
                    Text(content.markdown)
                        .font(level == 1 ? .headline : .subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(baseColor)
                        .padding(.top, level <= 2 ? 6 : 2)
                case .bullet(let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(baseFont).foregroundStyle(baseColor.opacity(0.6))
                        Text(content.markdown).font(baseFont).foregroundStyle(baseColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .numbered(let number, let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(number).").font(baseFont).foregroundStyle(baseColor.opacity(0.6))
                            .frame(minWidth: 20, alignment: .trailing)
                        Text(content.markdown).font(baseFont).foregroundStyle(baseColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let content):
                    Text(content.markdown).font(baseFont).foregroundStyle(baseColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct ReasoningCard: View {
    let text: String

    var body: some View {
        MarkdownBody(text: text)
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
                .foregroundStyle(.orange).font(.footnote).padding(.top, 2)
            Text(text.markdown)
                .font(.subheadline).foregroundStyle(.primary)
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
        .environmentObject(AppState())
}

#Preview("Plan — Empty") {
    PlanView()
        .environmentObject(AppState())
}

#Preview("Plan — With Transcript") {
    let state = AppState()
    state.major = "Computer Science"
    state.transcriptCourses = [
        TranscriptCourse(code: "CS 1114", name: "Intro to Software Design", credits: 3, grade: "A", semester: "Fall 2023"),
        TranscriptCourse(code: "MATH 1225", name: "Calculus of a Single Variable I", credits: 3, grade: "B+", semester: "Fall 2023"),
    ]
    state.hasTranscript = true
    return PlanView().environmentObject(state)
}
