import Foundation
import Combine

@MainActor
final class ChatHistoryStore: ObservableObject {
    @Published private(set) var sessions: [ChatSession] = []
    @Published private(set) var memories: [ChatMemory] = []

    private let documentsURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()
    private var currentUserID: UUID?
    private var currentAccessToken: String?
    private var lastSessionValidationDate: Date?
    private let sessionValidationInterval: TimeInterval = 300

    private var cacheKey: String {
        currentUserID?.uuidString ?? "local"
    }

    private var sessionsURL: URL {
        documentsURL.appendingPathComponent("chat_sessions_\(cacheKey).json")
    }

    private var memoriesURL: URL {
        documentsURL.appendingPathComponent("chat_memories_\(cacheKey).json")
    }

    init() { loadLocalCache() }

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
        syncSession(saved)
    }

    func delete(at offsets: IndexSet) {
        let removed = offsets
            .sorted(by: >)
            .compactMap { sessions.indices.contains($0) ? sessions[$0].id : nil }
        for index in offsets.sorted(by: >) where sessions.indices.contains(index) {
            sessions.remove(at: index)
        }
        persistSessions()
        removed.forEach(syncDeleteSession)
    }

    func delete(sessionID: UUID) {
        sessions.removeAll { $0.id == sessionID }
        persistSessions()
        syncDeleteSession(sessionID)
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
        let memory = ChatMemory(content: cleaned)
        memories.insert(memory, at: 0)
        persistMemories()
        syncMemory(memory)
    }

    func updateMemory(_ memory: ChatMemory, content: String) {
        let cleaned = cleanMemory(content)
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        if cleaned.isEmpty {
            let removed = memories[index]
            memories.remove(at: index)
            syncDeleteMemory(removed.id)
        } else {
            memories[index].content = cleaned
            memories[index].date = Date()
            syncMemory(memories[index])
        }
        persistMemories()
    }

    func deleteMemory(at offsets: IndexSet) {
        let removed = offsets
            .sorted(by: >)
            .compactMap { memories.indices.contains($0) ? memories[$0].id : nil }
        for index in offsets.sorted(by: >) where memories.indices.contains(index) {
            memories.remove(at: index)
        }
        persistMemories()
        removed.forEach(syncDeleteMemory)
    }

    func deleteMemory(_ memory: ChatMemory) {
        memories.removeAll { $0.id == memory.id }
        persistMemories()
        syncDeleteMemory(memory.id)
    }

    func captureMemory(from userMessage: String) {
        for memory in inferredMemories(from: userMessage) {
            addMemory(memory)
        }
        if let recurring = recurringTopicMemory(from: userMessage) {
            addMemory(recurring)
        }
    }

    func configureForAuthenticatedUser() async {
        guard let session = try? await SupabaseAuthService.shared.validatedCurrentSession(),
              let userID = session.user?.id else {
            clearLoadedUser()
            return
        }

        await configure(userID: userID, accessToken: session.accessToken)
    }

    func configure(userID: UUID, accessToken: String) async {
        currentAccessToken = accessToken
        lastSessionValidationDate = Date()

        if currentUserID != userID {
            currentUserID = userID
            loadLocalCache()
        }

        do {
            let remote = try await SupabaseUserDataService.shared.fetchChatData(
                userID: userID,
                accessToken: accessToken
            )
            mergeRemoteData(remote.sessions, remote.memories)
            persistSessions()
            persistMemories()
            syncAllLocalData()
        } catch {
            // Keep the user-scoped local cache available when the network is slow or offline.
        }
    }

    func clearLoadedUser() {
        currentUserID = nil
        currentAccessToken = nil
        lastSessionValidationDate = nil
        sessions = []
        memories = []
    }

    private func loadLocalCache() {
        sessions = []
        memories = []
        if let data = try? Data(contentsOf: sessionsURL),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = decoded
        }
        if let data = try? Data(contentsOf: memoriesURL),
           let decoded = try? JSONDecoder().decode([ChatMemory].self, from: data) {
            memories = decoded
        }
    }

    private func mergeRemoteData(_ remoteSessions: [ChatSession], _ remoteMemories: [ChatMemory]) {
        var sessionsByID = Dictionary(uniqueKeysWithValues: remoteSessions.map { ($0.id, $0) })
        for local in sessions {
            if let remote = sessionsByID[local.id] {
                if local.date > remote.date {
                    sessionsByID[local.id] = local
                }
            } else {
                sessionsByID[local.id] = local
            }
        }
        sessions = sessionsByID.values
            .sorted { $0.date > $1.date }
            .prefix(100)
            .map { $0 }

        var memoriesByID = Dictionary(uniqueKeysWithValues: remoteMemories.map { ($0.id, $0) })
        for local in memories {
            if let remote = memoriesByID[local.id] {
                if local.date > remote.date {
                    memoriesByID[local.id] = local
                }
            } else {
                memoriesByID[local.id] = local
            }
        }
        memories = memoriesByID.values
            .sorted { $0.date > $1.date }
            .prefix(100)
            .map { $0 }
    }

    private func persistSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: sessionsURL, options: [.atomic])
    }

    private func persistMemories() {
        guard let data = try? JSONEncoder().encode(memories) else { return }
        try? data.write(to: memoriesURL, options: [.atomic])
    }

    private func syncAllLocalData() {
        sessions.forEach(syncSession)
        memories.forEach(syncMemory)
    }

    private func syncSession(_ session: ChatSession) {
        guard currentUserID != nil else { return }
        Task { [weak self] in
            await self?.persistSessionRemotely(session)
        }
    }

    private func syncMemory(_ memory: ChatMemory) {
        guard currentUserID != nil else { return }
        Task { [weak self] in
            await self?.persistMemoryRemotely(memory)
        }
    }

    private func syncDeleteSession(_ sessionID: UUID) {
        guard currentUserID != nil else { return }
        Task { [weak self] in
            await self?.deleteSessionRemotely(sessionID)
        }
    }

    private func syncDeleteMemory(_ memoryID: UUID) {
        guard currentUserID != nil else { return }
        Task { [weak self] in
            await self?.deleteMemoryRemotely(memoryID)
        }
    }

    private func authenticatedSyncContext() async -> (userID: UUID, accessToken: String)? {
        guard let configuredUserID = currentUserID else {
            return nil
        }

        if let token = currentAccessToken,
           let validatedAt = lastSessionValidationDate,
           Date().timeIntervalSince(validatedAt) < sessionValidationInterval {
            return (configuredUserID, token)
        }

        guard let session = try? await SupabaseAuthService.shared.validatedCurrentSession(),
              session.user?.id == configuredUserID else {
            currentAccessToken = nil
            lastSessionValidationDate = nil
            return nil
        }

        currentAccessToken = session.accessToken
        lastSessionValidationDate = Date()
        return (configuredUserID, session.accessToken)
    }

    private func persistSessionRemotely(_ session: ChatSession) async {
        guard let context = await authenticatedSyncContext() else { return }
        try? await SupabaseUserDataService.shared.upsertChatSession(
            session,
            userID: context.userID,
            accessToken: context.accessToken
        )
    }

    private func persistMemoryRemotely(_ memory: ChatMemory) async {
        guard let context = await authenticatedSyncContext() else { return }
        try? await SupabaseUserDataService.shared.upsertMemory(
            memory,
            userID: context.userID,
            accessToken: context.accessToken
        )
    }

    private func deleteSessionRemotely(_ sessionID: UUID) async {
        guard let context = await authenticatedSyncContext() else { return }
        try? await SupabaseUserDataService.shared.deleteChatSession(
            id: sessionID,
            accessToken: context.accessToken
        )
    }

    private func deleteMemoryRemotely(_ memoryID: UUID) async {
        guard let context = await authenticatedSyncContext() else { return }
        try? await SupabaseUserDataService.shared.deleteMemory(
            id: memoryID,
            accessToken: context.accessToken
        )
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
