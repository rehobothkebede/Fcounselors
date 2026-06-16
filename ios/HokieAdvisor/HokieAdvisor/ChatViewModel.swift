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
    var transcriptNotes: [String] = []

    private(set) var currentSessionID: UUID = UUID()
    private weak var historyStore: ChatHistoryStore?
    private var activeRequestID: UUID?

    var isReadyForMessage: Bool {
        !isLoading
            && !messages.contains(where: { $0.isStreaming })
    }

    var canSend: Bool {
        canSend(text: inputText)
    }

    func canSend(text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isReadyForMessage
    }

    func configure(store: ChatHistoryStore) {
        historyStore = store
    }

    @discardableResult
    func sendMessage(textOverride: String? = nil) async -> Bool {
        let sourceText = textOverride ?? inputText
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend(text: text) else { return false }

        inputText = ""
        errorMessage = nil
        messages.append(ChatMessage(role: "user", content: text))
        historyStore?.captureMemory(from: text)
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
            inProgressCourses: inProgressSummary,
            transcriptNotes: transcriptNotes,
            chatMemories: historyStore?.memoryContext ?? []
        )

        let streamID = UUID()
        activeRequestID = streamID
        var streamStarted = false

        do {
            for try await token in APIService.streamChat(request: chatRequest) {
                guard activeRequestID == streamID else { return false }
                if !streamStarted {
                    streamStarted = true
                    isLoading = false
                    messages.append(ChatMessage(id: streamID, role: "assistant", content: "", isStreaming: true))
                }
                if let idx = messages.firstIndex(where: { $0.id == streamID }) {
                    messages[idx].content += token
                }
            }
            guard activeRequestID == streamID else { return false }
            if let idx = messages.firstIndex(where: { $0.id == streamID }) {
                messages[idx].isStreaming = false
            }
            activeRequestID = nil
            autoSave()
            isLoading = false
            return true
        } catch {
            guard activeRequestID == streamID else { return false }
            activeRequestID = nil
            isLoading = false
            messages.removeAll { $0.id == streamID }
            if messages.last?.role == "user" { messages.removeLast() }
            errorMessage = error.localizedDescription
            inputText = text
            return false
        }
    }

    func loadSession(_ session: ChatSession) {
        autoSave()
        activeRequestID = nil
        isLoading = false
        currentSessionID = session.id
        messages = session.messages.map {
            ChatMessage(id: $0.id, role: $0.role, content: $0.content, isStreaming: false)
        }
        errorMessage = nil
    }

    func autoSave() {
        guard !messages.isEmpty, let store = historyStore else { return }
        let title = messages.first(where: { $0.role == "user" })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(60)
            .description ?? "Chat"
        let saved = messages.map {
            ChatMessage(id: $0.id, role: $0.role, content: $0.content, isStreaming: false)
        }
        store.upsert(ChatSession(id: currentSessionID, title: title, date: Date(), messages: saved))
    }

    func clearConversation() {
        autoSave()
        resetConversation()
    }

    func discardCurrentConversation() {
        resetConversation()
    }

    private func resetConversation() {
        activeRequestID = nil
        isLoading = false
        messages = []
        inputText = ""
        errorMessage = nil
        currentSessionID = UUID()
    }
}
