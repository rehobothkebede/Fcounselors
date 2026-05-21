import SwiftUI
import Combine

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = ChatViewModel()
    @Namespace private var bottomID

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            messageList
            inputBar
        }
        .background(Color(.systemBackground))
        .onAppear {
            if vm.major.isEmpty && !appState.major.isEmpty { vm.major = appState.major }
            vm.transcriptCourses = appState.transcriptCourses
            vm.inProgressSummary = appState.inProgressSummary
        }
        .onChange(of: appState.major) { _, major in
            if !major.isEmpty { vm.major = major }
        }
        .onChange(of: appState.transcriptCourses) { _, courses in
            vm.transcriptCourses = courses
            vm.inProgressSummary = appState.inProgressSummary
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Advisor")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Courses, prereqs, and degree planning")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !vm.messages.isEmpty {
                Button { vm.clearConversation() } label: {
                    Image(systemName: "trash")
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
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.vtBurgundy.opacity(0.4))
            Text("Start a conversation")
                .font(.title3.bold()).fontDesign(.rounded).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                if appState.needsTutoringSupport {
                    SuggestionChip(
                        text: "I'm struggling with \(appState.strugglingCourses.first ?? "my classes"). What should I do?",
                        vm: vm
                    )
                }
                SuggestionChip(text: "What CS courses should I take next semester?", vm: vm)
                SuggestionChip(text: "What are the communications and writing elective options?", vm: vm)
                SuggestionChip(text: "Explain pointers and memory for CS 2505", vm: vm)
                SuggestionChip(text: "What are the prerequisites for CS 3114?", vm: vm)
                SuggestionChip(text: "Help me plan my CS degree sequence", vm: vm)
            }
        }
        .padding(.top, 40).padding(.horizontal, 16)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
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
        .padding(.horizontal, 16).padding(.vertical, 12)
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

#Preview { ChatView().environmentObject(AppState()) }
