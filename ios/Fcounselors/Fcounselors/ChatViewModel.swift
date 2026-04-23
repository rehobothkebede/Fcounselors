import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var major: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        inputText = ""
        errorMessage = nil
        messages.append(ChatMessage(role: "user", content: text))
        isLoading = true

        let payload = messages.map { ChatPayload(role: $0.role, content: $0.content) }
        let request = ChatRequest(messages: payload, major: major)

        do {
            let response = try await APIService.sendChat(request: request)
            messages.append(ChatMessage(role: "assistant", content: response.reply))
        } catch {
            errorMessage = error.localizedDescription
            // Remove the user message so they can retry
            messages.removeLast()
            inputText = text
        }

        isLoading = false
    }

    func clearConversation() {
        messages = []
        errorMessage = nil
    }
}
