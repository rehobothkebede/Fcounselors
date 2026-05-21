import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileCard.padding(.top, 8)
                    settingsGroup(title: "Appearance") { appearanceSection }
                    settingsGroup(title: "Academic") { academicSection }
                    settingsGroup(title: "Transcript") { transcriptSection }
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
            .background(Color(.systemBackground))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showTranscriptImport) {
            TranscriptView().environmentObject(appState)
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
                appState.inProgressGrades = [:]
                appState.hasTranscript = false
                appState.passingAllClasses = nil
                appState.strugglingCourses = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your transcript and all academic data will be removed from this device. This cannot be undone.")
        }
        .alert("Reset Account", isPresented: $showResetAlert) {
            Button("Reset & Restart", role: .destructive) {
                appState.transcriptCourses = []
                appState.inProgressCourses = []
                appState.inProgressGrades = [:]
                appState.hasTranscript = false
                appState.passingAllClasses = nil
                appState.strugglingCourses = []
                appState.major = ""
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
                } else {
                    Text(appState.major.isEmpty ? "Virginia Tech Student" : appState.major)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text("Virginia Tech")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.vtBurgundy).clipShape(Capsule())

                if !vtPID.isEmpty {
                    Text("PID: \(vtPID)")
                        .font(.caption.bold()).foregroundStyle(Color.vtBurgundy)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.vtBurgundy.opacity(0.1)).clipShape(Capsule())
                }
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
    SettingsView().environmentObject(AppState())
}
