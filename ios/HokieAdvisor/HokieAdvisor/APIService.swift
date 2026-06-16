import Foundation
import Combine

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(Int)
    case serverMessage(Int, String?, String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid server URL."
        case .networkError(let e):
            let nsError = e as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorCannotConnectToHost,
                     NSURLErrorNotConnectedToInternet,
                     NSURLErrorNetworkConnectionLost,
                     NSURLErrorTimedOut,
                     NSURLErrorCannotFindHost:
                    return "We could not analyze your file right now. Check your connection and try again."
                default:
                    break
                }
            }
            return e.localizedDescription
        case .serverError:
            return "We could not analyze your file right now. Check your connection and try again."
        case .serverMessage(let statusCode, _, let message):
            return "\(message) (HTTP \(statusCode))"
        case .decodingError:       return "Could not read server response."
        }
    }

    var userTitle: String {
        switch self {
        case .networkError:
            return "Server unavailable"
        case .serverMessage(let statusCode, _, _), .serverError(let statusCode):
            switch statusCode {
            case 400:
                return "Bad request"
            case 401:
                return "Unauthorized"
            case 403:
                return "Forbidden"
            case 404:
                return "Not found"
            case 413:
                return "File too large"
            case 415:
                return "Unsupported file"
            case 422:
                return "Could not process file"
            case 500...599:
                return "Server error"
            default:
                return "HTTP \(statusCode)"
            }
        case .decodingError:
            return "Response error"
        default:
            return "Upload failed"
        }
    }
}

private struct APIErrorBody: Decodable {
    let detail: APIErrorDetail?
}

private enum APIErrorDetail: Decodable {
    case message(String)
    case coded(code: String?, message: String)

    var code: String? {
        switch self {
        case .message:
            return nil
        case .coded(let code, _):
            return code
        }
    }

    var message: String {
        switch self {
        case .message(let message):
            return message
        case .coded(_, let message):
            return message
        }
    }

    enum CodingKeys: String, CodingKey {
        case code, message, detail
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let message = try? container.decode(String.self) {
            self = .message(message)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decodeIfPresent(String.self, forKey: .code)
        let message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .detail)
            ?? "Server returned an error."
        self = .coded(code: code, message: message)
    }
}

final class APIService {
    static let functionBaseURL = "\(SupabaseConfig.url)/functions/v1"
    static let chatFunctionURL = "\(functionBaseURL)/chat"
    static let auditFunctionURL = "\(functionBaseURL)/audit"
    static let darsFunctionURL = "\(functionBaseURL)/dars"
    static let transcriptFunctionURL = "\(functionBaseURL)/transcript"
    static let tutoringFunctionURL = "\(functionBaseURL)/tutoring"

    static func fetchDegreeAudit(request: DegreeAuditRequest) async throws -> DegreeAuditResponse {
        try await post(urlString: auditFunctionURL, body: request, headers: await supabaseFunctionHeaders(includeUserSession: true))
    }

    static func sendChat(request: ChatRequest) async throws -> ChatResponse {
        try await post(urlString: chatFunctionURL, body: request, headers: await supabaseFunctionHeaders(includeUserSession: true))
    }

    static func streamChat(request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let url = URL(string: "\(chatFunctionURL)/stream") else {
                    continuation.finish(throwing: APIError.invalidURL)
                    return
                }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                let headers = await supabaseFunctionHeaders(includeUserSession: true)
                for (key, value) in headers {
                    req.setValue(value, forHTTPHeaderField: key)
                }
                do {
                    req.httpBody = try JSONEncoder().encode(request)
                } catch {
                    continuation.finish(throwing: APIError.decodingError(error))
                    return
                }
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        continuation.finish(throwing: APIError.serverError(http.statusCode))
                        return
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        if let data = payload.data(using: .utf8),
                           let token = try? JSONDecoder().decode(String.self, from: data) {
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError.networkError(error))
                }
            }
        }
    }

    static func fetchTutoring(request: TutoringRequest) async throws -> TutoringResponse {
        try await post(urlString: tutoringFunctionURL, body: request, headers: await supabaseFunctionHeaders(includeUserSession: true))
    }

    static func uploadDarsAudit(fileData: Data, mimeType: String, fileName: String) async throws -> DarsAuditResponse {
        try await uploadMultipart(
            urlString: darsFunctionURL,
            fileData: fileData,
            mimeType: mimeType,
            fileName: fileName,
            headers: await supabaseFunctionHeaders(includeUserSession: true)
        )
    }

    static func uploadTranscript(fileData: Data, mimeType: String, fileName: String) async throws -> TranscriptResponse {
        try await uploadMultipart(
            urlString: transcriptFunctionURL,
            fileData: fileData,
            mimeType: mimeType,
            fileName: fileName,
            headers: await supabaseFunctionHeaders(includeUserSession: true)
        )
    }

    // MARK: - Private

    private static func anonymousSupabaseFunctionHeaders() -> [String: String] {
        return [
            "apikey": SupabaseConfig.anonKey,
            "Authorization": "Bearer \(SupabaseConfig.anonKey)",
        ]
    }

    private static func supabaseFunctionHeaders(includeUserSession: Bool) async -> [String: String] {
        var headers = anonymousSupabaseFunctionHeaders()
        guard includeUserSession,
              let session = try? await SupabaseAuthService.shared.validatedCurrentSession() else {
            return headers
        }
        headers["Authorization"] = "Bearer \(session.accessToken)"
        return headers
    }

    private static func uploadMultipart<Response: Decodable>(
        urlString: String,
        fileData: Data,
        mimeType: String,
        fileName: String,
        headers: [String: String]
    ) async throws -> Response {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.default
            c.timeoutIntervalForRequest = 120
            c.timeoutIntervalForResource = 120
            return c
        }())
        let data: Data
        let response: URLResponse
        debugLogRequest(endpoint: urlString, method: "POST", mimeType: mimeType, size: fileData.count, hasUserSession: usesUserSession(headers))
        do { (data, response) = try await session.data(for: req) } catch { throw APIError.networkError(error) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            debugLogResponse(endpoint: urlString, statusCode: http.statusCode, data: data)
            throw error(from: data, statusCode: http.statusCode)
        }
        if let http = response as? HTTPURLResponse {
            debugLogResponse(endpoint: urlString, statusCode: http.statusCode, data: nil)
        }
        do { return try JSONDecoder().decode(Response.self, from: data) } catch { throw APIError.decodingError(error) }
    }

    private static func post<Body: Encodable, Response: Decodable>(
        urlString: String,
        body: Body,
        headers: [String: String] = [:]
    ) async throws -> Response {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        return try await post(url: url, body: body, headers: headers)
    }

    private static func post<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body,
        headers: [String: String] = [:]
    ) async throws -> Response {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        do { req.httpBody = try JSONEncoder().encode(body) } catch { throw APIError.decodingError(error) }

        let data: Data
        let response: URLResponse
        debugLogRequest(endpoint: url.absoluteString, method: "POST", mimeType: nil, size: nil, hasUserSession: usesUserSession(headers))
        do { (data, response) = try await URLSession.shared.data(for: req) } catch { throw APIError.networkError(error) }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            debugLogResponse(endpoint: url.absoluteString, statusCode: http.statusCode, data: data)
            throw error(from: data, statusCode: http.statusCode)
        }
        if let http = response as? HTTPURLResponse {
            debugLogResponse(endpoint: url.absoluteString, statusCode: http.statusCode, data: nil)
        }
        do { return try JSONDecoder().decode(Response.self, from: data) } catch { throw APIError.decodingError(error) }
    }

    private static func error(from data: Data, statusCode: Int) -> APIError {
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data),
           let detail = body.detail,
           !detail.message.isEmpty {
            return .serverMessage(statusCode, detail.code, detail.message)
        }
        return .serverError(statusCode)
    }

    private static func usesUserSession(_ headers: [String: String]) -> Bool {
        guard let authorization = headers["Authorization"] else { return false }
        return authorization != "Bearer \(SupabaseConfig.anonKey)"
    }

    private static func debugLogRequest(endpoint: String, method: String, mimeType: String?, size: Int?, hasUserSession: Bool) {
        #if DEBUG
        var parts = [
            "[APIService]",
            method,
            endpoint,
            "authSession=\(hasUserSession ? "user" : "anon")",
        ]
        if let mimeType { parts.append("mime=\(mimeType)") }
        if let size { parts.append("bytes=\(size)") }
        print(parts.joined(separator: " "))
        #endif
    }

    private static func debugLogResponse(endpoint: String, statusCode: Int, data: Data?) {
        #if DEBUG
        var message = "[APIService] response \(statusCode) \(endpoint)"
        if let data, let body = String(data: data.prefix(800), encoding: .utf8) {
            message += " body=\(redactSecrets(body))"
        }
        print(message)
        #endif
    }

    private static func redactSecrets(_ value: String) -> String {
        value.replacingOccurrences(of: SupabaseConfig.anonKey, with: "[redacted]")
    }
}
