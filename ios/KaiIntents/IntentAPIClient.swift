import Foundation
import Security

/// Lightweight API client for App Intents
/// Uses shared keychain for authentication tokens
actor IntentAPIClient {

    // MARK: - Configuration

    static let shared = IntentAPIClient()

    private let baseURL = URL(string: "https://kai.pvp2max.com")!
    private let keychainServiceName = "com.arcticauradesigns.kai.auth"
    private let keychainAccessGroup = "group.com.arcticauradesigns.kai"
    private let accessTokenKey = "access_token"

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Keychain Access

    /// Retrieves the access token from shared keychain
    func getAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: accessTokenKey,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    // MARK: - API Requests

    /// Chat request to Kai
    func sendChatMessage(
        message: String,
        conversationId: String? = nil
    ) async throws -> IntentChatResponse {
        let endpoint = baseURL.appendingPathComponent("/api/chat")

        var body: [String: Any] = [
            "message": message,
            "source": "siri"
        ]

        if let conversationId = conversationId {
            body["conversation_id"] = conversationId
        }

        let data = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: body
        )

        return try JSONDecoder().decode(IntentChatResponse.self, from: data)
    }

    /// Fetch daily briefing
    func getDailyBriefing() async throws -> BriefingResponse {
        let endpoint = baseURL.appendingPathComponent("/api/briefing")

        let data = try await performRequest(
            endpoint: endpoint,
            method: "GET"
        )

        return try JSONDecoder().decode(BriefingResponse.self, from: data)
    }

    /// Create a meeting recording session
    func createMeetingSession(title: String?) async throws -> MeetingSessionResponse {
        let endpoint = baseURL.appendingPathComponent("/api/meetings")

        var body: [String: Any] = [:]
        if let title = title {
            body["title"] = title
        }

        let data = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: body
        )

        return try JSONDecoder().decode(MeetingSessionResponse.self, from: data)
    }

    // MARK: - Private Helpers

    private func performRequest(
        endpoint: URL,
        method: String,
        body: [String: Any]? = nil
    ) async throws -> Data {
        guard let token = getAccessToken() else {
            throw IntentAPIError.notAuthenticated
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Kai-iOS-Siri/1.0", forHTTPHeaderField: "User-Agent")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IntentAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw IntentAPIError.notAuthenticated
        case 403:
            throw IntentAPIError.forbidden
        case 404:
            throw IntentAPIError.notFound
        case 429:
            throw IntentAPIError.rateLimited
        case 500...599:
            throw IntentAPIError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw IntentAPIError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Response Models

struct IntentChatResponse: Codable {
    let response: String
    let conversationId: String
    let requiresFollowUp: Bool?
    let followUpQuestion: String?
    let actionTaken: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case response
        case conversationId = "conversation_id"
        case requiresFollowUp = "requires_follow_up"
        case followUpQuestion = "follow_up_question"
        case actionTaken = "action_taken"
        case model
    }
}

struct BriefingResponse: Codable {
    let summary: String
    let greeting: String
    let weather: WeatherInfo?
    let upcomingEvents: [BriefingEvent]
    let tasks: [BriefingTask]
    let unreadEmailCount: Int?

    enum CodingKeys: String, CodingKey {
        case summary
        case greeting
        case weather
        case upcomingEvents = "upcoming_events"
        case tasks
        case unreadEmailCount = "unread_email_count"
    }
}

struct WeatherInfo: Codable {
    let temperature: Double
    let condition: String
    let high: Double?
    let low: Double?
}

struct BriefingEvent: Codable {
    let id: String
    let title: String
    let startTime: String
    let endTime: String?
    let location: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startTime = "start_time"
        case endTime = "end_time"
        case location
    }
}

struct BriefingTask: Codable {
    let id: String
    let title: String
    let priority: String?
    let dueDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case priority
        case dueDate = "due_date"
    }
}

struct MeetingSessionResponse: Codable {
    let id: String
    let title: String?
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case createdAt = "created_at"
    }
}

// MARK: - Errors

enum IntentAPIError: LocalizedError {
    case notAuthenticated
    case forbidden
    case notFound
    case rateLimited
    case invalidResponse
    case serverError(statusCode: Int)
    case httpError(statusCode: Int)
    case encodingError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please open the Kai app and sign in first."
        case .forbidden:
            return "You don't have permission to perform this action."
        case .notFound:
            return "The requested resource was not found."
        case .rateLimited:
            return "Too many requests. Please try again in a moment."
        case .invalidResponse:
            return "Received an invalid response from Kai."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .httpError(let code):
            return "Request failed with status \(code)."
        case .encodingError:
            return "Failed to encode the request."
        }
    }
}
