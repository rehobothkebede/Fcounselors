import SwiftUI
import UniformTypeIdentifiers

struct TranscriptView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = TranscriptViewModel()
    @State private var showFilePicker = false
    @State private var newStrugglingCourse = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    heroHeader

                    VStack(spacing: 20) {
                        if vm.isLoading {
                            loadingView
                        } else if let error = vm.errorMessage {
                            errorView(message: error)
                            uploadButton
                        } else if appState.hasTranscript {
                            successBanner
                            if !appState.inProgressCourses.isEmpty {
                                inProgressSection
                            }
                            semesterStatusSection
                            courseListSection
                            reuploadButton
                        } else {
                            uploadPrompt
                        }
                    }
                    .padding()
                }
            }
            .background { LinearGradient.vtBackground.ignoresSafeArea() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .png, .jpeg],
            allowsMultipleSelection: false,
            onCompletion: handlePickedFile
        )
        .onChange(of: vm.result) { _, result in
            guard let result = result else { return }
            appState.transcriptCourses = result.courses
            appState.inProgressCourses = result.in_progress_courses
            appState.inProgressGrades = [:]
            appState.hasTranscript = true
            appState.passingAllClasses = nil
            appState.strugglingCourses = []
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transcript")
                            .font(.largeTitle).fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text("Your CS course history, automatically parsed")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 28)
            .background(LinearGradient.vtHeader)
        }
    }

    // MARK: - Upload Prompt (empty state)

    private var uploadPrompt: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.vtBurgundyMuted)
                        .frame(height: 180)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(
                                    Color.vtBurgundy.opacity(0.4),
                                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                                )
                        )

                    VStack(spacing: 12) {
                        Image(systemName: "arrow.up.doc.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.vtBurgundy)
                        Text("Upload Your Transcript")
                            .font(.headline).fontWeight(.bold)
                        Text("PDF, PNG, or JPG")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .onTapGesture {
                    vm.reset()
                    showFilePicker = true
                }

                Button {
                    vm.reset()
                    showFilePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc.fill")
                        Text("Choose File")
                            .fontWeight(.semibold)
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.vtBurgundy)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            VStack(spacing: 12) {
                featureRow(icon: "brain.head.profile", text: "AI-powered parsing — no manual entry needed")
                featureRow(icon: "calendar.badge.checkmark", text: "Feeds directly into your course plan")
                featureRow(icon: "lock.fill", text: "Processed securely, never stored")
            }
            .padding(16)
            .glassCard(cornerRadius: 16)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.vtBurgundy)
                .frame(width: 20)
            Text(text)
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: - Upload Button (shown after errors)

    private var uploadButton: some View {
        Button {
            vm.reset()
            showFilePicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.doc.fill")
                Text("Try Again")
                    .fontWeight(.semibold)
            }
            .font(.body)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.vtBurgundy)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var reuploadButton: some View {
        Button {
            vm.reset()
            appState.hasTranscript = false
            appState.transcriptCourses = []
            showFilePicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Re-upload Transcript")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundStyle(Color.vtBurgundy)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.vtBurgundyMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Success Banner

    private var successBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(appState.transcriptCourses.count) courses found")
                    .font(.subheadline).fontWeight(.semibold)
                Text("\(Int(appState.totalCredits)) total credit hours parsed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 12, accent: .green)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.4), lineWidth: 1.5))
    }

    // MARK: - In-Progress Courses Section

    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Currently Enrolled", icon: "clock.badge.fill", color: .orange)

            Text("We found \(appState.inProgressCourses.count) in-progress course\(appState.inProgressCourses.count == 1 ? "" : "s"). How are they going?")
                .font(.subheadline).foregroundStyle(.secondary)

            ForEach(appState.inProgressCourses) { course in
                inProgressCourseRow(course: course)
            }

            Text("Your current grades help the advisor decide which prereqs you'll have completed by next semester.")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    private func inProgressCourseRow(course: InProgressCourse) -> some View {
        let grades = ["A", "B", "C", "D", "F"]
        let selected = appState.inProgressGrades[course.code]

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(course.code)
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(Color.vtBurgundy)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.vtBurgundyMuted)
                    .clipShape(Capsule())
                Text(course.name)
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                ForEach(grades, id: \.self) { grade in
                    let isSelected = selected == grade
                    let color: Color = grade == "D" || grade == "F" ? .red : (grade == "C" ? .orange : .green)
                    Button {
                        appState.inProgressGrades[course.code] = isSelected ? nil : grade
                    } label: {
                        Text(grade)
                            .font(.subheadline).fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? color : color.opacity(0.1))
                            .foregroundStyle(isSelected ? .white : color)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Semester Status Section

    private var semesterStatusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Current Semester", icon: "calendar", color: .vtBurgundy)

            Text("How are your current classes going?")
                .font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                statusButton(
                    title: "All Good",
                    icon: "checkmark.circle.fill",
                    isSelected: appState.passingAllClasses == true,
                    color: .green
                ) {
                    withAnimation { appState.passingAllClasses = true; appState.strugglingCourses = [] }
                }
                statusButton(
                    title: "Struggling",
                    icon: "exclamationmark.triangle.fill",
                    isSelected: appState.passingAllClasses == false,
                    color: .orange
                ) {
                    withAnimation { appState.passingAllClasses = false }
                }
            }

            if appState.passingAllClasses == false {
                strugglingCoursesInput
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    private func statusButton(title: String, icon: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(isSelected ? .white : color)
                Text(title).fontWeight(.semibold)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color : color.opacity(0.1))
            .foregroundColor(isSelected ? .white : color)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : color.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var strugglingCoursesInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which courses are you struggling with?")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if !appState.strugglingCourses.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(appState.strugglingCourses, id: \.self) { course in
                        HStack(spacing: 4) {
                            Text(course)
                                .font(.caption).fontWeight(.semibold)
                            Button {
                                appState.strugglingCourses.removeAll { $0 == course }
                            } label: {
                                Image(systemName: "xmark").font(.caption2)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 1))
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("e.g. CS 3114", text: $newStrugglingCourse)
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .glassCard(cornerRadius: 10)
                    .submitLabel(.done)
                    .onSubmit { addStrugglingCourse() }

                Button(action: addStrugglingCourse) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(newStrugglingCourse.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.gray.opacity(0.4) : Color.orange)
                }
                .disabled(newStrugglingCourse.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if appState.needsTutoringSupport {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill").foregroundStyle(.orange)
                    Text("Go to Plan tab to get tutoring resources for these courses.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func addStrugglingCourse() {
        let trimmed = newStrugglingCourse.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty, !appState.strugglingCourses.contains(trimmed) else { return }
        appState.strugglingCourses.append(trimmed)
        newStrugglingCourse = ""
    }

    // MARK: - Course List (grouped by semester)

    private var courseListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Completed Courses", icon: "checkmark.circle.fill", color: .vtBurgundy)

            if let result = vm.result, !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.warnings, id: \.self) { WarningCard(text: $0) }
                }
            }

            ForEach(appState.semesterGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.semester)
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.leading, 4)

                    ForEach(group.courses) { course in
                        TranscriptCourseCard(course: course)
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.vtBurgundyMuted)
                        .frame(height: 180)

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color.vtBurgundy)
                        Text("Parsing your transcript...")
                            .font(.headline).foregroundStyle(.secondary)
                        Text("AI is reading your course history")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Could not parse transcript")
                    .font(.subheadline).fontWeight(.semibold)
                Text(message)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - File Handling

    private func handlePickedFile(_ pickerResult: Result<[URL], Error>) {
        switch pickerResult {
        case .failure(let error):
            vm.errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                vm.errorMessage = "Could not read the selected file."
                return
            }
            let mime: String
            switch url.pathExtension.lowercased() {
            case "pdf": mime = "application/pdf"
            case "png": mime = "image/png"
            default: mime = "image/jpeg"
            }
            Task { await vm.upload(fileData: data, mimeType: mime, fileName: url.lastPathComponent) }
        }
    }
}

// MARK: - Flow Layout (for course chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(width: proposal.width ?? 0, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }
            .reduce(0) { $0 + $1 + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(width: CGFloat, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var rowWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width, !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(subview)
            rowWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Transcript Course Card

struct TranscriptCourseCard: View {
    let course: TranscriptCourse

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(course.code)
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(Color.vtBurgundy)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.vtBurgundyMuted)
                        .clipShape(Capsule())

                    if let grade = course.grade {
                        Text(grade)
                            .font(.caption).fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(gradeColor(grade))
                            .clipShape(Capsule())
                    }
                }
                Text(course.name)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(2)

                if let credits = course.credits {
                    Text("\(credits, specifier: "%.0f") credits")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: 12)
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A", "A+": return .green
        case "A-", "B+", "B": return Color(red: 0.2, green: 0.6, blue: 0.2)
        case "B-", "C+", "C": return .orange
        case "C-", "D+", "D", "D-": return .red.opacity(0.8)
        case "P", "CR", "TR", "T": return Color.vtBurgundy
        default: return .gray
        }
    }
}

#Preview("Transcript — Empty") {
    TranscriptView()
        .environmentObject(AppState())
}

#Preview("Transcript — Loaded") {
    let state = AppState()
    state.hasTranscript = true
    state.transcriptCourses = [
        TranscriptCourse(code: "CS 1114", name: "Intro to Software Design", credits: 3, grade: "A", semester: "Fall 2023"),
        TranscriptCourse(code: "MATH 1225", name: "Calculus I", credits: 3, grade: "B+", semester: "Fall 2023"),
        TranscriptCourse(code: "CS 2114", name: "Software Design & Data Structures", credits: 3, grade: "A-", semester: "Spring 2024"),
    ]
    return TranscriptView().environmentObject(state)
}
