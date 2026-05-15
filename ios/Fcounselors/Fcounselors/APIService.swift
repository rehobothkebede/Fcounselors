import Foundation
import Combine

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid server URL."
        case .networkError(let e): return e.localizedDescription
        case .serverError(let c):  return "Server returned error \(c)."
        case .decodingError:       return "Could not read server response."
        }
    }
}

final class APIService {
    // Change this to your Mac's local IP when running on a physical device.
    // For the iOS Simulator, http://localhost:8000 works fine.
    static let baseURL = "http://127.0.0.1:8000"

    static func fetchPlan(request: PlanRequest) async throws -> PlanResponse {
        try await post(path: "/advisor/plan", body: request)
    }

    static func sendChat(request: ChatRequest) async throws -> ChatResponse {
        try await post(path: "/chat", body: request)
    }

    static func fetchTutoring(request: TutoringRequest) async throws -> TutoringResponse {
        try await post(path: "/tutoring/recommend", body: request)
    }

    static func uploadTranscript(fileData: Data, mimeType: String, fileName: String) async throws -> TranscriptResponse {
        guard let url = URL(string: "\(baseURL)/transcript/upload") else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

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
        do { (data, response) = try await session.data(for: req) } catch { throw APIError.networkError(error) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        do { return try JSONDecoder().decode(TranscriptResponse.self, from: data) } catch { throw APIError.decodingError(error) }
    }

    // MARK: - Private

    private static func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do { req.httpBody = try JSONEncoder().encode(body) } catch { throw APIError.decodingError(error) }

        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) } catch { throw APIError.networkError(error) }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        do { return try JSONDecoder().decode(Response.self, from: data) } catch { throw APIError.decodingError(error) }
    }
}
