import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @AppStorage("studentName") private var studentName = ""
    @AppStorage("graduationYear") private var graduationYear = ""
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("vtEmail") private var vtEmail = ""
    @AppStorage("vtPID") private var vtPID = ""
    @AppStorage("onboardingComplete") private var onboardingComplete = true
    @AppStorage("appPasswordHash") private var appPasswordHash = ""

    @State private var showClearDataAlert = false
    @State private var showResetAlert = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showTranscriptImport = false
    @State private var showMemoryEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileCard.padding(.top, 8)
                    settingsGroup(title: "Appearance") { appearanceSection }
                    settingsGroup(title: "Academic") { academicSection }
                    settingsGroup(title: "Transcript") { transcriptSection }
                    settingsGroup(title: "Chat Memory") { chatMemorySection }
                    settingsGroup(title: "About") { aboutSection }
                    settingsGroup(title: "") { dangerSection }

                    Text("Hokie Advisor · v1.0.0\nA Virginia Tech Academic Advising Tool")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)

                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemBackground))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
        .swipeDownToDismissKeyboard()
        .sheet(isPresented: $showTranscriptImport) {
            TranscriptView().environmentObject(appState)
        }
        .sheet(isPresented: $showMemoryEditor) {
            ChatMemoryEditorView()
                .environmentObject(chatHistory)
        }
        .sheet(isPresented: $showTerms) {
            LegalSheet(title: "Terms of Service", content: termsBody)
        }
        .sheet(isPresented: $showPrivacy) {
            LegalSheet(title: "Privacy Policy", content: privacyBody)
        }
        .alert("Clear All Data", isPresented: $showClearDataAlert) {
            Button("Clear Everything", role: .destructive) {
                appState.transcriptCourses = []
                appState.inProgressCourses = []
                appState.plannedCourses = []
                appState.transcriptNotes = []
                appState.inProgressGrades = [:]
                appState.hasTranscript = false
                appState.passingAllClasses = nil
                appState.strugglingCourses = []
                chatHistory.deleteAll()
                Task { await SupabaseAuthService.shared.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your transcript, academic data, saved chat history, and chat memories will be removed from this device. This cannot be undone.")
        }
        .alert("Reset Account", isPresented: $showResetAlert) {
            Button("Reset & Restart", role: .destructive) {
                appState.transcriptCourses = []
                appState.inProgressCourses = []
                appState.plannedCourses = []
                appState.transcriptNotes = []
                appState.inProgressGrades = [:]
                appState.hasTranscript = false
                appState.passingAllClasses = nil
                appState.strugglingCourses = []
                appState.major = ""
                chatHistory.deleteAll()
                Task { await SupabaseAuthService.shared.signOut() }
                appPasswordHash = ""
                vtEmail = ""
                vtPID = ""
                onboardingComplete = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will erase all your data and return you to the setup screen.")
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.vtBurgundy).frame(width: 80, height: 80)
                Text(initials).font(.title.bold()).foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                TextField("Your Name", text: $studentName)
                    .font(.title3.bold()).fontDesign(.rounded)
                    .multilineTextAlignment(.center)

                if !vtEmail.isEmpty {
                    Text(vtEmail)
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let gpa = appState.calculatedGPA {
                    Text(String(format: "%.2f GPA", gpa))
                        .font(.subheadline.bold())
                        .foregroundStyle(gpaColor(gpa))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Virginia Tech")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.vtBurgundy).clipShape(Capsule())

                    if !appState.major.isEmpty {
                        Text(appState.major)
                            .font(.caption.bold()).foregroundStyle(Color.vtBurgundy)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.vtBurgundy.opacity(0.1)).clipShape(Capsule())
                    }

                    if !graduationYear.isEmpty {
                        Text("'\(String(graduationYear.suffix(2)))")
                            .font(.caption.bold()).foregroundStyle(Color.blue)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.blue.opacity(0.1)).clipShape(Capsule())
                    }

                    if !vtPID.isEmpty {
                        Text("PID: \(vtPID)")
                            .font(.caption.bold()).foregroundStyle(Color(.systemGray))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color(.systemGray4)).clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }

    private var initials: String {
        let parts = studentName.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.isEmpty { return "HK" }
        if parts.count == 1 { return String(parts[0].prefix(2)).uppercased() }
        return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        row(icon: "moon.stars.fill", iconColor: .purple, label: "Theme") {
            Picker("", selection: $appearanceMode) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
        }
    }

    // MARK: - Academic

    private var academicSection: some View {
        row(icon: "calendar", iconColor: .blue, label: "Grad Year") {
            TextField("From transcript", text: $graduationYear)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(spacing: 0) {
            if appState.hasTranscript {
                row(icon: "doc.text.fill", iconColor: .green, label: "Transcript") {
                    Text("\(appState.transcriptCourses.count) courses · \(Int(appState.totalCredits)) cr")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Button { showTranscriptImport = true } label: {
                    row(icon: "arrow.up.doc.fill", iconColor: .vtBurgundy, label: "Import Transcript") {
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Chat Memory

    private var chatMemorySection: some View {
        VStack(spacing: 0) {
            row(icon: "brain.head.profile", iconColor: .vtBurgundy, label: "Saved Chats") {
                Text("\(chatHistory.sessions.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            divider
            Button { showMemoryEditor = true } label: {
                row(icon: "sparkles", iconColor: .purple, label: "Saved Memories") {
                    HStack(spacing: 8) {
                        Text("\(chatHistory.memories.count)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                }
            }

            if appState.hasTranscript {
                divider
                row(icon: "person.text.rectangle.fill", iconColor: .blue, label: "Transcript Context") {
                    Text("\(appState.transcriptCourses.count) courses")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if !chatHistory.recentMemoryHighlights.isEmpty {
                divider
                VStack(alignment: .leading, spacing: 10) {
                    Text("Memory Preview")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    ForEach(chatHistory.recentMemoryHighlights) { memory in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.vtBurgundy.opacity(0.7))
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                            Text(memory.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(spacing: 0) {
            Button { showTerms = true } label: {
                row(icon: "doc.text", iconColor: Color(.systemGray), label: "Terms of Service") {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            divider
            Button { showPrivacy = true } label: {
                row(icon: "hand.raised.fill", iconColor: Color(.systemGray), label: "Privacy Policy") {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            divider
            row(icon: "info.circle.fill", iconColor: .blue, label: "Version") {
                Text("1.0.0 (1)").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Danger

    private var dangerSection: some View {
        VStack(spacing: 0) {
            Button { showClearDataAlert = true } label: {
                row(icon: "trash.fill", iconColor: .red, label: "Clear Transcript Data") {
                    EmptyView()
                }
            }
            divider
            Button { showResetAlert = true } label: {
                row(icon: "arrow.counterclockwise", iconColor: .orange, label: "Reset Account & Restart") {
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Divider().padding(.leading, 58)
    }

    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption.bold()).foregroundStyle(.secondary)
                    .textCase(.uppercase).tracking(0.5).padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    @ViewBuilder
    private func row<Trailing: View>(icon: String, iconColor: Color, label: String,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(label).font(.body).foregroundStyle(.primary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    // MARK: - Legal Content

    private var termsBody: String {
"""
**Terms of Service**

*Last updated: May 2026*

**Acceptance**
By using Hokie Advisor, you agree to these terms. If you do not agree, please do not use the app.

**Purpose**
Hokie Advisor is a student academic planning tool designed to assist Virginia Tech students with course planning and advising. It is not a replacement for official advising from your department or the university.

**AI Recommendations**
Course recommendations and advisor responses are AI-generated. Always verify recommendations against your official degree audit and consult your academic advisor before making enrollment decisions.

**Your Data**
Your transcript and academic data are stored locally on your device. Nothing is transmitted to third parties.

**Disclaimer**
Hokie Advisor is an independent student project and is not officially affiliated with or endorsed by Virginia Tech University.

**Changes**
We may update these terms at any time. Continued use of the app constitutes acceptance of any changes.
"""
    }

    private var privacyBody: String {
"""
**Privacy Policy**

*Last updated: May 2026*

**What We Collect**
- Transcript data you upload (processed locally, not sent to external servers beyond the AI API call)
- Your name, major, and graduation year (stored locally on your device via iOS app storage)

**How We Use It**
Your data is used solely to generate personalized course plans and advisor responses within the app.

**Data Sharing**
We do not sell, share, or transmit your personal data to any third parties, except as necessary to generate AI responses (course code lists and your major are sent to the AI API — never your full name or personally identifiable information).

**Data Deletion**
You can delete all stored data at any time via Settings → Clear All Data.

**Security**
Data stored on your device is protected by iOS app sandboxing and your device passcode/Face ID.

**Contact**
Questions about this policy? Reach out through the Virginia Tech CS department.
"""
    }
}

// MARK: - Chat Memory Editor

struct ChatMemoryEditorView: View {
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var newMemory = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        TextField("Add something to remember...", text: $newMemory, axis: .vertical)
                            .lineLimit(1...3)
                        Button {
                            chatHistory.addMemory(newMemory)
                            newMemory = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.vtBurgundy)
                        }
                        .disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: {
                    Text("Examples: preferred name, tutoring style, recurring weak topics, course goals, or scheduling preferences.")
                }

                Section("Saved") {
                    if chatHistory.memories.isEmpty {
                        Text("No saved memories yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(chatHistory.memories) { memory in
                            EditableMemoryRow(memory: memory)
                                .environmentObject(chatHistory)
                        }
                        .onDelete { offsets in
                            chatHistory.deleteMemory(at: offsets)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Chat Memory")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.vtBurgundy)
                }
            }
        }
        .swipeDownToDismissKeyboard()
    }
}

struct EditableMemoryRow: View {
    @EnvironmentObject var chatHistory: ChatHistoryStore
    let memory: ChatMemory
    @State private var draft: String = ""

    var body: some View {
        TextField("Memory", text: $draft, axis: .vertical)
            .lineLimit(1...4)
            .font(.subheadline)
            .onAppear { draft = memory.content }
            .onSubmit {
                chatHistory.updateMemory(memory, content: draft)
            }
            .onChange(of: draft) { _, value in
                chatHistory.updateMemory(memory, content: value)
            }
    }
}

// MARK: - Legal Sheet

struct LegalSheet: View {
    let title: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content.markdown)
                    .font(.body).lineSpacing(5)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.vtBurgundy)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(ChatHistoryStore())
}
