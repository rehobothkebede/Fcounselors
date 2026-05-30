import SwiftUI
import Combine
import UniformTypeIdentifiers

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
                case 1: DegreeAuditView()
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
        ("checklist.checked",                   "Audit"),
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
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

// MARK: - Degree Audit View

struct DegreeAuditView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = DegreeAuditViewModel()
    @StateObject private var darsVM = DarsAuditViewModel()
    @StateObject private var tutoringVM = TutoringViewModel()
    @State private var showTutoringSheet = false
    @State private var showDarsImporter = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                pageHeader(
                    title: "Official Audit",
                    subtitle: "DARS first, local CS check as backup"
                )

                darsImportSection.padding(.horizontal, 20)
                transcriptStatusCard.padding(.horizontal, 20)
                if appState.hasTranscript {
                    auditSection.padding(.horizontal, 20)
                    if appState.needsTutoringSupport {
                        tutoringBanner.padding(.horizontal, 20)
                    }
                } else {
                    auditEmptyState.padding(.horizontal, 20)
                }

                Spacer(minLength: 20)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showTutoringSheet) { TutoringSheet(vm: tutoringVM) }
        .fileImporter(
            isPresented: $showDarsImporter,
            allowedContentTypes: [.pdf, .png, .jpeg],
            allowsMultipleSelection: false,
            onCompletion: handlePickedDarsFile
        )
        .task(id: auditRefreshKey) {
            guard appState.hasTranscript else { return }
            await vm.runAudit(
                transcript: appState.transcriptCourses,
                major: appState.major,
                inProgressCourses: appState.inProgressCourses.map(\.code)
            )
        }
    }

    // MARK: Subviews

    private var darsImportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DarsHeroCard(
                audit: darsVM.audit,
                fileName: darsVM.importedFileName,
                isLoading: darsVM.isLoading,
                onImport: {
                    darsVM.errorMessage = nil
                    showDarsImporter = true
                },
                onClear: { darsVM.clear() }
            )

            if darsVM.isLoading {
                statusCard(icon: "hourglass", iconColor: .vtBurgundy,
                           title: "Reading official audit",
                           subtitle: "Parsing the uploaded DARS/uAchieve file")
            }

            if let error = darsVM.errorMessage {
                DarsBackendStatusCard(message: error)
            }

            if let audit = darsVM.audit {
                DarsAuditSummaryCard(audit: audit)

                if !audit.warnings.isEmpty {
                    ForEach(audit.warnings, id: \.self) { WarningCard(text: $0) }
                }

                DarsCategoryList(categories: audit.categories)

                if !audit.sections.isEmpty {
                    DarsSectionList(sections: audit.sections)
                }
            }
        }
    }

    private var auditRefreshKey: String {
        let courses = appState.transcriptCourses
            .map { "\($0.code):\($0.grade ?? ""):\($0.credits ?? 0)" }
            .joined(separator: "|")
        return "\(appState.major)|\(courses)|\(appState.inProgressCourses.map(\.code).joined(separator: ","))"
    }

    private var transcriptStatusCard: some View {
        Group {
            if appState.hasTranscript {
                statusCard(icon: "checkmark.circle.fill", iconColor: .green,
                           title: "Computer Science B.S. audit",
                           subtitle: "\(appState.transcriptCourses.count) courses · \(Int(appState.totalCredits)) imported credits")
            } else {
                statusCard(icon: "doc.badge.plus", iconColor: .vtBurgundy,
                           title: "Import your transcript",
                           subtitle: "Go to Profile → Transcript to unlock your CS degree audit")
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

    private var auditSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(title: "Audit Results", icon: "checklist.checked", color: .vtBurgundy)
                Spacer()
                Button {
                    Task {
                        await vm.runAudit(
                            transcript: appState.transcriptCourses,
                            major: appState.major,
                            inProgressCourses: appState.inProgressCourses.map(\.code)
                        )
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.bold())
                        .foregroundStyle(Color.vtBurgundy)
                        .frame(width: 34, height: 34)
                        .background(Color.vtBurgundy.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(vm.isAuditLoading)
            }

            if vm.isAuditLoading && vm.audit == nil {
                statusCard(icon: "hourglass", iconColor: .vtBurgundy,
                           title: "Running audit", subtitle: "Checking transcript against CS degree requirements")
            } else if let error = vm.auditErrorMessage {
                statusCard(icon: "exclamationmark.triangle.fill", iconColor: .orange,
                           title: "Audit unavailable", subtitle: error)
            } else if let audit = vm.audit {
                AuditSummaryCard(audit: audit)

                if !audit.warnings.isEmpty {
                    ForEach(audit.warnings, id: \.self) { WarningCard(text: $0) }
                }

                auditBucketGroup(title: "Needs Attention", buckets: audit.buckets.filter { $0.status == "attention" })
                auditBucketGroup(title: "Remaining Requirements", buckets: auditBucketsToShow(audit))
                auditBucketGroup(title: "Completed", buckets: Array(audit.buckets.filter { $0.status == "complete" }.prefix(8)))
            }
        }
    }

    private var auditEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Color.vtBurgundy.opacity(0.45))
            Text("Your CS degree audit will appear here")
                .font(.title3.bold()).fontDesign(.rounded)
                .multilineTextAlignment(.center)
            Text("Import a transcript and Hokie Advisor will check completed courses, retakes, Pathways, electives, and remaining CS requirements.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func auditBucketGroup(title: String, buckets: [AuditBucket]) -> some View {
        Group {
            if !buckets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    ForEach(buckets) { bucket in
                        AuditBucketCard(bucket: bucket)
                    }
                }
            }
        }
    }

    private func auditBucketsToShow(_ audit: DegreeAuditResponse) -> [AuditBucket] {
        let priority = audit.buckets.filter { $0.status == "incomplete" }
        let partial = audit.buckets.filter { $0.status == "in_progress" }
        return Array((priority + partial).prefix(14))
    }

    private func handlePickedDarsFile(_ pickerResult: Result<[URL], Error>) {
        switch pickerResult {
        case .failure(let error):
            darsVM.errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                darsVM.errorMessage = "Could not read the selected audit file."
                return
            }
            let mime: String
            switch url.pathExtension.lowercased() {
            case "pdf": mime = "application/pdf"
            case "png": mime = "image/png"
            default: mime = "image/jpeg"
            }
            Task { await darsVM.upload(fileData: data, mimeType: mime, fileName: url.lastPathComponent) }
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

func gpaColor(_ gpa: Double) -> Color {
    if gpa >= 3.7 { return .green }
    if gpa >= 3.0 { return .blue }
    if gpa >= 2.0 { return .orange }
    return .red
}

func centeredLoadingView(label: String) -> some View {
    VStack(spacing: 14) {
        ProgressView().scaleEffect(1.3).tint(Color.vtBurgundy)
        Text(label).font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity).padding(.top, 48)
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

// MARK: - Degree Audit Cards

struct AuditSummaryCard: View {
    let audit: DegreeAuditResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(audit.major) \(audit.degree)")
                        .font(.headline.bold()).fontDesign(.rounded)
                    Text("Catalog \(audit.catalogYear)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(audit.percentComplete)%")
                    .font(.title2.bold()).fontDesign(.rounded)
                    .foregroundStyle(Color.vtBurgundy)
            }

            ProgressView(value: Double(audit.percentComplete), total: 100)
                .tint(Color.vtBurgundy)

            HStack(spacing: 12) {
                auditMetric(value: "\(Int(audit.completedCredits))/\(Int(audit.totalRequiredCredits))", label: "Credits")
                auditMetric(value: "\(audit.completeBucketCount)/\(audit.totalBucketCount)", label: "Buckets")
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func auditMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct AuditBucketCard: View {
    let bucket: AuditBucket

    private var statusColor: Color {
        switch bucket.status {
        case "complete": return .green
        case "attention": return .orange
        case "in_progress": return .blue
        default: return Color(.systemGray)
        }
    }

    private var statusIcon: String {
        switch bucket.status {
        case "complete": return "checkmark.circle.fill"
        case "attention": return "exclamationmark.triangle.fill"
        case "in_progress": return "clock.fill"
        default: return "circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.headline)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bucket.title)
                        .font(.subheadline.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if bucket.requiredCredits > 0 {
                        Text("\(Int(bucket.completedCredits))/\(Int(bucket.requiredCredits)) cr")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                if !bucket.matchedCourses.isEmpty {
                    Text(bucket.matchedCourses.prefix(4).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !bucket.missingItems.isEmpty {
                    Text("Missing: \(bucket.missingItems.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let note = bucket.notes.first {
                    Text(note)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - DARS / uAchieve Cards

struct DarsHeroCard: View {
    let audit: DarsAuditResponse?
    let fileName: String?
    let isLoading: Bool
    let onImport: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                circleIcon("building.columns.fill", color: .vtBurgundy, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Official DARS / CollegeSource")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(audit == nil ? "Source-of-truth audit import" : loadedSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(action: onImport) {
                    Label(audit == nil ? "Import Audit" : "Replace Audit", systemImage: "arrow.up.doc.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isLoading ? Color(.tertiarySystemBackground) : Color.vtBurgundy)
                        .foregroundStyle(isLoading ? Color(.tertiaryLabel) : .white)
                        .clipShape(Capsule())
                }
                .disabled(isLoading)

                if audit != nil {
                    Button(action: onClear) {
                        Image(systemName: "xmark")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.vtBurgundy)
                            .frame(width: 46, height: 46)
                            .background(Color.vtBurgundy.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Clear DARS audit")
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private var loadedSubtitle: String {
        if let preparedOn = audit?.preparedOn, !preparedOn.isEmpty {
            return "Prepared \(preparedOn)"
        }
        if let fileName {
            return fileName
        }
        return "Audit loaded"
    }
}

struct DarsBackendStatusCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "network.slash")
                .foregroundStyle(.orange)
                .font(.headline)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("DARS backend not ready")
                    .font(.subheadline.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct DarsAuditSummaryCard: View {
    let audit: DarsAuditResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(audit.program ?? "Official Degree Audit")
                    .font(.headline.bold())
                    .fontDesign(.rounded)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let programCode = audit.programCode, !programCode.isEmpty {
                        DarsPill(text: programCode, color: .vtBurgundy)
                    }
                    if let catalogYear = audit.catalogYear, !catalogYear.isEmpty {
                        DarsPill(text: catalogYear, color: .blue)
                    }
                    if let auditType = audit.auditType, !auditType.isEmpty {
                        DarsPill(text: auditType, color: .purple)
                    }
                }
            }

            HStack(spacing: 12) {
                darsMetric(value: audit.universityGPA.map { String(format: "%.3f", $0) } ?? "—", label: "University GPA")
                darsMetric(value: audit.inMajorGPA.map { String(format: "%.3f", $0) } ?? "—", label: "In-Major GPA")
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func darsMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .fontDesign(.rounded)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct DarsCategoryList: View {
    let categories: [DarsCategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Official Categories")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            ForEach(categories) { category in
                DarsCategoryCard(category: category)
            }
        }
    }
}

struct DarsCategoryCard: View {
    let category: DarsCategory

    private var totalHours: Double {
        let visibleTotal = (category.completeHours ?? 0) +
            (category.inProgressHours ?? 0) +
            (category.unfulfilledHours ?? 0) +
            (category.plannedHours ?? 0)
        return max(category.requiredHours ?? visibleTotal, visibleTotal, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(category.title)
                    .font(.subheadline.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let required = category.requiredHours {
                    Text("\(formatHours(required)) hrs")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                } else if let gpa = category.gpa {
                    Text(String(format: "%.3f", gpa))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }

            DarsProgressBar(category: category, totalHours: totalHours)

            HStack(spacing: 10) {
                darsLegend("Complete", category.completeHours, .green)
                darsLegend("Progress", category.inProgressHours, .blue)
                darsLegend("Open", category.unfulfilledHours, .red)
                darsLegend("Planned", category.plannedHours, .purple)
            }

            if let note = category.notes.first {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var statusColor: Color {
        switch category.status {
        case "complete": return .green
        case "in_progress": return .blue
        case "unfulfilled": return .red
        case "planned": return .purple
        default: return Color(.systemGray)
        }
    }

    private var statusIcon: String {
        switch category.status {
        case "complete": return "checkmark.circle.fill"
        case "in_progress": return "clock.fill"
        case "unfulfilled": return "xmark.circle.fill"
        case "planned": return "calendar.badge.clock"
        default: return "questionmark.circle.fill"
        }
    }

    private func darsLegend(_ title: String, _ hours: Double?, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(title) \(formatHours(hours ?? 0))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DarsProgressBar: View {
    let category: DarsCategory
    let totalHours: Double

    private var segments: [(Double, Color)] {
        [
            (category.completeHours ?? 0, .green),
            (category.inProgressHours ?? 0, .blue),
            (category.unfulfilledHours ?? 0, .red),
            (category.plannedHours ?? 0, .purple),
        ].filter { $0.0 > 0 }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                if segments.isEmpty {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.tertiarySystemBackground))
                } else {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(segment.1)
                            .frame(width: max(4, proxy.size.width * CGFloat(segment.0 / totalHours)))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 11)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct DarsSectionList: View {
    let sections: [DarsSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Official Sections")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            ForEach(sections.prefix(12)) { section in
                DarsSectionCard(section: section)
            }
        }
    }
}

struct DarsSectionCard: View {
    let section: DarsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(section.title)
                    .font(.subheadline.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            if !section.matchedCourses.isEmpty {
                Text(section.matchedCourses.prefix(6).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !section.missingItems.isEmpty {
                Text("Missing: \(section.missingItems.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note = section.notes.first {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var statusColor: Color {
        switch section.status {
        case "complete": return .green
        case "in_progress": return .blue
        case "unfulfilled": return .red
        case "planned": return .purple
        default: return Color(.systemGray)
        }
    }

    private var statusIcon: String {
        switch section.status {
        case "complete": return "checkmark.circle.fill"
        case "in_progress": return "clock.fill"
        case "unfulfilled": return "xmark.circle.fill"
        case "planned": return "calendar.badge.clock"
        default: return "questionmark.circle.fill"
        }
    }
}

struct DarsPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

private func formatHours(_ value: Double) -> String {
    value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
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
        case math(String)
        case code(language: String, content: String)
        case graph(String)
        case resource(title: String, url: URL)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var pending = ""
        var inCode = false
        var inMath = false
        var mathEndEnvironment: String?
        var codeLang = ""
        var codeLines: [String] = []
        var mathLines: [String] = []

        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)

            if inMath {
                if let environment = mathEndEnvironment {
                    mathLines.append(line)
                    if LaTeXFormatter.endsMathEnvironment(t, environment: environment) {
                        result.append(.math(mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                        inMath = false; mathEndEnvironment = nil; mathLines = []
                    }
                } else if t == "$$" || t == "\\]" || t == "\\\\]" {
                    result.append(.math(mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                    inMath = false; mathLines = []
                } else {
                    mathLines.append(line)
                }
                continue
            }

            if inCode {
                if t.hasPrefix("```") {
                    let content = codeLines.joined(separator: "\n")
                        .trimmingCharacters(in: .newlines)
                    if codeLang.lowercased() == "graph" {
                        result.append(.graph(content))
                    } else {
                        result.append(.code(language: codeLang, content: content))
                    }
                    inCode = false; codeLang = ""; codeLines = []
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if let environment = LaTeXFormatter.startedMathEnvironment(t) {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                inMath = true
                mathEndEnvironment = environment
                mathLines = [line]
                if LaTeXFormatter.endsMathEnvironment(t, environment: environment) {
                    result.append(.math(t))
                    inMath = false; mathEndEnvironment = nil; mathLines = []
                }
                continue
            }

            if t == "$$" || t == "\\[" || t == "\\\\[" {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                inMath = true; mathLines = []
                continue
            }

            if t.hasPrefix("$$"), t.hasSuffix("$$"), t.count > 4 {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.math(String(t.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if t.hasPrefix("\\["), t.hasSuffix("\\]"), t.count > 4 {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.math(String(t.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if t.hasPrefix("\\\\["), t.hasSuffix("\\\\]"), t.count > 6 {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.math(String(t.dropFirst(3).dropLast(3)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if LaTeXFormatter.looksLikeDisplayMath(t) {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.math(t))
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
            } else if let resource = MarkdownBody.youtubeResource(from: t) {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.resource(title: resource.title, url: resource.url))
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
        if inMath, !mathLines.isEmpty {
            result.append(.math(mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if !pending.isEmpty { result.append(.paragraph(pending)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let content):
                    Text(LaTeXFormatter.inline(content).markdown)
                        .font(level == 1 ? .headline : .subheadline).fontWeight(.semibold)
                        .foregroundStyle(baseColor).padding(.top, level <= 2 ? 6 : 2)
                case .bullet(let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(baseFont).foregroundStyle(baseColor.opacity(0.6))
                        Text(LaTeXFormatter.inline(content).markdown).font(baseFont).foregroundStyle(baseColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .numbered(let number, let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(number).").font(baseFont).foregroundStyle(baseColor.opacity(0.6))
                            .frame(minWidth: 20, alignment: .trailing)
                        Text(LaTeXFormatter.inline(content).markdown).font(baseFont).foregroundStyle(baseColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let content):
                    Text(LaTeXFormatter.inline(content).markdown).font(baseFont).foregroundStyle(baseColor)
                        .fixedSize(horizontal: false, vertical: true)
                case .math(let content):
                    LaTeXMathView(content: content)
                        .padding(.vertical, 4)
                case .code(let lang, let content):
                    CodeBlockView(language: lang, code: content)
                        .padding(.vertical, 2)
                case .graph(let content):
                    GraphDiagramView(content: content)
                        .padding(.vertical, 4)
                case .resource(let title, let url):
                    ResourceLinkCard(title: title, url: url)
                        .padding(.vertical, 3)
                }
            }
        }
    }

    private static func youtubeResource(from line: String) -> (title: String, url: URL)? {
        guard line.localizedCaseInsensitiveContains("youtube.com") ||
                line.localizedCaseInsensitiveContains("youtu.be") else {
            return nil
        }

        let markdownPattern = #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#
        if let range = line.range(of: markdownPattern, options: .regularExpression) {
            let match = String(line[range])
            let title = match.replacingOccurrences(of: #"^\[([^\]]+)\].*$"#, with: "$1", options: .regularExpression)
            let urlString = match.replacingOccurrences(of: #"^.*\]\((https?://[^)\s]+)\).*$"#, with: "$1", options: .regularExpression)
            if let url = URL(string: urlString) {
                return (title, url)
            }
        }

        let urlPattern = #"https?://[^\s)]+"#
        guard let range = line.range(of: urlPattern, options: .regularExpression),
              let url = URL(string: String(line[range])) else {
            return nil
        }
        return ("YouTube resource", url)
    }
}

// MARK: - LaTeX Rendering

struct ResourceLinkCard: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.trimmingCharacters(in: CharacterSet(charactersIn: "-* ")))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(url.host() ?? "YouTube")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct GraphDiagramView: View {
    let content: String

    private var graph: SimpleGraph {
        SimpleGraph.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.caption.bold())
                    .foregroundStyle(Color.vtBurgundy)
                Text("Visual model")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            GeometryReader { proxy in
                graphCanvas(size: proxy.size)
            }
            .frame(height: 210)
        }
        .padding(14)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func graphCanvas(size: CGSize) -> some View {
        let positions = graph.positions(in: size)
        return ZStack {
            ForEach(Array(graph.edges.enumerated()), id: \.offset) { _, edge in
                if let a = positions[edge.from], let b = positions[edge.to] {
                    Path { path in
                        path.move(to: a)
                        path.addLine(to: b)
                    }
                    .stroke(
                        graph.highlightedEdges.contains(edge.normalized)
                            ? Color.vtBurgundy
                            : Color.secondary.opacity(0.45),
                        style: StrokeStyle(
                            lineWidth: graph.highlightedEdges.contains(edge.normalized) ? 3 : 1.5,
                            lineCap: .round
                        )
                    )
                }
            }

            ForEach(graph.nodes, id: \.self) { node in
                if let point = positions[node] {
                    nodeView(node, highlighted: graph.highlightedNodes.contains(node))
                        .position(point)
                }
            }
        }
    }

    private func nodeView(_ label: String, highlighted: Bool) -> some View {
        Text(label)
            .font(.caption.bold())
            .foregroundStyle(highlighted ? .white : .primary)
            .frame(width: 38, height: 38)
            .background(highlighted ? Color.vtBurgundy : Color(.secondarySystemBackground))
            .overlay(
                Circle().stroke(highlighted ? Color.vtBurgundy : Color.secondary.opacity(0.35), lineWidth: 1)
            )
            .clipShape(Circle())
            .shadow(color: highlighted ? Color.vtBurgundy.opacity(0.22) : .clear, radius: 8, y: 4)
    }
}

struct SimpleGraph {
    struct Edge: Hashable {
        let from: String
        let to: String

        var normalized: Edge {
            from <= to ? self : Edge(from: to, to: from)
        }
    }

    let nodes: [String]
    let edges: [Edge]
    let highlightedNodes: Set<String>
    let highlightedEdges: Set<Edge>

    static func parse(_ text: String) -> SimpleGraph {
        var nodes = Set<String>()
        var edges: [Edge] = []
        var highlightedNodes = Set<String>()
        var highlightedEdges = Set<Edge>()

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.lowercased().hasPrefix("highlight:") {
                let values = line.dropFirst("highlight:".count)
                    .split { $0 == "," || $0 == " " || $0 == ">" || $0 == "-" }
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                highlightedNodes.formUnion(values)
                for pair in zip(values, values.dropFirst()) {
                    highlightedEdges.insert(Edge(from: pair.0, to: pair.1).normalized)
                }
                continue
            }

            let separators = ["--", "->", "-"]
            if let separator = separators.first(where: { line.contains($0) }) {
                let parts = line.components(separatedBy: separator)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard parts.count >= 2 else { continue }
                for pair in zip(parts, parts.dropFirst()) {
                    nodes.insert(pair.0)
                    nodes.insert(pair.1)
                    edges.append(Edge(from: pair.0, to: pair.1))
                }
            } else {
                nodes.insert(line)
            }
        }

        let orderedNodes = Array(nodes).sorted()
        return SimpleGraph(
            nodes: orderedNodes,
            edges: edges,
            highlightedNodes: highlightedNodes,
            highlightedEdges: highlightedEdges
        )
    }

    func positions(in size: CGSize) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        let radius = max(58, min(size.width, size.height) * 0.36)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return Dictionary(uniqueKeysWithValues: nodes.enumerated().map { index, node in
            let angle = (Double(index) / Double(nodes.count)) * 2 * Double.pi - Double.pi / 2
            return (
                node,
                CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y + CGFloat(sin(angle)) * radius
                )
            )
        })
    }
}

struct LaTeXMathView: View {
    let content: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if let matrix = LaTeXFormatter.matrix(from: content) {
                    matrixView(matrix)
                } else if let cases = LaTeXFormatter.cases(from: content) {
                    casesView(cases)
                } else {
                    Text(LaTeXFormatter.display(content))
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func matrixView(_ matrix: LaTeXFormatter.Matrix) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(matrix.leftBracket)
                .font(.system(size: CGFloat(max(34, matrix.rows.count * 20)), weight: .light, design: .serif))
                .foregroundStyle(.secondary)

            VStack(alignment: .center, spacing: 8) {
                ForEach(Array(matrix.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 18) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            if cell == LaTeXFormatter.dividerCell {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.6))
                                    .frame(width: 1, height: 24)
                                    .padding(.horizontal, 2)
                            } else {
                                Text(LaTeXFormatter.display(cell))
                                    .font(.system(.body, design: .serif))
                                    .frame(minWidth: 24, alignment: .center)
                            }
                        }
                    }
                }
            }

            Text(matrix.rightBracket)
                .font(.system(size: CGFloat(max(34, matrix.rows.count * 20)), weight: .light, design: .serif))
                .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }

    private func casesView(_ cases: LaTeXFormatter.Cases) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("{")
                .font(.system(size: CGFloat(max(46, cases.rows.count * 24)), weight: .light, design: .serif))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(cases.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(LaTeXFormatter.display(row.expression))
                            .font(.system(.body, design: .serif))
                        if let condition = row.condition {
                            Text(LaTeXFormatter.display(condition))
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

enum LaTeXFormatter {
    static let dividerCell = "__HA_MATRIX_DIVIDER__"

    struct Matrix {
        let rows: [[String]]
        let leftBracket: String
        let rightBracket: String
    }

    struct Cases {
        struct Row {
            let expression: String
            let condition: String?
        }

        let rows: [Row]
    }

    static func inline(_ text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "$", let end = text[text.index(after: index)...].firstIndex(of: "$") {
                let math = String(text[text.index(after: index)..<end])
                output += display(math)
                index = text.index(after: end)
            } else if text[index...].hasPrefix("\\("),
                      let range = text[index...].range(of: "\\)") {
                let start = text.index(index, offsetBy: 2)
                let math = String(text[start..<range.lowerBound])
                output += display(math)
                index = range.upperBound
            } else {
                output.append(text[index])
                index = text.index(after: index)
            }
        }

        return output
    }

    static func display(_ latex: String) -> String {
        var value = repairMalformedMathSyntax(normalizeEscapes(latex))
            .replacingOccurrences(of: "\\left", with: "")
            .replacingOccurrences(of: "\\right", with: "")
            .replacingOccurrences(of: "\\,", with: " ")
            .replacingOccurrences(of: "\\;", with: " ")
            .replacingOccurrences(of: "\\quad", with: " ")
            .replacingOccurrences(of: "\\cdot", with: "·")
            .replacingOccurrences(of: "\\times", with: "×")
            .replacingOccurrences(of: "\\div", with: "÷")
            .replacingOccurrences(of: "\\leq", with: "≤")
            .replacingOccurrences(of: "\\geq", with: "≥")
            .replacingOccurrences(of: "\\neq", with: "≠")
            .replacingOccurrences(of: "\\approx", with: "≈")
            .replacingOccurrences(of: "\\rightarrow", with: "→")
            .replacingOccurrences(of: "\\to", with: "→")
            .replacingOccurrences(of: "\\infty", with: "∞")
            .replacingOccurrences(of: "\\pi", with: "π")
            .replacingOccurrences(of: "\\theta", with: "θ")
            .replacingOccurrences(of: "\\lambda", with: "λ")
            .replacingOccurrences(of: "\\mu", with: "μ")
            .replacingOccurrences(of: "\\sigma", with: "σ")
            .replacingOccurrences(of: "\\alpha", with: "α")
            .replacingOccurrences(of: "\\beta", with: "β")
            .replacingOccurrences(of: "\\gamma", with: "γ")
            .replacingOccurrences(of: "\\Delta", with: "Δ")
            .replacingOccurrences(of: "\\nabla", with: "∇")

        value = replaceFractions(in: value)
        value = value
            .replacingOccurrences(of: #"\\begin\{[^}]+\}(\{[^}]*\})?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\end\{[^}]+\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\\\", with: "\n")
            .replacingOccurrences(of: "&", with: "  ")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    static func looksLikeDisplayMath(_ latex: String) -> Bool {
        let normalized = repairMalformedMathSyntax(normalizeEscapes(latex))
        return normalized.contains("\\begin{") &&
            (normalized.contains("matrix}") || normalized.contains("array}") || normalized.contains("cases}"))
    }

    static func startedMathEnvironment(_ latex: String) -> String? {
        let normalized = repairMalformedMathSyntax(normalizeEscapes(latex))
        guard let range = normalized.range(
            of: #"\\begin\{(bmatrix|pmatrix|vmatrix|matrix|array|cases|case)\}"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let command = String(normalized[range])
        return command
            .replacingOccurrences(of: "\\begin{", with: "")
            .replacingOccurrences(of: "}", with: "")
    }

    static func endsMathEnvironment(_ latex: String, environment: String) -> Bool {
        let normalized = repairMalformedMathSyntax(normalizeEscapes(latex))
        return normalized.contains("\\end{\(environment)}")
    }

    static func matrix(from latex: String) -> Matrix? {
        let normalized = repairMalformedMathSyntax(normalizeEscapes(latex))
            .replacingOccurrences(of: "\\[", with: "")
            .replacingOccurrences(of: "\\]", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let beginRange = normalized.range(of: #"\\begin\{([bpv]?matrix|array)\}(\{[^}]*\})?"#, options: .regularExpression),
              let endRange = normalized.range(of: #"\\end\{([bpv]?matrix|array)\}"#, options: .regularExpression) else {
            return nil
        }

        let beginCommand = String(normalized[beginRange])
        let inner = String(normalized[beginRange.upperBound..<endRange.lowerBound])
        let rowSegments = inner.contains("\\\\")
            ? inner.components(separatedBy: "\\\\")
            : inner.components(separatedBy: .newlines)
        let dividerIndex = dividerColumnIndex(for: beginCommand)
        let rows = rowSegments
            .map { row in
                parseMatrixRow(String(row), dividerIndex: dividerIndex)
            }
            .filter { !$0.isEmpty }

        guard !rows.isEmpty else { return nil }
        let brackets = bracketsForEnvironment(beginCommand)
        return Matrix(rows: rows, leftBracket: brackets.left, rightBracket: brackets.right)
    }

    static func cases(from latex: String) -> Cases? {
        let normalized = repairMalformedMathSyntax(normalizeEscapes(latex))
            .replacingOccurrences(of: "\\[", with: "")
            .replacingOccurrences(of: "\\]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let beginRange = normalized.range(of: #"\\begin\{cases?\}"#, options: .regularExpression),
              let endRange = normalized.range(of: #"\\end\{cases?\}"#, options: .regularExpression) else {
            return nil
        }

        let inner = String(normalized[beginRange.upperBound..<endRange.lowerBound])
        let rowSegments = inner.contains("\\\\")
            ? inner.components(separatedBy: "\\\\")
            : inner.components(separatedBy: .newlines)

        let rows = rowSegments
            .flatMap { row -> [Cases.Row] in
                let cells = row.split(separator: "&", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard let expression = cells.first else { return [] }
                let condition = cells.count > 1 ? cells.dropFirst().joined(separator: "  ") : nil
                return [Cases.Row(expression: expression, condition: condition)]
            }

        guard !rows.isEmpty else { return nil }
        return Cases(rows: rows)
    }

    private static func replaceFractions(in input: String) -> String {
        var value = input
        let pattern = #"\\frac\{([^{}]+)\}\{([^{}]+)\}"#
        while let range = value.range(of: pattern, options: .regularExpression) {
            let match = String(value[range])
            let parts = match.replacingOccurrences(of: "\\frac{", with: "")
                .dropLast()
                .components(separatedBy: "}{")
            guard parts.count == 2 else { break }
            value.replaceSubrange(range, with: "(\(parts[0]))/(\(parts[1]))")
        }
        return value
    }

    private static func parseMatrixRow(_ row: String, dividerIndex: Int? = nil) -> [String] {
        let cells = row.split(separator: "&", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var parsed: [String] = []
        for (index, cell) in cells.enumerated() {
            if let dividerIndex, index == dividerIndex {
                parsed.append(dividerCell)
            }
            if cell == "|" {
                parsed.append(dividerCell)
            } else if !cell.isEmpty {
                parsed.append(cell)
            }
        }
        return parsed
    }

    private static func dividerColumnIndex(for command: String) -> Int? {
        guard let specRange = command.range(of: #"\{[clr|]+\}"#, options: .regularExpression) else {
            return nil
        }
        let spec = command[specRange].filter { $0 != "{" && $0 != "}" }
        guard let divider = spec.firstIndex(of: "|") else { return nil }
        return spec[..<divider].filter { $0 == "c" || $0 == "l" || $0 == "r" }.count
    }

    private static func bracketsForEnvironment(_ command: String) -> (left: String, right: String) {
        if command.contains("pmatrix") { return ("(", ")") }
        if command.contains("vmatrix") { return ("|", "|") }
        return ("[", "]")
    }

    private static func normalizeEscapes(_ latex: String) -> String {
        latex
            .replacingOccurrences(of: "\\\\[", with: "\\[")
            .replacingOccurrences(of: "\\\\]", with: "\\]")
            .replacingOccurrences(of: "\\\\begin", with: "\\begin")
            .replacingOccurrences(of: "\\\\end", with: "\\end")
    }

    private static func repairMalformedMathSyntax(_ latex: String) -> String {
        var value = latex

        for environment in ["array", "bmatrix", "pmatrix", "vmatrix", "matrix", "cases", "case"] {
            value = value.replacingOccurrences(of: "\\end\(environment)", with: "\\end{\(environment)}")
        }

        let braceEnvironments = ["bmatrix", "pmatrix", "vmatrix", "matrix", "cases", "case"]
        for environment in braceEnvironments {
            let malformed = "\\begin\(environment)"
            while let range = value.range(of: malformed) {
                value.replaceSubrange(range, with: "\\begin{\(environment)}")
            }
        }

        while let range = value.range(of: "\\beginarray") {
            var cursor = range.upperBound
            var columnSpec = ""
            let allowedSpecCharacters = Set("clr|")

            while cursor < value.endIndex, allowedSpecCharacters.contains(value[cursor]) {
                columnSpec.append(value[cursor])
                cursor = value.index(after: cursor)
            }

            let replacement = columnSpec.isEmpty ? "\\begin{array}" : "\\begin{array}{\(columnSpec)}"
            value.replaceSubrange(range.lowerBound..<cursor, with: replacement)
        }

        return value
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
#Preview("Audit — Empty") { DegreeAuditView().environmentObject(AppState()) }
