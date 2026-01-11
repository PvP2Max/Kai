import Foundation

// MARK: - Meeting Model

/// Meeting model matching the backend MeetingResponse schema.
/// Represents a meeting with optional transcript and AI-generated summary.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct Meeting: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let calendarEventId: String?
    let eventTitle: String?
    let eventStart: Date?
    let eventEnd: Date?
    let transcript: String?
    let summary: MeetingSummary?
    let projectId: UUID?
    let actionItems: [ActionItem]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        calendarEventId: String? = nil,
        eventTitle: String? = nil,
        eventStart: Date? = nil,
        eventEnd: Date? = nil,
        transcript: String? = nil,
        summary: MeetingSummary? = nil,
        projectId: UUID? = nil,
        actionItems: [ActionItem] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.calendarEventId = calendarEventId
        self.eventTitle = eventTitle
        self.eventStart = eventStart
        self.eventEnd = eventEnd
        self.transcript = transcript
        self.summary = summary
        self.projectId = projectId
        self.actionItems = actionItems
        self.createdAt = createdAt
    }

    // Computed properties for UI
    var displayTitle: String {
        eventTitle ?? "Untitled Meeting"
    }

    var hasTranscript: Bool {
        transcript != nil && !transcript!.isEmpty
    }

    var hasSummary: Bool {
        summary != nil
    }

    var displayDate: String {
        guard let start = eventStart else {
            return DateFormatter.mediumDateFormatter.string(from: createdAt)
        }
        return DateFormatter.mediumDateFormatter.string(from: start)
    }

    var displayTime: String? {
        guard let start = eventStart else { return nil }
        return DateFormatter.timeFormatter.string(from: start)
    }

    /// Formatted date range for display
    var dateRangeDisplay: String? {
        guard let start = eventStart else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        if let end = eventEnd {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "\(dateFormatter.string(from: start)) - \(timeFormatter.string(from: end))"
        }

        return dateFormatter.string(from: start)
    }
}

// MARK: - Meeting Summary

/// AI-generated summary of a meeting.
/// Matches the backend MeetingSummary schema.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct MeetingSummary: Codable, Equatable, Hashable, Sendable {
    let discussion: String?
    let keyPoints: [String]?
    let actionItems: [String]?
    let attendees: [String]?

    init(
        discussion: String? = nil,
        keyPoints: [String]? = nil,
        actionItems: [String]? = nil,
        attendees: [String]? = nil
    ) {
        self.discussion = discussion
        self.keyPoints = keyPoints
        self.actionItems = actionItems
        self.attendees = attendees
    }

    /// Returns the total count of key points and action items
    var itemCount: Int {
        (keyPoints?.count ?? 0) + (actionItems?.count ?? 0)
    }

    /// Whether the summary has any content
    var isEmpty: Bool {
        (discussion?.isEmpty ?? true) &&
        (keyPoints?.isEmpty ?? true) &&
        (actionItems?.isEmpty ?? true)
    }
}

// MARK: - Action Item

/// Action item extracted from a meeting.
/// Matches the backend ActionItemResponse schema.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct ActionItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let description: String
    let owner: String?
    let dueDate: Date?
    let priority: ActionPriority
    let status: ActionStatus
    let reminderId: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        description: String,
        owner: String? = nil,
        dueDate: Date? = nil,
        priority: ActionPriority = .medium,
        status: ActionStatus = .pending,
        reminderId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.description = description
        self.owner = owner
        self.dueDate = dueDate
        self.priority = priority
        self.status = status
        self.reminderId = reminderId
        self.createdAt = createdAt
    }
}

// MARK: - Action Priority

/// Priority level for action items
enum ActionPriority: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high

    var displayName: String {
        rawValue.capitalized
    }

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

// MARK: - Action Status

/// Status of an action item
enum ActionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled

    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .inProgress:
            return "In Progress"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

// MARK: - Meeting Upload Response

/// Response from uploading meeting audio.
/// Matches the backend MeetingUploadResponse schema.
struct MeetingUploadResponse: Codable, Sendable {
    let id: UUID
    let message: String
    let transcript: String?
    let summary: MeetingSummary?
}

// MARK: - Date Formatter Extensions

extension DateFormatter {
    static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let iso8601Full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
