import Foundation

/// Calendar event model matching the backend CalendarEventResponse schema.
/// Represents an event from the user's calendar.
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct CalendarEvent: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier for the event
    let id: String

    /// Event title
    let title: String

    /// Event start time
    let start: Date

    /// Event end time
    let end: Date

    /// Whether this is an all-day event
    let isAllDay: Bool

    /// Event location (optional)
    let location: String?

    /// Event description/notes (optional)
    let notes: String?

    /// List of attendee email addresses
    let attendees: [String]

    /// Color of the calendar (hex string)
    let calendarColor: String?

    /// Name of the calendar containing this event
    let calendarName: String?

    /// Recurrence rule description (if recurring)
    let recurrenceRule: String?

    /// Whether this event is protected from schedule optimization
    let isProtected: Bool

    init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        attendees: [String] = [],
        calendarColor: String? = nil,
        calendarName: String? = nil,
        recurrenceRule: String? = nil,
        isProtected: Bool = false
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.attendees = attendees
        self.calendarColor = calendarColor
        self.calendarName = calendarName
        self.recurrenceRule = recurrenceRule
        self.isProtected = isProtected
    }

    /// Duration of the event in seconds
    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    /// Duration of the event in minutes
    var durationMinutes: Int {
        Int(duration / 60)
    }

    /// Formatted time range for display
    var formattedTimeRange: String {
        if isAllDay {
            return "All Day"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    /// Alias for notes (backward compatibility)
    var description: String? {
        notes
    }

    /// Formatted date for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: start)
    }

    /// Whether the event is happening today
    var isToday: Bool {
        Calendar.current.isDateInToday(start)
    }

    /// Whether the event is happening now
    var isHappeningNow: Bool {
        let now = Date()
        return start <= now && end > now
    }

    /// Whether the event has passed
    var isPast: Bool {
        end < Date()
    }

    /// Whether the event is in the future
    var isFuture: Bool {
        start > Date()
    }
}

// MARK: - Create/Update Request Models

/// Request body for creating a calendar event
/// Note: APIClient uses `.convertToSnakeCase` so no CodingKeys needed.
struct CalendarEventCreateRequest: Codable, Sendable {
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let description: String?
    let attendees: [String]?
    let calendarName: String?

    init(
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        description: String? = nil,
        attendees: [String]? = nil,
        calendarName: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.description = description
        self.attendees = attendees
        self.calendarName = calendarName
    }
}

/// Request body for updating a calendar event
struct CalendarEventUpdateRequest: Codable, Sendable {
    let title: String?
    let start: Date?
    let end: Date?
    let location: String?
    let description: String?

    init(
        title: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        location: String? = nil,
        description: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.description = description
    }
}

// MARK: - Schedule Optimization Models

/// A proposed change to the schedule
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct ScheduleChange: Codable, Equatable, Sendable {
    let eventId: String
    let eventTitle: String
    let changeType: ScheduleChangeType
    let originalStart: Date
    let originalEnd: Date
    let newStart: Date?
    let newEnd: Date?
    let reason: String
}

/// Type of schedule change
enum ScheduleChangeType: String, Codable, Sendable {
    case move
    case shorten
    case remove
}

/// Request for schedule optimization
/// Note: APIClient uses `.convertToSnakeCase` so no CodingKeys needed.
struct OptimizationRequest: Codable, Sendable {
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let protectedEventIds: [String]
    let optimizationGoal: OptimizationGoal

    init(
        dateRangeStart: Date,
        dateRangeEnd: Date,
        protectedEventIds: [String] = [],
        optimizationGoal: OptimizationGoal = .efficiency
    ) {
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.protectedEventIds = protectedEventIds
        self.optimizationGoal = optimizationGoal
    }
}

/// Goal for schedule optimization
enum OptimizationGoal: String, Codable, Sendable {
    case efficiency
    case focusTime = "focus_time"
    case balance

    var displayName: String {
        switch self {
        case .efficiency:
            return "Efficiency"
        case .focusTime:
            return "Focus Time"
        case .balance:
            return "Balance"
        }
    }
}

/// Response from schedule optimization
/// Note: APIClient uses `.convertFromSnakeCase` so no CodingKeys needed.
struct OptimizationResponse: Codable, Sendable {
    let suggestions: [ScheduleChange]
    let reasoning: String
    let affectedEvents: [String]
}

/// Request to apply approved optimization changes
/// Note: APIClient uses `.convertToSnakeCase` so no CodingKeys needed.
struct ApplyOptimizationRequest: Codable, Sendable {
    let approvedChanges: [ScheduleChange]
}

// MARK: - Sample Data

extension CalendarEvent {
    static let sample = CalendarEvent(
        id: "1",
        title: "Team Standup",
        start: Date(),
        end: Date().addingTimeInterval(3600),
        isAllDay: false,
        location: "Conference Room A",
        notes: "Daily team sync meeting",
        attendees: ["team@example.com"],
        calendarColor: "#4285F4",
        calendarName: "Work",
        recurrenceRule: nil,
        isProtected: false
    )

    static let samples: [CalendarEvent] = [
        CalendarEvent(
            id: "1",
            title: "Team Standup",
            start: Date(),
            end: Date().addingTimeInterval(3600),
            isAllDay: false,
            location: "Conference Room A",
            notes: "Daily team sync meeting",
            attendees: [],
            calendarColor: "#4285F4",
            calendarName: "Work",
            recurrenceRule: nil,
            isProtected: false
        ),
        CalendarEvent(
            id: "2",
            title: "Lunch with Sarah",
            start: Date().addingTimeInterval(7200),
            end: Date().addingTimeInterval(10800),
            isAllDay: false,
            location: "Cafe Blue",
            notes: nil,
            attendees: ["sarah@example.com"],
            calendarColor: "#34A853",
            calendarName: "Personal",
            recurrenceRule: nil,
            isProtected: false
        ),
        CalendarEvent(
            id: "3",
            title: "Project Review",
            start: Date().addingTimeInterval(14400),
            end: Date().addingTimeInterval(18000),
            isAllDay: false,
            location: nil,
            notes: "Q4 project milestone review",
            attendees: ["manager@example.com", "team@example.com"],
            calendarColor: "#4285F4",
            calendarName: "Work",
            recurrenceRule: nil,
            isProtected: true
        )
    ]
}
