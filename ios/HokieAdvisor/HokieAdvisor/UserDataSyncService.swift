import Foundation

actor SupabaseUserDataService {
    static let shared = SupabaseUserDataService()

    private let maxSyncedSessions = 50
    private let maxSyncedMemories = 100

    func fetchStudentSnapshot(
        userID: UUID,
        accessToken: String
    ) async throws -> SupabaseStudentSnapshot {
        let profile = try await fetchProfile(userID: userID, accessToken: accessToken)
        let transcript = try await fetchLatestTranscript(userID: userID, accessToken: accessToken)
        let degreeAudit = try? await fetchLatestDegreeAudit(userID: userID, accessToken: accessToken)
        let darsAudit = try? await fetchLatestDarsAudit(userID: userID, accessToken: accessToken)
        return SupabaseStudentSnapshot(
            profile: profile,
            transcript: transcript,
            degreeAudit: degreeAudit,
            darsAudit: darsAudit
        )
    }

    func upsertProfile(
        _ profile: SupabaseProfileSnapshot,
        userID: UUID,
        accessToken: String
    ) async throws {
        let row = ProfileUpsertRow(
            id: userID,
            vtPID: profile.vtPID ?? "",
            vtEmail: profile.vtEmail ?? "",
            fullName: profile.fullName ?? "",
            major: profile.major ?? "Computer Science",
            graduationYear: profile.graduationYear ?? "",
            appearanceMode: profile.appearanceMode ?? "system"
        )
        try await send(
            path: "/rest/v1/profiles?on_conflict=id",
            method: "POST",
            accessToken: accessToken,
            body: [row],
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func fetchChatData(
        userID: UUID,
        accessToken: String
    ) async throws -> (sessions: [ChatSession], memories: [ChatMemory]) {
        let sessionRows: [RemoteChatSessionRow] = try await get(
            path: "/rest/v1/chat_sessions?select=id,title,created_at,updated_at&user_id=eq.\(userID.uuidString)&order=updated_at.desc&limit=\(maxSyncedSessions)",
            accessToken: accessToken
        )

        let messageRows = try await fetchMessages(
            sessionIDs: sessionRows.map(\.id),
            userID: userID,
            accessToken: accessToken
        )
        let messagesBySession = Dictionary(grouping: messageRows, by: \.sessionID)
        let sessions = sessionRows.map { row in
            let messages = (messagesBySession[row.id] ?? [])
                .sorted { $0.position < $1.position }
                .map { ChatMessage(id: $0.id, role: $0.role, content: $0.content, isStreaming: false) }
            return ChatSession(
                id: row.id,
                title: row.title,
                date: date(from: row.updatedAt) ?? date(from: row.createdAt) ?? Date(),
                messages: messages
            )
        }

        let memoryRows: [RemoteChatMemoryRow] = try await get(
            path: "/rest/v1/chat_memories?select=id,content,created_at,updated_at&user_id=eq.\(userID.uuidString)&order=updated_at.desc&limit=\(maxSyncedMemories)",
            accessToken: accessToken
        )
        let memories = memoryRows.map {
            ChatMemory(
                id: $0.id,
                content: $0.content,
                date: date(from: $0.updatedAt) ?? date(from: $0.createdAt) ?? Date()
            )
        }

        return (sessions, memories)
    }

    func upsertChatSession(
        _ session: ChatSession,
        userID: UUID,
        accessToken: String
    ) async throws {
        let sessionRow = ChatSessionUpsertRow(
            id: session.id,
            userID: userID,
            title: session.title,
            createdAt: isoString(from: session.date),
            updatedAt: isoString(from: session.date)
        )
        try await send(
            path: "/rest/v1/chat_sessions?on_conflict=id",
            method: "POST",
            accessToken: accessToken,
            body: [sessionRow],
            prefer: "resolution=merge-duplicates,return=minimal"
        )

        let messageRows = session.messages.enumerated().map { index, message in
            ChatMessageUpsertRow(
                id: message.id,
                sessionID: session.id,
                userID: userID,
                role: sanitizedRole(message.role),
                content: message.content,
                position: index,
                metadata: [:]
            )
        }
        guard !messageRows.isEmpty else { return }
        try await send(
            path: "/rest/v1/chat_messages?on_conflict=id",
            method: "POST",
            accessToken: accessToken,
            body: messageRows,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func deleteChatSession(
        id: UUID,
        accessToken: String
    ) async throws {
        try await sendWithoutBody(
            path: "/rest/v1/chat_sessions?id=eq.\(id.uuidString)",
            method: "DELETE",
            accessToken: accessToken
        )
    }

    func upsertMemory(
        _ memory: ChatMemory,
        userID: UUID,
        accessToken: String
    ) async throws {
        let row = ChatMemoryUpsertRow(
            id: memory.id,
            userID: userID,
            content: memory.content,
            createdAt: isoString(from: memory.date),
            updatedAt: isoString(from: memory.date)
        )
        try await send(
            path: "/rest/v1/chat_memories?on_conflict=id",
            method: "POST",
            accessToken: accessToken,
            body: [row],
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func deleteMemory(
        id: UUID,
        accessToken: String
    ) async throws {
        try await sendWithoutBody(
            path: "/rest/v1/chat_memories?id=eq.\(id.uuidString)",
            method: "DELETE",
            accessToken: accessToken
        )
    }

    // MARK: - Private

    private func fetchProfile(
        userID: UUID,
        accessToken: String
    ) async throws -> SupabaseProfileSnapshot? {
        let rows: [RemoteProfileRow] = try await get(
            path: "/rest/v1/profiles?select=id,vt_pid,vt_email,full_name,major,graduation_year,appearance_mode&id=eq.\(userID.uuidString)&limit=1",
            accessToken: accessToken
        )
        guard let row = rows.first else { return nil }
        return SupabaseProfileSnapshot(
            fullName: row.fullName,
            vtPID: row.vtPID,
            vtEmail: row.vtEmail,
            major: row.major,
            graduationYear: row.graduationYear,
            appearanceMode: row.appearanceMode
        )
    }

    private func fetchLatestTranscript(
        userID: UUID,
        accessToken: String
    ) async throws -> SupabaseTranscriptSnapshot? {
        let transcripts: [RemoteTranscriptRow] = try await get(
            path: "/rest/v1/transcripts?select=id,transcript_notes,created_at&user_id=eq.\(userID.uuidString)&order=created_at.desc&limit=1",
            accessToken: accessToken
        )
        guard let transcript = transcripts.first else { return nil }

        let rows: [RemoteTranscriptCourseRow] = try await get(
            path: "/rest/v1/transcript_courses?select=code,name,credits,grade,semester,status&user_id=eq.\(userID.uuidString)&transcript_id=eq.\(transcript.id.uuidString)&order=created_at.asc",
            accessToken: accessToken
        )

        let completed = rows
            .filter { $0.status == "completed" }
            .map { TranscriptCourse(code: $0.code, name: $0.name, credits: $0.credits, grade: $0.grade, semester: $0.semester) }
        let inProgress = rows
            .filter { $0.status == "in_progress" }
            .map { InProgressCourse(code: $0.code, name: $0.name, credits: $0.credits, semester: $0.semester) }
        let planned = rows
            .filter { $0.status == "planned" }
            .map { InProgressCourse(code: $0.code, name: $0.name, credits: $0.credits, semester: $0.semester) }

        return SupabaseTranscriptSnapshot(
            courses: completed,
            inProgressCourses: inProgress,
            plannedCourses: planned,
            notes: transcript.transcriptNotes
        )
    }

    private func fetchLatestDegreeAudit(
        userID: UUID,
        accessToken: String
    ) async throws -> DegreeAuditResponse? {
        let rows: [RemoteDegreeAuditRow] = try await get(
            path: "/rest/v1/degree_audits?select=response&user_id=eq.\(userID.uuidString)&order=created_at.desc&limit=1",
            accessToken: accessToken
        )
        return rows.first?.response
    }

    private func fetchLatestDarsAudit(
        userID: UUID,
        accessToken: String
    ) async throws -> DarsAuditResponse? {
        let rows: [RemoteDarsAuditRow] = try await get(
            path: "/rest/v1/dars_audits?select=response&user_id=eq.\(userID.uuidString)&order=created_at.desc&limit=1",
            accessToken: accessToken
        )
        return rows.first?.response
    }

    private func fetchMessages(
        sessionIDs: [UUID],
        userID: UUID,
        accessToken: String
    ) async throws -> [RemoteChatMessageRow] {
        guard !sessionIDs.isEmpty else { return [] }
        let ids = sessionIDs.map(\.uuidString).joined(separator: ",")
        return try await get(
            path: "/rest/v1/chat_messages?select=id,session_id,role,content,position,created_at&user_id=eq.\(userID.uuidString)&session_id=in.(\(ids))&order=position.asc&limit=1200",
            accessToken: accessToken
        )
    }

    private func get<Response: Decodable>(
        path: String,
        accessToken: String
    ) async throws -> Response {
        var request = try request(path: path, method: "GET", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func send<Body: Encodable>(
        path: String,
        method: String,
        accessToken: String,
        body: Body,
        prefer: String? = nil
    ) async throws {
        var request = try request(path: path, method: method, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
    }

    private func sendWithoutBody(
        path: String,
        method: String,
        accessToken: String
    ) async throws {
        let request = try request(path: path, method: method, accessToken: accessToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response)
    }

    private func request(
        path: String,
        method: String,
        accessToken: String
    ) throws -> URLRequest {
        guard let url = URL(string: "\(SupabaseConfig.url)\(path)") else {
            throw SupabaseAuthError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if let errorBody = try? JSONDecoder().decode(SupabaseErrorBody.self, from: data) {
                throw SupabaseAuthError.server(errorBody.message ?? errorBody.errorDescription ?? errorBody.msg ?? "Supabase returned \(http.statusCode).")
            }
            throw SupabaseAuthError.server(String(data: data, encoding: .utf8) ?? "Supabase returned \(http.statusCode).")
        }
    }

    private func sanitizedRole(_ role: String) -> String {
        switch role {
        case "system", "user", "assistant", "tool":
            return role
        default:
            return "user"
        }
    }

    private func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

nonisolated struct SupabaseStudentSnapshot {
    let profile: SupabaseProfileSnapshot?
    let transcript: SupabaseTranscriptSnapshot?
    let degreeAudit: DegreeAuditResponse?
    let darsAudit: DarsAuditResponse?
}

nonisolated struct SupabaseProfileSnapshot {
    let fullName: String?
    let vtPID: String?
    let vtEmail: String?
    let major: String?
    let graduationYear: String?
    let appearanceMode: String?
}

nonisolated struct SupabaseTranscriptSnapshot {
    let courses: [TranscriptCourse]
    let inProgressCourses: [InProgressCourse]
    let plannedCourses: [InProgressCourse]
    let notes: [String]
}

private struct RemoteProfileRow: Decodable {
    let fullName: String?
    let vtPID: String?
    let vtEmail: String?
    let major: String?
    let graduationYear: String?
    let appearanceMode: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case vtPID = "vt_pid"
        case vtEmail = "vt_email"
        case major
        case graduationYear = "graduation_year"
        case appearanceMode = "appearance_mode"
    }
}

private struct ProfileUpsertRow: Encodable {
    let id: UUID
    let vtPID: String
    let vtEmail: String
    let fullName: String
    let major: String
    let graduationYear: String
    let appearanceMode: String

    enum CodingKeys: String, CodingKey {
        case id, major
        case vtPID = "vt_pid"
        case vtEmail = "vt_email"
        case fullName = "full_name"
        case graduationYear = "graduation_year"
        case appearanceMode = "appearance_mode"
    }
}

private struct RemoteTranscriptRow: Decodable {
    let id: UUID
    let transcriptNotes: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case transcriptNotes = "transcript_notes"
    }
}

private struct RemoteTranscriptCourseRow: Decodable {
    let code: String
    let name: String
    let credits: Double?
    let grade: String?
    let semester: String?
    let status: String
}

private struct RemoteDegreeAuditRow: Decodable {
    let response: DegreeAuditResponse
}

private struct RemoteDarsAuditRow: Decodable {
    let response: DarsAuditResponse
}

private struct RemoteChatSessionRow: Decodable {
    let id: UUID
    let title: String
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct RemoteChatMessageRow: Decodable {
    let id: UUID
    let sessionID: UUID
    let role: String
    let content: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id, role, content, position
        case sessionID = "session_id"
    }
}

private struct RemoteChatMemoryRow: Decodable {
    let id: UUID
    let content: String
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct ChatSessionUpsertRow: Encodable {
    let id: UUID
    let userID: UUID
    let title: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case userID = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct ChatMessageUpsertRow: Encodable {
    let id: UUID
    let sessionID: UUID
    let userID: UUID
    let role: String
    let content: String
    let position: Int
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, role, content, position, metadata
        case sessionID = "session_id"
        case userID = "user_id"
    }
}

private struct ChatMemoryUpsertRow: Encodable {
    let id: UUID
    let userID: UUID
    let content: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, content
        case userID = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
