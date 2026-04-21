import SwiftUI
import Combine

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @Namespace private var bottomID

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            inputBar
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Advisor")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("Ask anything about courses or your degree")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                if !vm.messages.isEmpty {
                    Button {
                        vm.clearConversation()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(8)
                            .background(.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                TextField("Major (optional — e.g. ME, CS, ECE)", text: $vm.major)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .tint(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.72, green: 0.1, blue: 0.1), Color.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vm.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.messages) { message in
                            MessageBubble(message: message)
                        }
                        if vm.isLoading {
                            TypingIndicator()
                        }
                        if let error = vm.errorMessage {
                            ErrorBanner(message: error)
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: vm.messages.count) { _ in
                withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: vm.isLoading) { _ in
                withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange.opacity(0.6))
            Text("Start a conversation")
                .font(.headline)
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                SuggestionChip(text: "What courses should I take next semester?", vm: vm)
                SuggestionChip(text: "Explain recursion to me", vm: vm)
                SuggestionChip(text: "What are the prerequisites for CS 3114?", vm: vm)
                SuggestionChip(text: "Help me plan my degree", vm: vm)
            }
        }
        .padding(.top, 40)
        .padding(.horizontal, 16)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask a question...", text: $vm.inputText, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                .onSubmit {
                    if vm.canSend {
                        Task { await vm.sendMessage() }
                    }
                }

            Button {
                Task { await vm.sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(vm.canSend ? Color.orange : Color.gray.opacity(0.35))
            }
            .disabled(!vm.canSend)
            .animation(.easeInOut(duration: 0.15), value: vm.canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 48) }

            if !isUser {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(colors: [Color(red: 0.72, green: 0.1, blue: 0.1), .orange],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(Circle())
            }

            Text(message.content)
                .font(.subheadline)
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.orange : Color(.systemBackground))
                .clipShape(BubbleShape(isUser: isUser))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)

            if !isUser { Spacer(minLength: 48) }
        }
    }
}

// MARK: - Bubble Shape

struct BubbleShape: Shape {
    let isUser: Bool
    let radius: CGFloat = 18
    let tail: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tr = isUser ? tail : radius
        let tl = isUser ? radius : tail
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase: Int = 0
    let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(colors: [Color(red: 0.72, green: 0.1, blue: 0.1), .orange],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(Circle())

            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .frame(width: 7, height: 7)
                        .foregroundStyle(Color.secondary.opacity(phase == i ? 1 : 0.3))
                        .animation(.easeInOut(duration: 0.3), value: phase)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)

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
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25)))
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
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25)))
        }
    }
}

// MARK: - Placeholder helper

extension View {
    func placeholder<Content: View>(when condition: Bool, @ViewBuilder content: () -> Content) -> some View {
        overlay(condition ? content() : nil)
    }
}

// MARK: - Preview

#Preview {
    ChatView()
}
