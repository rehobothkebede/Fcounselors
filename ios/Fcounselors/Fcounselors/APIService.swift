import Foundation

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
    static let baseURL = "http://localhost:8000"

    static func fetchPlan(request: PlanRequest) async throws -> PlanResponse {
        try await post(path: "/advisor/plan", body: request)
    }

    static func sendChat(request: ChatRequest) async throws -> ChatResponse {
        try await post(path: "/chat", body: request)
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
