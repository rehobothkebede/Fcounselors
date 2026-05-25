import SwiftUI
import UIKit
import Combine

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @StateObject private var vm = ChatViewModel()
    @Namespace private var bottomID
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            messageList
            inputBar
        }
        .background(Color(.systemBackground))
        .swipeDownToDismissKeyboard()
        .onAppear {
            vm.configure(store: chatHistory)
            if vm.major.isEmpty && !appState.major.isEmpty { vm.major = appState.major }
            vm.transcriptCourses = appState.transcriptCourses
            vm.inProgressSummary = appState.inProgressSummary
            vm.transcriptNotes = appState.transcriptNotes
        }
        .onDisappear { vm.autoSave() }
        .onChange(of: appState.major) { _, major in
            if !major.isEmpty { vm.major = major }
        }
        .onChange(of: appState.transcriptCourses) { _, courses in
            vm.transcriptCourses = courses
            vm.inProgressSummary = appState.inProgressSummary
            vm.transcriptNotes = appState.transcriptNotes
        }
        .onChange(of: appState.transcriptNotes) { _, notes in
            vm.transcriptNotes = notes
        }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet(vm: vm)
                .environmentObject(chatHistory)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.vtBurgundy)
                    .frame(width: 40, height: 40)
                    .background(Color.vtBurgundy.opacity(0.1))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AI Advisor")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Visual math, CS, and degree planning")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !vm.messages.isEmpty {
                Button { vm.clearConversation() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.vtBurgundy)
                        .frame(width: 40, height: 40)
                        .background(Color.vtBurgundy.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.messages) { MessageBubble(message: $0) }
                        if vm.isLoading { TypingIndicator() }
                        if let error = vm.errorMessage { ErrorBanner(message: error) }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: vm.isLoading) { _, _ in
                withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: vm.messages.last?.content) { _, _ in
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 18) {
            MiniGraphPreview()
                .frame(height: 150)

            VStack(spacing: 6) {
                Text("Math + CS tutor")
                    .font(.title3.bold()).fontDesign(.rounded)
                Text("Graph theory, algorithms, proofs, linear algebra, calculus, and VT planning.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                TopicChip(icon: "point.3.connected.trianglepath.dotted", label: "Graph theory")
                TopicChip(icon: "function", label: "Calculus")
                TopicChip(icon: "square.grid.3x3.fill", label: "Linear algebra")
                TopicChip(icon: "chevron.left.forwardslash.chevron.right", label: "Algorithms")
            }

            VStack(spacing: 8) {
                if appState.needsTutoringSupport {
                    SuggestionChip(
                        text: "I'm struggling with \(appState.strugglingCourses.first ?? "my classes"). What should I do?",
                        vm: vm
                    )
                }
                ForEach(suggestionChips, id: \.self) { text in
                    SuggestionChip(text: text, vm: vm)
                }
            }
        }
        .padding(.top, 40).padding(.horizontal, 16)
    }

    private var suggestionChips: [String] {
        let major = vm.major.isEmpty ? (appState.major.isEmpty ? "my major" : appState.major) : vm.major
        return [
            "Show me BFS on a graph with a visual",
            "Explain paths vs circuits in graph theory",
            "Walk me through an eigenvalue example",
            "Help me prove a recurrence by induction",
            "What \(major) courses should I take next semester?",
        ]
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 4) {
            KeyboardDismissHandle()

            HStack(spacing: 10) {
                TextField("Ask a question...", text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.subheadline)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .onSubmit {
                        if vm.canSend { Task { await vm.sendMessage() } }
                    }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await vm.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.bold()).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(vm.canSend ? Color.vtBurgundy : Color(.tertiarySystemBackground))
                        .clipShape(Circle())
                }
                .disabled(!vm.canSend)
                .animation(.easeInOut(duration: 0.15), value: vm.canSend)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .background(Color(.systemBackground))
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            Text(message.content)
                .font(.subheadline).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.vtBurgundy)
                .clipShape(RoundedRectangle(cornerRadius: 22))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                MarkdownBody(text: message.content.isEmpty ? " " : message.content, baseColor: .primary)
                if message.isStreaming {
                    StreamingCursor()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }
            if !isUser {
                Image(systemName: "brain.head.profile")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.vtBurgundy).clipShape(Circle())
                    .alignmentGuide(.bottom) { d in d[.bottom] }
            }
            bubbleContent
            // No right spacer for assistant — let code-heavy replies use full available width
        }
    }
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    @State private var visible = true
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .frame(width: 2, height: 14)
            .foregroundStyle(Color.vtBurgundy)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: visible)
            .onReceive(timer) { _ in visible.toggle() }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase = 0
    let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.vtBurgundy).clipShape(Circle())

            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle().frame(width: 7, height: 7)
                        .foregroundStyle(Color.secondary.opacity(phase == i ? 1 : 0.3))
                        .animation(.easeInOut(duration: 0.3), value: phase)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22))

            Spacer(minLength: 48)
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    let text: String
    let vm: ChatViewModel

    var body: some View {
        Button {
            vm.inputText = text
            Task { await vm.sendMessage() }
        } label: {
            Text(text).font(.subheadline).foregroundStyle(Color.vtBurgundy)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.vtBurgundy.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct TopicChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(Color.vtBurgundy)
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MiniGraphPreview: View {
    private let nodes: [(String, CGPoint)] = [
        ("A", CGPoint(x: 0.18, y: 0.24)),
        ("B", CGPoint(x: 0.50, y: 0.18)),
        ("C", CGPoint(x: 0.30, y: 0.72)),
        ("D", CGPoint(x: 0.72, y: 0.66)),
        ("E", CGPoint(x: 0.84, y: 0.30)),
    ]

    private let edges = [(0, 1), (0, 2), (1, 3), (1, 4), (2, 3), (3, 4)]
    private let path = Set([0, 1, 3])
    private let pathEdges = Set(["0-1", "1-3"])

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemBackground))

                ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
                    let a = scaled(nodes[edge.0].1, in: proxy.size)
                    let b = scaled(nodes[edge.1].1, in: proxy.size)
                    let key = "\(edge.0)-\(edge.1)"
                    Path { path in
                        path.move(to: a)
                        path.addLine(to: b)
                    }
                    .stroke(
                        pathEdges.contains(key) ? Color.vtBurgundy : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: pathEdges.contains(key) ? 4 : 1.5, lineCap: .round)
                    )
                }

                ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                    let highlighted = path.contains(index)
                    Text(node.0)
                        .font(.caption.bold())
                        .foregroundStyle(highlighted ? .white : .primary)
                        .frame(width: 36, height: 36)
                        .background(highlighted ? Color.vtBurgundy : Color(.tertiarySystemBackground))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                        .position(scaled(node.1, in: proxy.size))
                }

                VStack {
                    Spacer()
                    HStack {
                        Label("shortest path A → D", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color.vtBurgundy)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.vtBurgundy.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer()
                    }
                    .padding(12)
                }
            }
        }
    }

    private func scaled(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

// MARK: - Chat History Sheet

struct ChatHistorySheet: View {
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if chatHistory.sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 46))
                            .foregroundStyle(Color.vtBurgundy.opacity(0.4))
                        Text("No saved chats yet")
                            .font(.title3.bold()).fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                        Text("Your conversations are automatically saved as you chat.")
                            .font(.subheadline).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(chatHistory.sessions) { session in
                            let userMessageCount = session.messages.filter { $0.role == "user" }.count
                            Button {
                                vm.loadSession(session)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        HStack(spacing: 8) {
                                            Text(Self.dateFormatter.string(from: session.date))
                                                .font(.caption).foregroundStyle(.secondary)
                                            Text("·")
                                                .font(.caption).foregroundStyle(.tertiary)
                                            Text("\(userMessageCount) \(userMessageCount == 1 ? "message" : "messages")")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if session.id == vm.currentSessionID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.vtBurgundy)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { offsets in
                            if offsets.contains(where: { index in
                                chatHistory.sessions.indices.contains(index) &&
                                    chatHistory.sessions[index].id == vm.currentSessionID
                            }) {
                                vm.discardCurrentConversation()
                            }
                            chatHistory.delete(at: offsets)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.vtBurgundy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.clearConversation()
                        dismiss()
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    .foregroundStyle(Color.vtBurgundy)
                }
            }
        }
    }
}

#Preview { ChatView().environmentObject(AppState()).environmentObject(ChatHistoryStore()) }
