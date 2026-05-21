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
    static let vtBurgundy     = Color(red: 0.525, green: 0.122, blue: 0.255)
    static let vtBurgundyDark = Color(red: 0.315, green: 0.073, blue: 0.153)
}

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: HomeView(selectedTab: $selectedTab)
                case 1: PlanView()
                case 2: ChatView()
                default: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 90)

            FloatingTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
    }
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: Int

    private let items: [(icon: String, label: String)] = [
        ("house.fill",                          "Home"),
        ("calendar.badge.plus",                 "Plan"),
        ("bubble.left.and.bubble.right.fill",   "Advisor"),
        ("person.crop.circle.fill",             "Profile"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = i
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: items[i].icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(items[i].label)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(selectedTab == i ? .white : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background {
                        if selectedTab == i {
                            Capsule().fill(Color.vtBurgundy)
                        }
                    }
                }
            }
        }
        .padding(5)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
        )
    }
}

// MARK: - Plan View

struct PlanView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = PlanViewModel()
    @StateObject private var tutoringVM = TutoringViewModel()
    @State private var showTutoringSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                pageHeader(
                    title: "Course Plan",
                    subtitle: "Your CS degree plan, powered by your transcript"
                )

                transcriptStatusCard.padding(.horizontal, 20)

                VStack(spacing: 12) {
                    BigInputField(label: "Major", placeholder: "Computer Science",
                                  icon: "graduationcap.fill", text: $appState.major)
                    BigInputField(label: "Preferences", placeholder: "e.g. lighter workload, internship focus",
                                  icon: "slider.horizontal.3", text: $vm.preferences)
                }
                .padding(.horizontal, 20)

                if appState.needsTutoringSupport {
                    tutoringBanner.padding(.horizontal, 20)
                }

                generateButton.padding(.horizontal, 20)

                if vm.isLoading {
                    centeredLoadingView(label: "Building your academic plan...")
                        .padding(.horizontal, 20)
                } else if let error = vm.errorMessage {
                    statusCard(icon: "exclamationmark.triangle.fill", iconColor: .orange,
                               title: "Something went wrong", subtitle: "Check your connection and try again.")
                        .padding(.horizontal, 20)
                } else if let plan = vm.plan {
                    resultsView(plan: plan).padding(.horizontal, 20)
                } else {
                    emptyState.padding(.horizontal, 20)
                }

                Spacer(minLength: 20)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showTutoringSheet) { TutoringSheet(vm: tutoringVM) }
    }

    // MARK: Subviews

    private var transcriptStatusCard: some View {
        Group {
            if appState.hasTranscript {
                statusCard(icon: "checkmark.circle.fill", iconColor: .green,
                           title: "\(appState.transcriptCourses.count) courses loaded",
                           subtitle: "\(Int(appState.totalCredits)) credit hours imported")
            } else {
                statusCard(icon: "doc.badge.plus", iconColor: .vtBurgundy,
                           title: "No transcript yet",
                           subtitle: "Go to Profile → Transcript to import yours")
            }
        }
    }

    private var tutoringBanner: some View {
        HStack(spacing: 14) {
            circleIcon("lightbulb.fill", color: .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Academic Support Available").font(.subheadline.bold())
                Text(appState.strugglingCourses.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("View") {
                Task {
                    await tutoringVM.load(strugglingCourses: appState.strugglingCourses,
                                          completedCourses: appState.completedCourseCodes,
                                          major: appState.major)
                    showTutoringSheet = true
                }
            }
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.orange)
            .clipShape(Capsule())
        }
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

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
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars").font(.body.bold())
                Text("Generate My Plan").font(.body.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(canSubmit ? Color.vtBurgundy : Color(.tertiarySystemBackground))
            .foregroundStyle(canSubmit ? .white : Color(.tertiaryLabel))
            .clipShape(Capsule())
        }
        .disabled(!canSubmit)
        .animation(.easeInOut(duration: 0.2), value: canSubmit)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Color.vtBurgundy.opacity(0.4))
            Text("Your plan will appear here")
                .font(.title3.bold()).fontDesign(.rounded)
                .foregroundStyle(.secondary)
            Text(appState.hasTranscript
                 ? "Tap Generate to get recommendations."
                 : "Import your transcript first.")
                .font(.subheadline).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func resultsView(plan: PlanResponse) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("\(plan.recommended_courses.count) courses recommended")
                    .font(.subheadline.bold())
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "Recommended Courses", icon: "book.closed.fill", color: .vtBurgundy)
                ForEach(Array(plan.recommended_courses.enumerated()), id: \.element.id) { idx, course in
                    CourseCard(course: course, index: idx + 1)
                }
            }

            if !plan.reasoning.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Advisor Notes", icon: "text.bubble.fill", color: .blue)
                    ReasoningCard(text: plan.reasoning)
                }
            }

            if !plan.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(title: "Heads Up", icon: "exclamationmark.triangle.fill", color: .orange)
                    ForEach(plan.warnings, id: \.self) { WarningCard(text: $0) }
                }
            }

            if appState.needsTutoringSupport {
                Button {
                    Task {
                        await tutoringVM.load(strugglingCourses: appState.strugglingCourses,
                                              completedCourses: appState.completedCourseCodes,
                                              major: appState.major)
                        showTutoringSheet = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill.questionmark").font(.body.bold())
                        Text("Get Academic Support").font(.body.bold())
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color.orange).foregroundStyle(.white)
                    .clipShape(Capsule())
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
        isLoading = true; errorMessage = nil
        do {
            response = try await APIService.fetchTutoring(
                request: TutoringRequest(struggling_courses: strugglingCourses,
                                        completed_courses: completedCourses, major: major))
        } catch { errorMessage = error.localizedDescription }
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
                    centeredLoadingView(label: "Finding resources for you...")
                } else if let response = vm.response {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if !response.encouragement.isEmpty {
                                Text(response.encouragement.markdown)
                                    .font(.subheadline).lineSpacing(4)
                                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.vtBurgundy.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 24))
                            }
                            if !response.resources.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionLabel(title: "Resources", icon: "building.columns.fill", color: .vtBurgundy)
                                    ForEach(response.resources) { TutoringResourceCard(resource: $0) }
                                }
                            }
                            if !response.tips.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionLabel(title: "Study Tips", icon: "lightbulb.fill", color: .orange)
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(response.tips, id: \.self) { tip in
                                            HStack(alignment: .top, spacing: 10) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.vtBurgundy)
                                                    .font(.footnote).padding(.top, 2)
                                                Text(tip.markdown).font(.subheadline)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                    .padding(18)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 24))
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
                    Button("Done") { dismiss() }.foregroundStyle(Color.vtBurgundy)
                }
            }
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
            circleIcon(typeIcon, color: .vtBurgundy)
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.name).font(.subheadline.bold())
                Text(resource.description).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Shared UI Helpers

func pageHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 34, weight: .bold, design: .rounded))
        Text(subtitle)
            .font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.top, 16)
}

func circleIcon(_ icon: String, color: Color, size: CGFloat = 48) -> some View {
    Image(systemName: icon)
        .font(.system(size: size * 0.38, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(color)
        .clipShape(Circle())
}

func statusCard(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
    HStack(spacing: 14) {
        circleIcon(icon, color: iconColor)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
    }
    .padding(18)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 24))
}

func centeredLoadingView(label: String) -> some View {
    VStack(spacing: 14) {
        ProgressView().scaleEffect(1.3).tint(Color.vtBurgundy)
        Text(label).font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity).padding(.top, 48)
}

// MARK: - BigInputField

struct BigInputField: View {
    let label: String
    let placeholder: String
    let icon: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.bold()).foregroundStyle(Color.vtBurgundy)
                Text(label).font(.caption.bold()).foregroundStyle(.secondary)
                    .textCase(.uppercase).tracking(0.5)
            }
            TextField(placeholder, text: $text)
                .font(.body)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {
    let title: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline.bold()).fontDesign(.rounded)
            .foregroundStyle(color)
    }
}

// MARK: - CourseCard

struct CourseCard: View {
    let course: RecommendedCourse
    var index: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.vtBurgundy).clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(course.code)
                    .font(.caption.bold()).foregroundStyle(Color.vtBurgundy)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.vtBurgundy.opacity(0.1)).clipShape(Capsule())
                Text(course.name).font(.subheadline.bold())
                Text(course.reason).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - MarkdownBody

struct MarkdownBody: View {
    let text: String
    var baseFont: Font = .subheadline
    var baseColor: Color = .primary

    private enum Block {
        case heading(Int, String)
        case bullet(String)
        case numbered(Int, String)
        case paragraph(String)
        case code(language: String, content: String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var pending = ""
        var inCode = false
        var codeLang = ""
        var codeLines: [String] = []

        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)

            if inCode {
                if t.hasPrefix("```") {
                    let content = codeLines.joined(separator: "\n")
                        .trimmingCharacters(in: .newlines)
                    result.append(.code(language: codeLang, content: content))
                    inCode = false; codeLang = ""; codeLines = []
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if t.hasPrefix("```") {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                codeLang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                inCode = true; codeLines = []
                continue
            }

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
                        .font(level == 1 ? .headline : .subheadline).fontWeight(.semibold)
                        .foregroundStyle(baseColor).padding(.top, level <= 2 ? 6 : 2)
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
                case .code(let lang, let content):
                    CodeBlockView(language: lang, code: content)
                        .padding(.vertical, 2)
                }
            }
        }
    }
}

struct ReasoningCard: View {
    let text: String
    var body: some View {
        MarkdownBody(text: text)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct WarningCard: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.footnote).padding(.top, 2)
            Text(text.markdown).font(.subheadline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Previews

#Preview("Tabs") { ContentView().environmentObject(AppState()) }
#Preview("Plan — Empty") { PlanView().environmentObject(AppState()) }
