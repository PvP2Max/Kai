import Foundation

/// Manages offline storage of messages and uploads using UserDefaults with App Groups.
/// Enables data sharing between the main app and extensions (widgets, Siri intents).
final class OfflineQueue: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = OfflineQueue()

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let messagesKey = "offline_messages"
    private let uploadsKey = "offline_uploads"
    private let pendingActionsKey = "pending_actions"

    private let queue = DispatchQueue(label: "com.kamron.kai.offlinequeue", qos: .utility)

    // MARK: - Initialization

    private init() {
        // Use App Group UserDefaults for sharing between app and extensions
        if let sharedDefaults = UserDefaults(suiteName: AppEnvironment.appGroupIdentifier) {
            self.userDefaults = sharedDefaults
        } else {
            // Fallback to standard UserDefaults if App Group is not available
            self.userDefaults = UserDefaults.standard
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Offline Messages

    /// Queues a message for sending when online
    func queueMessage(_ message: OfflineMessage) {
        queue.async { [weak self] in
            guard let self = self else { return }

            var messages = self.getQueuedMessages()

            // Enforce maximum queue size
            if messages.count >= AppEnvironment.maxOfflineQueueSize {
                // Remove oldest messages to make room
                messages.removeFirst(messages.count - AppEnvironment.maxOfflineQueueSize + 1)
            }

            messages.append(message)
            self.saveMessages(messages)
        }
    }

    /// Returns all queued messages
    func getQueuedMessages() -> [OfflineMessage] {
        guard let data = userDefaults.data(forKey: messagesKey),
              let messages = try? decoder.decode([OfflineMessage].self, from: data) else {
            return []
        }
        return messages
    }

    /// Removes a message from the queue after successful sending
    func removeMessage(withId id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }

            var messages = self.getQueuedMessages()
            messages.removeAll { $0.id == id }
            self.saveMessages(messages)
        }
    }

    /// Removes all queued messages
    func clearMessages() {
        queue.async { [weak self] in
            self?.userDefaults.removeObject(forKey: self?.messagesKey ?? "")
        }
    }

    private func saveMessages(_ messages: [OfflineMessage]) {
        if let data = try? encoder.encode(messages) {
            userDefaults.set(data, forKey: messagesKey)
        }
    }

    // MARK: - Offline Uploads

    /// Queues an audio upload for processing when online
    func queueUpload(_ upload: OfflineUpload) {
        queue.async { [weak self] in
            guard let self = self else { return }

            var uploads = self.getQueuedUploads()

            // Enforce maximum queue size
            if uploads.count >= AppEnvironment.maxOfflineQueueSize {
                uploads.removeFirst(uploads.count - AppEnvironment.maxOfflineQueueSize + 1)
            }

            uploads.append(upload)
            self.saveUploads(uploads)
        }
    }

    /// Returns all queued uploads
    func getQueuedUploads() -> [OfflineUpload] {
        guard let data = userDefaults.data(forKey: uploadsKey),
              let uploads = try? decoder.decode([OfflineUpload].self, from: data) else {
            return []
        }
        return uploads
    }

    /// Removes an upload from the queue after successful processing
    func removeUpload(withId id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }

            var uploads = self.getQueuedUploads()
            uploads.removeAll { $0.id == id }
            self.saveUploads(uploads)
        }
    }

    /// Updates the status of an upload
    func updateUploadStatus(id: UUID, status: OfflineUpload.Status, error: String? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }

            var uploads = self.getQueuedUploads()
            if let index = uploads.firstIndex(where: { $0.id == id }) {
                uploads[index].status = status
                uploads[index].errorMessage = error
                uploads[index].retryCount += (status == .failed ? 1 : 0)
            }
            self.saveUploads(uploads)
        }
    }

    /// Removes all queued uploads
    func clearUploads() {
        queue.async { [weak self] in
            self?.userDefaults.removeObject(forKey: self?.uploadsKey ?? "")
        }
    }

    private func saveUploads(_ uploads: [OfflineUpload]) {
        if let data = try? encoder.encode(uploads) {
            userDefaults.set(data, forKey: uploadsKey)
        }
    }

    // MARK: - Pending Actions

    /// Queues an action for execution when online
    func queueAction(_ action: PendingAction) {
        queue.async { [weak self] in
            guard let self = self else { return }

            var actions = self.getPendingActions()

            if actions.count >= AppEnvironment.maxOfflineQueueSize {
                actions.removeFirst(actions.count - AppEnvironment.maxOfflineQueueSize + 1)
            }

            actions.append(action)
            self.saveActions(actions)
        }
    }

    /// Returns all pending actions
    func getPendingActions() -> [PendingAction] {
        guard let data = userDefaults.data(forKey: pendingActionsKey),
              let actions = try? decoder.decode([PendingAction].self, from: data) else {
            return []
        }
        return actions
    }

    /// Removes an action from the queue after successful execution
    func removeAction(withId id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }

            var actions = self.getPendingActions()
            actions.removeAll { $0.id == id }
            self.saveActions(actions)
        }
    }

    /// Removes all pending actions
    func clearActions() {
        queue.async { [weak self] in
            self?.userDefaults.removeObject(forKey: self?.pendingActionsKey ?? "")
        }
    }

    private func saveActions(_ actions: [PendingAction]) {
        if let data = try? encoder.encode(actions) {
            userDefaults.set(data, forKey: pendingActionsKey)
        }
    }

    // MARK: - Utility

    /// Returns the total count of all queued items
    var totalQueuedCount: Int {
        getQueuedMessages().count + getQueuedUploads().count + getPendingActions().count
    }

    /// Returns whether there are any queued items
    var hasQueuedItems: Bool {
        totalQueuedCount > 0
    }

    /// Clears all queued data
    func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.userDefaults.removeObject(forKey: self.messagesKey)
            self.userDefaults.removeObject(forKey: self.uploadsKey)
            self.userDefaults.removeObject(forKey: self.pendingActionsKey)
        }
    }

    /// Synchronizes changes to disk
    func synchronize() {
        userDefaults.synchronize()
    }
}

// MARK: - Offline Message Model

/// Represents a chat message queued for offline sending
struct OfflineMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let message: String
    let conversationId: UUID?
    let source: ChatSource
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case message
        case conversationId = "conversation_id"
        case source
        case createdAt = "created_at"
    }

    init(
        id: UUID = UUID(),
        message: String,
        conversationId: UUID? = nil,
        source: ChatSource = .ios,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.message = message
        self.conversationId = conversationId
        self.source = source
        self.createdAt = createdAt
    }

    /// Converts to a ChatRequest for sending
    func toChatRequest() -> ChatRequest {
        ChatRequest(
            message: message,
            conversationId: conversationId,
            source: source
        )
    }
}

// MARK: - Offline Upload Model

/// Represents an audio file queued for offline upload
struct OfflineUpload: Codable, Identifiable, Sendable {
    let id: UUID
    let fileURL: URL
    let meetingId: UUID?
    let eventTitle: String?
    let eventStart: Date?
    let eventEnd: Date?
    let createdAt: Date
    var status: Status
    var retryCount: Int
    var errorMessage: String?

    enum Status: String, Codable, Sendable {
        case pending
        case uploading
        case processing
        case completed
        case failed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fileURL = "file_url"
        case meetingId = "meeting_id"
        case eventTitle = "event_title"
        case eventStart = "event_start"
        case eventEnd = "event_end"
        case createdAt = "created_at"
        case status
        case retryCount = "retry_count"
        case errorMessage = "error_message"
    }

    init(
        id: UUID = UUID(),
        fileURL: URL,
        meetingId: UUID? = nil,
        eventTitle: String? = nil,
        eventStart: Date? = nil,
        eventEnd: Date? = nil,
        createdAt: Date = Date(),
        status: Status = .pending,
        retryCount: Int = 0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.meetingId = meetingId
        self.eventTitle = eventTitle
        self.eventStart = eventStart
        self.eventEnd = eventEnd
        self.createdAt = createdAt
        self.status = status
        self.retryCount = retryCount
        self.errorMessage = errorMessage
    }

    /// Maximum number of retry attempts
    static let maxRetries = 3

    /// Whether this upload can be retried
    var canRetry: Bool {
        status == .failed && retryCount < Self.maxRetries
    }
}

// MARK: - Pending Action Model

/// Represents a generic action queued for offline execution
struct PendingAction: Codable, Identifiable, Sendable {
    let id: UUID
    let type: ActionType
    let payload: Data
    let createdAt: Date

    enum ActionType: String, Codable, Sendable {
        case createNote
        case updateNote
        case deleteNote
        case createEvent
        case updateEvent
        case deleteEvent
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case payload
        case createdAt = "created_at"
    }

    init(
        id: UUID = UUID(),
        type: ActionType,
        payload: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.createdAt = createdAt
    }

    /// Creates a pending action from a Codable payload
    static func create<T: Codable>(type: ActionType, payload: T) -> PendingAction? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return PendingAction(type: type, payload: data)
    }

    /// Decodes the payload to the specified type
    func decodePayload<T: Codable>(_ type: T.Type) -> T? {
        try? JSONDecoder().decode(type, from: payload)
    }
}

// MARK: - Convenience Extensions

extension OfflineQueue {
    /// Creates and queues an offline message from a chat request
    func queueChatRequest(_ request: ChatRequest) {
        let offlineMessage = OfflineMessage(
            message: request.message,
            conversationId: request.conversationId,
            source: request.source
        )
        queueMessage(offlineMessage)
    }

    /// Creates and queues an offline upload from file info
    func queueAudioUpload(
        fileURL: URL,
        meetingId: UUID? = nil,
        eventTitle: String? = nil,
        eventStart: Date? = nil,
        eventEnd: Date? = nil
    ) {
        let upload = OfflineUpload(
            fileURL: fileURL,
            meetingId: meetingId,
            eventTitle: eventTitle,
            eventStart: eventStart,
            eventEnd: eventEnd
        )
        queueUpload(upload)
    }
}
