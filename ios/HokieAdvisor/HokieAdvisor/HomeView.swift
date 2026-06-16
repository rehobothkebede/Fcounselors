import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int
    @AppStorage("studentName") private var studentName = ""
    @AppStorage("graduationYear") private var graduationYear = ""
    @State private var scrollOffset: CGFloat = 0

    private var compactTitleProgress: CGFloat {
        min(max((scrollOffset - 82) / 34, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    homeHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    statsGrid.padding(.horizontal, 20)
                    quickActionsSection
                    if appState.hasTranscript { progressSection } else { transcriptNudge }
                    tipsSection
                    Spacer(minLength: HokieChrome.contentBottomInset)
                }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                guard abs(offset - scrollOffset) > 0.5 else { return }
                scrollOffset = offset
            }
            .hokieScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
            .overlay(alignment: .top) { compactTitleOverlay }
        }
    }

    private var compactTitleOverlay: some View {
        HokieCompactPill(
            title: "Home",
            symbol: "house.fill",
            accent: .vtOrange,
            progress: compactTitleProgress
        )
        .padding(.top, 8)
    }

    private var homeHeader: some View {
        HokiePageHeader(
            title: "Home",
            eyebrow: greeting,
            subtitle: "Your academic cockpit for credits, GPA, and next moves.",
            symbol: "sparkles",
            accent: .vtOrange,
            stat: homeStat
        )
    }

    private var greeting: String {
        let first = studentName.components(separatedBy: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return first.isEmpty ? "Ready for today" : "Ready, \(first)"
    }

    private var homeStat: HokieHeaderStat {
        if appState.hasTranscript {
            return HokieHeaderStat(
                value: "\(Int(appState.totalCredits))",
                label: "credits logged",
                icon: "books.vertical.fill"
            )
        }

        return HokieHeaderStat(
            value: "Setup",
            label: "import transcript",
            icon: "arrow.up.doc.fill"
        )
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
            circleIcon(icon, color: color, size: 40)
            Text(value).font(.title3.bold()).fontDesign(.rounded)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassSurface(cornerRadius: 22)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Quick Actions", icon: "bolt.fill", color: .vtOrange)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                quickActionRow(icon: "checklist.checked", title: "View Degree Audit",
                               subtitle: "See your CS requirements and remaining credits",
                               color: .vtBurgundy, tab: 1)
                quickActionRow(icon: "bubble.left.and.bubble.right.fill", title: "Ask Your Advisor",
                               subtitle: "Chat with your AI academic advisor",
                               color: .vtBurgundy, tab: 2)
            }
            .padding(.horizontal, 20)
        }
    }

    private func quickActionRow(icon: String, title: String, subtitle: String,
                                 color: Color, tab: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            switchToTab(tab)
        } label: {
            HStack(spacing: 14) {
                circleIcon(icon, color: color, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(15)
            .glassSurface(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transcript Nudge

    private var transcriptNudge: some View {
        Button { switchToTab(3) } label: {
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
            .padding(15)
            .glassSurface(cornerRadius: 24)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private func switchToTab(_ tab: Int) {
        setTabWithoutPageTraversal { selectedTab = tab }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Your Progress", icon: "chart.line.uptrend.xyaxis", color: .vtBurgundy)
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
                .padding(15)
                .glassSurface(cornerRadius: 24)

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
                    .padding(15)
                    .glassSurface(cornerRadius: 24)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Hokie Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Hokie Tips", icon: "lightbulb.fill", color: .vtOrange)
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
            circleIcon(icon, color: color, size: 44)
            Text(title).font(.subheadline.bold())
            Text(body).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 190)
        .padding(16)
        .glassSurface(cornerRadius: 22)
    }
}

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(AppState())
}
