//
//  APIClient.swift
//  Kai
//
//  REST API client with automatic token refresh.
//

import Foundation

/// Thread-safe actor for coordinating token refresh operations.
actor TokenRefreshCoordinator {
    private var isRefreshing = false
    private var refreshTask: Task<String, Error>?

    /// Gets a valid access token, refreshing if necessary.
    /// Ensures only one refresh operation happens at a time.
    func getValidToken() async throws -> String {
        // If we're already refreshing, wait for that to complete
        if let task = refreshTask {
            return try await task.value
        }

        let keychain = KeychainManager.shared

        // Check if current token is valid
        if let accessToken = keychain.getAccessToken(), !keychain.isTokenExpired() {
            return accessToken
        }

        // Need to refresh - create a task so others can wait
        let task = Task<String, Error> {
            defer { refreshTask = nil }
            return try await performRefresh()
        }

        refreshTask = task
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        let keychain = KeychainManager.shared

        guard let refreshToken = keychain.getRefreshToken() else {
            throw APIError.notAuthenticated
        }

        let url = URL(string: "\(APIClient.baseURL)/api/auth/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = TokenRefreshRequest(refreshToken: refreshToken)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            // Refresh token is also invalid - user needs to re-authenticate
            keychain.clearTokens()
            throw APIError.notAuthenticated
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        // Save new tokens
        try keychain.saveTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken
        )

        return tokenResponse.accessToken
    }
}

/// Main API client for communicating with the Kai backend.
final class APIClient {

    // MARK: - Singleton

    static let shared = APIClient()

    // MARK: - Configuration

    static let baseURL = "https://kai.pvp2max.com"

    // MARK: - Properties

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenCoordinator = TokenRefreshCoordinator()

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Custom date decoder to handle various ISO8601 formats from the backend
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds and timezone
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // Try standard ISO8601 with timezone
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // Try without timezone (backend returns dates without Z suffix)
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

            // Format with microseconds (6 digits): 2026-01-10T04:36:06.662524
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            if let date = dateFormatter.date(from: dateString) {
                return date
            }

            // Format with milliseconds (3 digits): 2026-01-10T04:36:06.662
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            if let date = dateFormatter.date(from: dateString) {
                return date
            }

            // Format without fractional seconds: 2026-01-10T04:36:06
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = dateFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Endpoints

    enum Endpoint {
        // Auth
        case login
        case register
        case refresh
        case me

        // Chat
        case chat
        case conversations
        case conversation(id: String)

        // Calendar
        case calendarEvents
        case calendarEvent(id: String)
        case calendarEventsSync
        case calendarOptimize

        // Notes
        case notes
        case note(id: String)
        case notesSearch

        // Meetings
        case meetings
        case meeting(id: String)
        case meetingTranscribe(id: String)

        // Devices
        case registerDevice

        var path: String {
            switch self {
            case .login:
                return "/api/auth/login"
            case .register:
                return "/api/auth/register"
            case .refresh:
                return "/api/auth/refresh"
            case .me:
                return "/api/auth/me"
            case .chat:
                return "/api/chat"
            case .conversations:
                return "/api/conversations"
            case .conversation(let id):
                return "/api/conversations/\(id)"
            case .calendarEvents:
                return "/api/calendar/events"
            case .calendarEvent(let id):
                return "/api/calendar/events/\(id)"
            case .calendarEventsSync:
                return "/api/calendar/events/sync"
            case .calendarOptimize:
                return "/api/calendar/optimize"
            case .notes:
                return "/api/notes"
            case .note(let id):
                return "/api/notes/\(id)"
            case .notesSearch:
                return "/api/notes/search"
            case .meetings:
                return "/api/meetings"
            case .meeting(let id):
                return "/api/meetings/\(id)"
            case .meetingTranscribe(let id):
                return "/api/meetings/\(id)/transcribe"
            case .registerDevice:
                return "/api/devices/register"
            }
        }

        var url: URL {
            return URL(string: APIClient.baseURL + path)!
        }
    }

    // MARK: - HTTP Methods

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    // MARK: - Public Request Methods

    /// Performs an authenticated API request.
    /// - Parameters:
    ///   - endpoint: The API endpoint.
    ///   - method: The HTTP method.
    ///   - body: Optional request body (will be JSON encoded).
    ///   - queryItems: Optional query parameters.
    /// - Returns: The decoded response.
    func request<T: Decodable, B: Encodable>(
        _ endpoint: Endpoint,
        method: HTTPMethod = .get,
        body: B? = nil as Empty?,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        // Check network connectivity
        try NetworkMonitor.shared.requireConnection()

        // Get valid access token
        let accessToken = try await tokenCoordinator.getValidToken()

        // Build request
        var request = try buildRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            queryItems: queryItems,
            accessToken: accessToken
        )

        // Execute request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Handle 401 - try token refresh once
        if httpResponse.statusCode == 401 {
            // Force a new token refresh
            let newToken = try await tokenCoordinator.getValidToken()
            request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")

            let (retryData, retryResponse) = try await session.data(for: request)

            guard let retryHttpResponse = retryResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if retryHttpResponse.statusCode == 401 {
                throw APIError.notAuthenticated
            }

            return try handleResponse(data: retryData, response: retryHttpResponse)
        }

        return try handleResponse(data: data, response: httpResponse)
    }

    /// Performs an unauthenticated API request (for login/register).
    func requestUnauthenticated<T: Decodable, B: Encodable>(
        _ endpoint: Endpoint,
        method: HTTPMethod = .post,
        body: B
    ) async throws -> T {
        try NetworkMonitor.shared.requireConnection()

        let request = try buildRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            queryItems: nil,
            accessToken: nil
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        return try handleResponse(data: data, response: httpResponse)
    }

    /// Performs a multipart form upload (for audio files).
    func uploadMultipart<T: Decodable>(
        _ endpoint: Endpoint,
        fileData: Data,
        fileName: String,
        mimeType: String,
        fieldName: String = "file"
    ) async throws -> T {
        try NetworkMonitor.shared.requireConnection()

        let accessToken = try await tokenCoordinator.getValidToken()

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        return try handleResponse(data: data, response: httpResponse)
    }

    // MARK: - Conversation Methods

    /// Fetches all conversations for the current user.
    func getConversations() async throws -> [ConversationSummary] {
        return try await request(.conversations, method: .get)
    }

    /// Fetches a specific conversation by ID.
    func getConversation(id: UUID) async throws -> Conversation {
        return try await request(.conversation(id: id.uuidString), method: .get)
    }

    /// Deletes a conversation.
    func deleteConversation(id: UUID) async throws {
        let _: Empty = try await request(.conversation(id: id.uuidString), method: .delete)
    }

    // MARK: - Private Helpers

    private func buildRequest<B: Encodable>(
        endpoint: Endpoint,
        method: HTTPMethod,
        body: B?,
        queryItems: [URLQueryItem]?,
        accessToken: String?
    ) throws -> URLRequest {
        var urlComponents = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)!

        if let queryItems = queryItems {
            urlComponents.queryItems = queryItems
        }

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accessToken = accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body = body, !(body is Empty) {
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func handleResponse<T: Decodable>(data: Data, response: HTTPURLResponse) throws -> T {
        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("[APIClient] Response (\(response.statusCode)): \(jsonString.prefix(500))")
        }
        #endif

        switch response.statusCode {
        case 200...299:
            // Handle empty response
            if data.isEmpty, T.self == Empty.self {
                return Empty() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                #if DEBUG
                print("[APIClient] Decode error for \(T.self): \(error)")
                #endif
                throw error
            }

        case 400:
            let error = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIError.badRequest(message: error?.detail ?? "Invalid request")

        case 401:
            throw APIError.notAuthenticated

        case 403:
            throw APIError.forbidden

        case 404:
            throw APIError.notFound

        case 422:
            let error = try? decoder.decode(ValidationErrorResponse.self, from: data)
            throw APIError.validationError(errors: error?.detail ?? [])

        case 500...599:
            throw APIError.serverError

        default:
            throw APIError.httpError(statusCode: response.statusCode, data: data)
        }
    }
}

// MARK: - Empty Type for Requests Without Body

struct Empty: Codable {}

// MARK: - API Error

enum APIError: LocalizedError {
    case notAuthenticated
    case forbidden
    case notFound
    case badRequest(message: String)
    case validationError(errors: [ValidationError])
    case serverError
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please log in to continue."
        case .forbidden:
            return "You don't have permission to perform this action."
        case .notFound:
            return "The requested resource was not found."
        case .badRequest(let message):
            return message
        case .validationError(let errors):
            return errors.map { $0.msg }.joined(separator: ", ")
        case .serverError:
            return "A server error occurred. Please try again later."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .httpError(let statusCode, _):
            return "Request failed with status code \(statusCode)."
        case .decodingError(let error):
            return "Failed to process server response: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Error Response Models

struct APIErrorResponse: Decodable {
    let detail: String
}

struct ValidationError: Decodable {
    let loc: [String]
    let msg: String
    let type: String
}

struct ValidationErrorResponse: Decodable {
    let detail: [ValidationError]
}

// MARK: - Auth Request/Response Models

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let name: String
}

struct TokenRefreshRequest: Encodable {
    let refreshToken: String
}

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
}

struct UserResponse: Decodable {
    let id: UUID
    let email: String
    let name: String
    let timezone: String?  // Optional until migration is run
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Device Registration

struct DeviceRegistrationRequest: Encodable {
    let deviceToken: String
    let platform: String
    let deviceName: String?

    init(deviceToken: String, deviceName: String? = nil) {
        self.deviceToken = deviceToken
        self.platform = "ios"
        self.deviceName = deviceName
    }
}

struct DeviceRegistrationResponse: Decodable {
    let deviceId: String
    let message: String
}
