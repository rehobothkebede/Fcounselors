import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var major: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Synced from AppState by ChatView on appear / onChange
    var transcriptCourses: [TranscriptCourse] = []
    var inProgressSummary: [String] = []

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty
            && !isLoading
            && !messages.contains(where: { $0.isStreaming })
    }

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        inputText = ""
        errorMessage = nil
        messages.append(ChatMessage(role: "user", content: text))
        isLoading = true

        let payload = messages.map { ChatPayload(role: $0.role, content: $0.content) }
        let transcriptEntries = transcriptCourses.map {
            TranscriptEntry(code: $0.code, name: $0.name, grade: $0.grade,
                            semester: $0.semester, credits: $0.credits)
        }
        let chatRequest = ChatRequest(
            messages: payload,
            major: major,
            transcript: transcriptEntries,
            inProgressCourses: inProgressSummary
        )

        let streamID = UUID()
        var streamStarted = false

        do {
            for try await token in APIService.streamChat(request: chatRequest) {
                if !streamStarted {
                    streamStarted = true
                    isLoading = false
                    messages.append(ChatMessage(id: streamID, role: "assistant", content: "", isStreaming: true))
                }
                if let idx = messages.firstIndex(where: { $0.id == streamID }) {
                    messages[idx].content += token
                }
            }
            if let idx = messages.firstIndex(where: { $0.id == streamID }) {
                messages[idx].isStreaming = false
            }
        } catch {
            isLoading = false
            messages.removeAll { $0.id == streamID }
            if messages.last?.role == "user" { messages.removeLast() }
            errorMessage = error.localizedDescription
            inputText = text
        }

        isLoading = false
    }

    func clearConversation() {
        messages = []
        errorMessage = nil
    }
}
