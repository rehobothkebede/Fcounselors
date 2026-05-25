import Foundation
import Combine

@MainActor
final class ChatHistoryStore: ObservableObject {
    @Published private(set) var sessions: [ChatSession] = []
    @Published private(set) var memories: [ChatMemory] = []

    private let sessionsURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat_sessions.json")
    }()

    private let memoriesURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat_memories.json")
    }()

    init() { load() }

    var recentMemoryHighlights: [ChatMemory] {
        Array(memories.prefix(4))
    }

    var memoryContext: [String] {
        memories.map(\.content)
    }

    func upsert(_ session: ChatSession) {
        let saved = ChatSession(
            id: session.id,
            title: session.title,
            date: session.date,
            messages: session.messages.map {
                ChatMessage(id: $0.id, role: $0.role, content: $0.content, isStreaming: false)
            }
        )

        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = saved
        } else {
            sessions.insert(saved, at: 0)
        }
        sessions.sort { $0.date > $1.date }
        persistSessions()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where sessions.indices.contains(index) {
            sessions.remove(at: index)
        }
        persistSessions()
    }

    func delete(sessionID: UUID) {
        sessions.removeAll { $0.id == sessionID }
        persistSessions()
    }

    func deleteAllSessions() {
        sessions.removeAll()
        persistSessions()
    }

    func deleteAll() {
        sessions.removeAll()
        memories.removeAll()
        persistSessions()
        persistMemories()
    }

    func addMemory(_ content: String) {
        let cleaned = cleanMemory(content)
        guard !cleaned.isEmpty, !containsSimilarMemory(cleaned) else { return }
        memories.insert(ChatMemory(content: cleaned), at: 0)
        persistMemories()
    }

    func updateMemory(_ memory: ChatMemory, content: String) {
        let cleaned = cleanMemory(content)
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        if cleaned.isEmpty {
            memories.remove(at: index)
        } else {
            memories[index].content = cleaned
            memories[index].date = Date()
        }
        persistMemories()
    }

    func deleteMemory(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where memories.indices.contains(index) {
            memories.remove(at: index)
        }
        persistMemories()
    }

    func captureMemory(from userMessage: String) {
        for memory in inferredMemories(from: userMessage) {
            addMemory(memory)
        }
        if let recurring = recurringTopicMemory(from: userMessage) {
            addMemory(recurring)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: sessionsURL),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = decoded
        }
        if let data = try? Data(contentsOf: memoriesURL),
           let decoded = try? JSONDecoder().decode([ChatMemory].self, from: data) {
            memories = decoded
        }
    }

    private func persistSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: sessionsURL, options: [.atomic])
    }

    private func persistMemories() {
        guard let data = try? JSONEncoder().encode(memories) else { return }
        try? data.write(to: memoriesURL, options: [.atomic])
    }

    private func cleanMemory(_ content: String) -> String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsSimilarMemory(_ content: String) -> Bool {
        let normalized = content.lowercased()
        return memories.contains { $0.content.lowercased() == normalized }
    }

    private func inferredMemories(from text: String) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()
        var results: [String] = []

        let explicitPrefixes = [
            "remember that ",
            "remember i ",
            "please remember ",
            "for future reference, ",
            "keep in mind that ",
        ]
        for prefix in explicitPrefixes where lower.hasPrefix(prefix) {
            results.append(cleaned)
        }

        if lower.hasPrefix("call me ") || lower.contains(" my preferred name is ") {
            results.append(cleaned)
        }
        if lower.contains("i prefer ") || lower.contains("i like explanations") || lower.contains("i learn best") {
            results.append(cleaned)
        }
        if lower.contains("i struggle with ") || lower.contains("i'm struggling with ") || lower.contains("i am struggling with ") {
            results.append(cleaned)
        }

        return results
    }

    private func recurringTopicMemory(from text: String) -> String? {
        let topics = [
            "graph theory",
            "linear algebra",
            "calculus",
            "proofs",
            "induction",
            "recurrences",
            "algorithms",
            "dynamic programming",
            "discrete math",
            "probability",
        ]

        let allUserText = ([text] + sessions.flatMap { session in
            session.messages
                .filter { $0.role == "user" }
                .map(\.content)
        })
        .joined(separator: " ")
        .lowercased()

        for topic in topics {
            let count = allUserText.components(separatedBy: topic).count - 1
            if count >= 2 {
                return "User has repeatedly asked about \(topic); connect future explanations to that topic when relevant."
            }
        }

        return nil
    }
}
