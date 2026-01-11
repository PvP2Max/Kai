//
//  MeetingsViewModel.swift
//  Kai
//
//  Created by Kai on 2024.
//

import Foundation

// MARK: - Meetings View Model

@MainActor
final class MeetingsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var uploadProgress: Double?
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    // MARK: - Private Properties

    private let baseURL: URL
    private let session: URLSession

    // MARK: - Initialization

    init(baseURL: URL = URL(string: "https://kai.pvp2max.com")!) {
        self.baseURL = baseURL

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300 // 5 minutes for transcription
        configuration.timeoutIntervalForResource = 600 // 10 minutes total
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Public Methods

    /// Loads all meetings from the API
    func loadMeetings() async {
        isLoading = true
        errorMessage = nil

        do {
            let url = baseURL.appendingPathComponent("/api/meetings")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            addAuthHeader(to: &request)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MeetingsError.invalidResponse
            }

            // Handle 404 as "no meetings" rather than an error
            if httpResponse.statusCode == 404 {
                meetings = []
                isLoading = false
                return
            }

            guard httpResponse.statusCode == 200 else {
                throw MeetingsError.serverError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                // Try multiple date formats
                let formatters: [DateFormatter] = [
                    .iso8601Full,
                    {
                        let f = DateFormatter()
                        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                        f.timeZone = TimeZone(secondsFromGMT: 0)
                        return f
                    }(),
                    {
                        let f = DateFormatter()
                        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                        f.timeZone = TimeZone(secondsFromGMT: 0)
                        return f
                    }()
                ]

                for formatter in formatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }

                // Try ISO8601DateFormatter as fallback
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoFormatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Cannot decode date: \(dateString)"
                )
            }

            meetings = try decoder.decode([Meeting].self, from: data)

        } catch let error as MeetingsError {
            handleError(error)
        } catch {
            handleError(.networkError(error))
        }

        isLoading = false
    }

    /// Uploads a recording and triggers transcription
    /// - Parameters:
    ///   - url: The URL of the audio file to upload
    ///   - title: Optional title for the meeting
    /// - Returns: The created meeting
    @discardableResult
    func uploadRecording(url: URL, title: String? = nil) async throws -> Meeting {
        uploadProgress = 0
        errorMessage = nil

        defer {
            Task { @MainActor in
                uploadProgress = nil
            }
        }

        // First, create a meeting
        let meeting = try await createMeeting(title: title)

        // Then upload the audio file for transcription
        let transcribedMeeting = try await transcribeMeeting(meetingId: meeting.id, audioURL: url)

        // Refresh the meetings list
        await loadMeetings()

        return transcribedMeeting
    }

    /// Refreshes a single meeting by ID
    func refreshMeeting(id: UUID) async -> Meeting? {
        do {
            let url = baseURL.appendingPathComponent("/api/meetings/\(id)")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            addAuthHeader(to: &request)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Meeting.self, from: data)
        } catch {
            print("Error refreshing meeting: \(error)")
            return nil
        }
    }

    /// Deletes a meeting
    func deleteMeeting(id: UUID) async throws {
        let url = baseURL.appendingPathComponent("/api/meetings/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeetingsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            throw MeetingsError.serverError(statusCode: httpResponse.statusCode)
        }

        // Remove from local list
        meetings.removeAll { $0.id == id }
    }

    // MARK: - Private Methods

    private func createMeeting(title: String?) async throws -> Meeting {
        let url = baseURL.appendingPathComponent("/api/meetings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body: [String: Any] = [
            "event_title": title ?? "New Recording",
            "event_start": ISO8601DateFormatter().string(from: Date())
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeetingsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw MeetingsError.serverError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Meeting.self, from: data)
    }

    private func transcribeMeeting(meetingId: UUID, audioURL: URL) async throws -> Meeting {
        let url = baseURL.appendingPathComponent("/api/meetings/\(meetingId)/transcribe")

        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        // Build multipart body
        var body = Data()

        // Add file field
        let filename = audioURL.lastPathComponent
        let mimeType = "audio/mp4"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)

        let fileData = try Data(contentsOf: audioURL)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Update progress
        uploadProgress = 0.3

        let (data, response) = try await session.data(for: request)

        uploadProgress = 0.9

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeetingsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                throw MeetingsError.uploadFailed(errorText)
            }
            throw MeetingsError.serverError(statusCode: httpResponse.statusCode)
        }

        uploadProgress = 1.0

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // The response might be MeetingUploadResponse or Meeting depending on API version
        if let uploadResponse = try? decoder.decode(MeetingUploadResponse.self, from: data) {
            // Fetch the full meeting object
            if let fullMeeting = await refreshMeeting(id: uploadResponse.id) {
                return fullMeeting
            }
            // Create a partial meeting from upload response
            return Meeting(
                id: uploadResponse.id,
                transcript: uploadResponse.transcript,
                summary: uploadResponse.summary
            )
        }

        return try decoder.decode(Meeting.self, from: data)
    }

    private func addAuthHeader(to request: inout URLRequest) {
        if let token = KeychainManager.shared.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func handleError(_ error: MeetingsError) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - Meetings Error

enum MeetingsError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)
    case networkError(Error)
    case uploadFailed(String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let statusCode):
            return "Server error (status: \(statusCode))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
