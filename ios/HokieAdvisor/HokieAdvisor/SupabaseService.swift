import Foundation
import Security

enum SupabaseConfig {
    // The anon key is safe to ship in the app when RLS policies are correct.
    // Never put the service-role key in iOS.
    static let url = ""
    static let anonKey = ""

    static var isConfigured: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !url.contains("YOUR_PROJECT_REF")
    }
}

enum SupabaseAuthError: LocalizedError {
    case notConfigured
    case invalidURL
    case missingSession
    case keychain(OSStatus)
    case server(String)
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured yet."
        case .invalidURL:
            return "Invalid Supabase URL."
        case .missingSession:
            return "Supabase did not return a session. Check whether email confirmation is required."
        case .keychain:
            return "Could not securely store the Supabase session."
        case .server(let message):
            return message
        case .network(let error):
            return error.localizedDescription
        case .decoding:
            return "Could not read Supabase response."
        }
    }
}

struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let tokenType: String
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
    }
}

struct SupabaseUser: Codable {
    let id: UUID
    let email: String?
}

struct SupabaseAuthResponse: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
    }

    var session: SupabaseSession? {
        guard let accessToken, let refreshToken else { return nil }
        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            tokenType: tokenType ?? "bearer",
            user: user
        )
    }
}

struct SupabaseProfilePayload: Encodable {
    let id: UUID
    let vtPID: String
    let vtEmail: String
    let fullName: String
    let major: String
    let graduationYear: String
    let appearanceMode: String

    enum CodingKeys: String, CodingKey {
        case id
        case vtPID = "vt_pid"
        case vtEmail = "vt_email"
        case fullName = "full_name"
        case major
        case graduationYear = "graduation_year"
        case appearanceMode = "appearance_mode"
    }
}

actor SupabaseAuthService {
    static let shared = SupabaseAuthService()

    private let sessionKey = "hokieadvisor.supabase.session"

    func signUp(
        email: String,
        password: String,
        fullName: String,
        vtPID: String,
        major: String,
        graduationYear: String,
        appearanceMode: String
    ) async throws -> SupabaseSession? {
        guard SupabaseConfig.isConfigured else { throw SupabaseAuthError.notConfigured }

        let payload: [String: Any] = [
            "email": email,
            "password": password,
            "data": [
                "full_name": fullName,
                "vt_email": email,
                "vt_pid": vtPID,
                "major": major,
                "graduation_year": graduationYear,
                "appearance_mode": appearanceMode,
            ],
        ]

        let response: SupabaseAuthResponse = try await request(
            path: "/auth/v1/signup",
            method: "POST",
            body: payload
        )

        if let session = response.session {
            try saveSession(session)
            try await upsertProfile(
                session: session,
                fullName: fullName,
                vtEmail: email,
                vtPID: vtPID,
                major: major,
                graduationYear: graduationYear,
                appearanceMode: appearanceMode
            )
            return session
        }

        return nil
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        guard SupabaseConfig.isConfigured else { throw SupabaseAuthError.notConfigured }
        let response: SupabaseAuthResponse = try await request(
            path: "/auth/v1/token?grant_type=password",
            method: "POST",
            body: ["email": email, "password": password]
        )
        guard let session = response.session else { throw SupabaseAuthError.missingSession }
        try saveSession(session)
        return session
    }

    func currentSession() throws -> SupabaseSession? {
        guard let data = KeychainStore.read(service: sessionKey) else { return nil }
        do {
            return try JSONDecoder().decode(SupabaseSession.self, from: data)
        } catch {
            throw SupabaseAuthError.decoding(error)
        }
    }

    func signOut() {
        KeychainStore.delete(service: sessionKey)
    }

    private func upsertProfile(
        session: SupabaseSession,
        fullName: String,
        vtEmail: String,
        vtPID: String,
        major: String,
        graduationYear: String,
        appearanceMode: String
    ) async throws {
        guard let userID = session.user?.id else { return }
        let payload = SupabaseProfilePayload(
            id: userID,
            vtPID: vtPID,
            vtEmail: vtEmail,
            fullName: fullName,
            major: major,
            graduationYear: graduationYear,
            appearanceMode: appearanceMode
        )
        try await restRequest(
            table: "profiles",
            method: "POST",
            body: [payload],
            bearerToken: session.accessToken,
            prefer: "resolution=merge-duplicates,return=minimal",
            query: "on_conflict=id"
        )
    }

    private func saveSession(_ session: SupabaseSession) throws {
        let data = try JSONEncoder().encode(session)
        try KeychainStore.save(data, service: sessionKey)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        body: [String: Any]
    ) async throws -> Response {
        guard let url = URL(string: "\(SupabaseConfig.url)\(path)") else {
            throw SupabaseAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SupabaseAuthError.network(error)
        }

        try validate(data: data, response: response)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SupabaseAuthError.decoding(error)
        }
    }

    private func restRequest<Body: Encodable>(
        table: String,
        method: String,
        body: Body,
        bearerToken: String,
        prefer: String,
        query: String? = nil
    ) async throws {
        var urlString = "\(SupabaseConfig.url)/rest/v1/\(table)"
        if let query { urlString += "?\(query)" }
        guard let url = URL(string: urlString) else { throw SupabaseAuthError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SupabaseAuthError.network(error)
        }
        try validate(data: data, response: response)
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }

        if let errorBody = try? JSONDecoder().decode(SupabaseErrorBody.self, from: data) {
            throw SupabaseAuthError.server(errorBody.message ?? errorBody.errorDescription ?? errorBody.msg ?? "Supabase returned \(http.statusCode).")
        }
        let text = String(data: data, encoding: .utf8) ?? "Supabase returned \(http.statusCode)."
        throw SupabaseAuthError.server(text)
    }
}

private struct SupabaseErrorBody: Decodable {
    let msg: String?
    let message: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case msg, message
        case errorDescription = "error_description"
    }
}

private enum KeychainStore {
    static func save(_ data: Data, service: String) throws {
        delete(service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SupabaseAuthError.keychain(status) }
    }

    static func read(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
