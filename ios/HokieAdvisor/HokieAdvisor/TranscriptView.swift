import SwiftUI
import UniformTypeIdentifiers

struct TranscriptView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = TranscriptViewModel()
    @AppStorage("graduationYear") private var graduationYear = ""
    @State private var showFilePicker = false
    @State private var newStrugglingCourse = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                transcriptHeader

                if vm.isLoading {
                    loadingView.padding(.horizontal, 20)
                } else if let error = vm.errorMessage {
                    statusCard(icon: "exclamationmark.triangle.fill", iconColor: .orange,
                               title: vm.errorTitle, subtitle: error)
                        .padding(.horizontal, 20)
                    primaryButton(title: "Try Again", icon: "arrow.up.doc.fill") {
                        vm.reset(); showFilePicker = true
                    }
                    .padding(.horizontal, 20)
                } else if appState.hasTranscript {
                    successBanner.padding(.horizontal, 20)
                    if !appState.activeSemesterCourses.isEmpty {
                        inProgressSection.padding(.horizontal, 20)
                    }
                    if !appState.registeredUpcomingCourses.isEmpty {
                        plannedCoursesSection.padding(.horizontal, 20)
                    }
                    if appState.isSemesterInSession {
                        semesterStatusSection.padding(.horizontal, 20)
                    }
                    courseListSection.padding(.horizontal, 20)
                    reuploadButton.padding(.horizontal, 20)
                } else {
                    uploadPrompt.padding(.horizontal, 20)
                }

                Spacer(minLength: HokieChrome.contentBottomInset)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .hokieScreenBackground()
        .swipeDownToDismissKeyboard()
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
            appState.plannedCourses = result.planned_courses ?? []
            appState.transcriptNotes = result.warnings
            appState.inProgressGrades = [:]
            appState.hasTranscript = true
            appState.passingAllClasses = nil
            appState.strugglingCourses = []
            appState.latestDegreeAudit = nil
            if let inferred = inferredGradYear(from: result.courses) {
                graduationYear = String(inferred)
            }
        }
    }

    // MARK: - Header

    private var transcriptHeader: some View {
        HokiePageHeader(
            title: "Transcript",
            eyebrow: "Course record",
            subtitle: "Upload once, then let the app read your CS path.",
            symbol: "doc.text.fill",
            accent: .vtOrange,
            stat: transcriptHeaderStat
        ) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.primary.opacity(0.82))
                    .frame(width: 38, height: 38)
                    .glassCapsule(strokeOpacity: 0.08)
            }
            .accessibilityLabel("Close transcript import")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var transcriptHeaderStat: HokieHeaderStat {
        if appState.hasTranscript {
            return HokieHeaderStat(value: "\(appState.transcriptCourses.count)", label: "courses parsed", icon: "checkmark.seal.fill")
        }
        return HokieHeaderStat(value: "PDF", label: "PNG or JPG", icon: "arrow.up.doc.fill")
    }

    // MARK: - Upload Prompt

    private var uploadPrompt: some View {
        VStack(spacing: 16) {
            Button {
                vm.reset(); showFilePicker = true
            } label: {
                HStack(spacing: 16) {
                    HokieIconTile(symbol: "arrow.up.doc.fill", color: .vtBurgundy, size: 58)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Upload Transcript")
                            .font(.title3.weight(.black))
                            .fontDesign(.rounded)
                            .foregroundStyle(.primary)
                        Text("PDF, PNG, or JPG")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.black))
                        .foregroundStyle(Color.vtOrange.opacity(0.8))
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .glassSurface(cornerRadius: 30)
            }
            .buttonStyle(.plain)

            VStack(spacing: 14) {
                featureRow(icon: "brain.head.profile", text: "AI-powered parsing — no manual entry needed")
                featureRow(icon: "calendar.badge.checkmark", text: "Feeds directly into your course plan")
                featureRow(icon: "lock.fill", text: "Used only to build your planning workspace")
            }
            .padding(20)
            .glassSurface(cornerRadius: 28)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            circleIcon(icon, color: .vtBurgundy, size: 38)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func primaryButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.body.bold())
                Text(title).font(.body.bold())
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .foregroundStyle(Color.vtBurgundy)
            .glassCapsule(strokeOpacity: 0.08)
        }
        .buttonStyle(.plain)
    }

    private var reuploadButton: some View {
        Button {
            vm.reset()
            appState.hasTranscript = false
            appState.transcriptCourses = []
            appState.inProgressCourses = []
            appState.plannedCourses = []
            appState.transcriptNotes = []
            appState.latestDegreeAudit = nil
            showFilePicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.subheadline.bold())
                Text("Re-upload Transcript").font(.subheadline.bold())
            }
            .foregroundStyle(Color.vtBurgundy)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .glassCapsule(strokeOpacity: 0.08)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Success Banner

    private var successBanner: some View {
        HStack(spacing: 14) {
            circleIcon("checkmark.seal.fill", color: .green)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(appState.transcriptCourses.count) courses found")
                    .font(.subheadline.bold())
                Text("\(Int(appState.totalCredits)) total credit hours parsed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let gpa = appState.calculatedGPA {
                VStack(spacing: 2) {
                    Text(String(format: "%.2f", gpa))
                        .font(.title2.bold()).fontDesign(.rounded)
                        .foregroundStyle(gpaColor(gpa))
                    Text("GPA").font(.caption2.bold()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .glassSurface(cornerRadius: 24)
    }

    // MARK: - In-Progress Courses

    private var inProgressSection: some View {
        let courses = appState.activeSemesterCourses
        return VStack(alignment: .leading, spacing: 16) {
            SectionLabel(title: "Currently Enrolled", icon: "clock.badge.fill", color: .orange)

            if let sem = appState.currentVTSemester {
                Text("\(sem) — \(courses.count) course\(courses.count == 1 ? "" : "s"). How are they going?")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            ForEach(courses) { inProgressCourseRow(course: $0) }

            Text("Your current grades help the advisor decide which prereqs you'll have completed by next semester.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(20)
        .glassSurface(cornerRadius: 28)
    }

    private var plannedCoursesSection: some View {
        let courses = appState.registeredUpcomingCourses
        return VStack(alignment: .leading, spacing: 16) {
            SectionLabel(title: "Registered — Not Started", icon: "calendar.badge.plus", color: .blue)

            Text("You're registered for \(courses.count) course\(courses.count == 1 ? "" : "s") in a future semester.")
                .font(.subheadline).foregroundStyle(.secondary)

            ForEach(courses) { course in
                HStack(spacing: 10) {
                    Text(course.code)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.vtOrange)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.vtOrange.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.vtOrange.opacity(0.18), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name).font(.subheadline.bold()).lineLimit(1)
                        if let sem = course.semester {
                            Text(sem).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }

            Text("These courses haven't started yet — grades will appear once you begin the semester.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(20)
        .glassSurface(cornerRadius: 28)
    }

    private func inProgressCourseRow(course: InProgressCourse) -> some View {
        let grades = ["A", "B", "C", "D", "F"]
        let selected = appState.inProgressGrades[course.code]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(course.code)
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.vtBurgundy)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.vtBurgundy.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Color.vtBurgundy.opacity(0.18), lineWidth: 1))
                Text(course.name).font(.subheadline.bold()).lineLimit(1)
            }
            HStack(spacing: 8) {
                ForEach(grades, id: \.self) { grade in
                    let isSelected = selected == grade
                    let color: Color = grade == "D" || grade == "F" ? .red : (grade == "C" ? .orange : .green)
                    Button {
                        appState.inProgressGrades[course.code] = isSelected ? nil : grade
                    } label: {
                        Text(grade).font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(isSelected ? .white : color)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(color.gradient)
                                        .shadow(color: color.opacity(0.16), radius: 8, x: 0, y: 4)
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(color.opacity(0.08))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.12), lineWidth: 1))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Semester Status

    private var semesterStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(title: "Current Semester", icon: "calendar", color: .vtBurgundy)

            Text("How are your current classes going?")
                .font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                statusToggle(title: "All Good", icon: "checkmark.circle.fill",
                             isSelected: appState.passingAllClasses == true, color: .green) {
                    withAnimation { appState.passingAllClasses = true; appState.strugglingCourses = [] }
                }
                statusToggle(title: "Struggling", icon: "exclamationmark.triangle.fill",
                             isSelected: appState.passingAllClasses == false, color: .orange) {
                    withAnimation { appState.passingAllClasses = false }
                }
            }

            if appState.passingAllClasses == false {
                strugglingCoursesInput
            }
        }
        .padding(20)
        .glassSurface(cornerRadius: 28)
    }

    private func statusToggle(title: String, icon: String, isSelected: Bool,
                               color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).fontWeight(.semibold)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .foregroundStyle(isSelected ? .white : color)
            .background {
                if isSelected {
                    Capsule()
                        .fill(color.gradient)
                        .shadow(color: color.opacity(0.16), radius: 8, x: 0, y: 4)
                } else {
                    Capsule()
                        .fill(color.opacity(0.08))
                        .overlay(Capsule().stroke(color.opacity(0.14), lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var strugglingCoursesInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which courses are you struggling with?")
                .font(.caption.bold()).foregroundStyle(.secondary)
                .textCase(.uppercase).tracking(0.5)

            if !appState.strugglingCourses.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(appState.strugglingCourses, id: \.self) { course in
                        HStack(spacing: 4) {
                            Text(course).font(.caption.bold())
                            Button {
                                appState.strugglingCourses.removeAll { $0 == course }
                            } label: {
                                Image(systemName: "xmark").font(.caption2)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(Color.vtOrange)
                        .background(Color.vtOrange.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.vtOrange.opacity(0.18), lineWidth: 1))
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("e.g. CS 3114", text: $newStrugglingCourse)
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .glassCapsule(strokeOpacity: 0.06)
                    .submitLabel(.done)
                    .onSubmit { addStrugglingCourse() }

                Button(action: addStrugglingCourse) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(newStrugglingCourse.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.hokieStone.opacity(0.45) : Color.vtOrange)
                }
                .disabled(newStrugglingCourse.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if appState.needsTutoringSupport {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill").foregroundStyle(.orange)
                    Text("Go to Audit tab to get tutoring resources.")
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

    // MARK: - Course List

    private var courseListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(title: "Completed Courses", icon: "checkmark.circle.fill", color: .vtBurgundy)

            ForEach(appState.semesterGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.semester)
                        .font(.caption.bold()).foregroundStyle(.secondary)
                        .textCase(.uppercase).tracking(0.5).padding(.leading, 4)
                    ForEach(group.courses) { TranscriptCourseCard(course: $0) }
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5).tint(Color.vtBurgundy)
            Text("Parsing your transcript...")
                .font(.headline.bold()).fontDesign(.rounded)
            Text("AI is reading your course history")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).frame(height: 200)
        .glassSurface(cornerRadius: 32)
    }

    // MARK: - Grad Year Inference

    private func inferredGradYear(from courses: [TranscriptCourse]) -> Int? {
        let startYear = courses.compactMap { course -> Int? in
            guard let semester = course.semester,
                  semester.lowercased() != "transfer" else { return nil }
            let parts = semester.split(separator: " ")
            guard parts.count == 2, let year = Int(parts[1]) else { return nil }
            return year
        }.min()
        guard let year = startYear else { return nil }
        return year + 4
    }

    // MARK: - File Handling

    private func handlePickedFile(_ pickerResult: Result<[URL], Error>) {
        switch pickerResult {
        case .failure(let error):
            vm.errorTitle = "File picker failed"
            vm.errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                vm.errorTitle = "File read failed"
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

// MARK: - Flow Layout

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
                rows.append([]); rowWidth = 0
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
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(course.code)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.vtBurgundy)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.vtBurgundy.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.vtBurgundy.opacity(0.18), lineWidth: 1))

                    if let grade = course.grade {
                        let badgeColor = gradeColor(grade)
                        Text(grade)
                            .font(.caption.weight(.black))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(badgeColor.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(badgeColor.opacity(0.18), lineWidth: 1))
                    }
                }
                Text(course.name).font(.subheadline.bold()).lineLimit(2)
                if let credits = course.credits {
                    Text("\(credits, specifier: "%.0f") credits").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(16)
        .glassSurface(cornerRadius: 20)
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

// MARK: - Previews

#Preview("Transcript — Empty") { TranscriptView().environmentObject(AppState()) }

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
