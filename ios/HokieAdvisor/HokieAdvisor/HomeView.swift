import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    @AppStorage("studentName") private var studentName = ""
    @AppStorage("graduationYear") private var graduationYear = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                welcomeHeader.padding(.horizontal, 24).padding(.top, 16)
                statsGrid.padding(.horizontal, 20)
                quickActionsSection
                if appState.hasTranscript { progressSection } else { transcriptNudge }
                tipsSection
                Spacer(minLength: 110)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemBackground))
    }

    // MARK: - Welcome Header

    private var welcomeHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.vtBurgundy).frame(width: 54, height: 54)
                Text(initials)
                    .font(.headline.bold()).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(studentName.isEmpty ? "Welcome, Hokie!" : "\(greeting), \(firstName)!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(appState.major.isEmpty ? "Set your major in Profile" : appState.major)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var firstName: String {
        studentName.components(separatedBy: " ").first ?? studentName
    }

    private var initials: String {
        let parts = studentName.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.isEmpty { return "HK" }
        if parts.count == 1 { return String(parts[0].prefix(2)).uppercased() }
        return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        let gpa = appState.calculatedGPA
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(
                value: appState.hasTranscript ? "\(Int(appState.totalCredits))" : "—",
                label: "Credits",
                icon: "books.vertical.fill",
                color: appState.hasTranscript ? .vtBurgundy : Color(.systemGray3)
            )
            statCard(
                value: appState.hasTranscript ? (gpa.map { String(format: "%.2f", $0) } ?? "N/A") : "—",
                label: "GPA",
                icon: "chart.bar.fill",
                color: appState.hasTranscript ? (gpa.map { gpaColor($0) } ?? Color(.systemGray3)) : Color(.systemGray3)
            )
            statCard(
                value: appState.hasTranscript ? "\(appState.transcriptCourses.count)" : "—",
                label: "Courses",
                icon: "checkmark.circle.fill",
                color: appState.hasTranscript ? .green : Color(.systemGray3)
            )
            statCard(
                value: graduationYear.isEmpty ? "—" : graduationYear,
                label: "Grad Year",
                icon: "graduationcap.fill",
                color: graduationYear.isEmpty ? Color(.systemGray3) : .blue
            )
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3.bold()).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(color).clipShape(Circle())
            Text(value).font(.title2.bold()).fontDesign(.rounded)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline.bold()).fontDesign(.rounded)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                quickActionRow(icon: "checklist.checked", title: "View Degree Audit",
                               subtitle: "See your CS requirements and remaining credits",
                               color: .vtBurgundy, tab: 1)
                quickActionRow(icon: "bubble.left.and.bubble.right.fill", title: "Ask Your Advisor",
                               subtitle: "Chat with your AI academic advisor",
                               color: .blue, tab: 2)
            }
            .padding(.horizontal, 20)
        }
    }

    private func quickActionRow(icon: String, title: String, subtitle: String,
                                 color: Color, tab: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = tab }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.bold()).foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(color).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    // MARK: - Transcript Nudge

    private var transcriptNudge: some View {
        Button { selectedTab = 3 } label: {
            HStack(spacing: 14) {
                circleIcon("doc.text.fill", color: .vtBurgundy)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import your transcript").font(.subheadline.bold()).foregroundStyle(.primary)
                    Text("Unlock your credit count, courses, and degree audit")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Progress")
                .font(.headline.bold()).fontDesign(.rounded)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    circleIcon("doc.text.fill", color: .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcript Imported").font(.subheadline.bold()).foregroundStyle(.primary)
                        Text("\(appState.transcriptCourses.count) courses · \(Int(appState.totalCredits)) credits")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.title3)
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))

                if appState.needsTutoringSupport {
                    HStack(spacing: 14) {
                        circleIcon("lightbulb.fill", color: .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Academic Support Ready").font(.subheadline.bold()).foregroundStyle(.primary)
                            Text("Resources available for \(appState.strugglingCourses.count) course\(appState.strugglingCourses.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Hokie Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hokie Tips")
                .font(.headline.bold()).fontDesign(.rounded)
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    tipCard(icon: "calendar.badge.clock", color: .purple,
                            title: "Plan Ahead",
                            body: "Register before advising deadlines — popular sections fill up fast.")
                    tipCard(icon: "person.2.fill", color: .blue,
                            title: "Office Hours",
                            body: "Go early in the semester, not just before exams. Professors remember you.")
                    tipCard(icon: "checkmark.seal.fill", color: .green,
                            title: "Pathways",
                            body: "Knock out Pathways requirements early — they're easy to defer and painful to cram in senior year.")
                    tipCard(icon: "brain.head.profile", color: .vtBurgundy,
                            title: "Ask Anything",
                            body: "Your AI advisor knows the VT CS curriculum. No question is too small.")
                    tipCard(icon: "building.columns.fill", color: .orange,
                            title: "Use Resources",
                            body: "The VT Writing Center, Math Emporium, and CS tutoring are free and underused.")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    private func tipCard(icon: String, color: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title2.bold()).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(color).clipShape(Circle())
            Text(title).font(.subheadline.bold())
            Text(body).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 190)
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(AppState())
}
