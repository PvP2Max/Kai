import Foundation
import Combine
import EventKit
import UIKit

/// CalendarViewModel - Hybrid calendar management using both EventKit and Kai's backend.
/// - iOS/Mac: Uses EventKit (device calendar) + syncs to backend database
/// - Web events sync down to device on app launch
/// - Enables cross-platform calendar access for each user
@MainActor
class CalendarViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var events: [CalendarEvent] = []
    @Published var selectedDate: Date = Date()
    @Published var isLoading: Bool = false
    @Published var isSyncing: Bool = false
    @Published var errorMessage: String?
    @Published var viewMode: CalendarViewMode = .month
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    // MARK: - Private Properties
    private let eventStore = EKEventStore()
    private let apiClient = APIClient.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init() {
        checkAuthorizationStatus()
    }

    // MARK: - Computed Properties
    var eventsForSelectedDate: [CalendarEvent] {
        let calendar = Calendar.current
        return events.filter { event in
            calendar.isDate(event.start, inSameDayAs: selectedDate)
        }.sorted { $0.start < $1.start }
    }

    var eventsByDay: [Date: [CalendarEvent]] {
        let calendar = Calendar.current
        var grouped: [Date: [CalendarEvent]] = [:]

        for event in events {
            let startOfDay = calendar.startOfDay(for: event.start)
            if grouped[startOfDay] != nil {
                grouped[startOfDay]?.append(event)
            } else {
                grouped[startOfDay] = [event]
            }
        }

        // Sort events within each day
        for (date, dayEvents) in grouped {
            grouped[date] = dayEvents.sorted { $0.start < $1.start }
        }

        return grouped
    }

    var currentMonthDates: [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1)
        else {
            return []
        }

        var dates: [Date] = []
        var currentDate = monthFirstWeek.start

        while currentDate < monthLastWeek.end {
            dates.append(currentDate)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return dates
    }

    var currentWeekDates: [Date] {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return []
        }

        var dates: [Date] = []
        var currentDate = weekInterval.start

        while currentDate < weekInterval.end {
            dates.append(currentDate)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return dates
    }

    var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }

    var needsAuthorization: Bool {
        authorizationStatus == .notDetermined
    }

    var isAuthorized: Bool {
        if #available(iOS 17.0, *) {
            return authorizationStatus == .fullAccess || authorizationStatus == .writeOnly
        } else {
            return authorizationStatus == .fullAccess
        }
    }

    // MARK: - Authorization Methods

    func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func requestCalendarAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run {
                checkAuthorizationStatus()
            }
            return granted
        } catch {
            #if DEBUG
            print("[CalendarViewModel] Calendar access error: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Event Loading Methods

    /// Loads events from EventKit and syncs with backend
    func loadEvents(for date: Date) async {
        isLoading = true
        errorMessage = nil

        // Check authorization for EventKit
        if !isAuthorized {
            let granted = await requestCalendarAccess()
            if !granted {
                // Fall back to backend-only if no EventKit access
                await loadEventsFromBackendOnly(for: date)
                return
            }
        }

        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else {
            errorMessage = "Invalid date range"
            isLoading = false
            return
        }

        let startDate = calendar.date(byAdding: .day, value: -7, to: monthInterval.start) ?? monthInterval.start
        let endDate = calendar.date(byAdding: .day, value: 7, to: monthInterval.end) ?? monthInterval.end

        // Load from EventKit
        let ekEvents = loadFromEventKit(startDate: startDate, endDate: endDate)

        // Convert to CalendarEvent model
        let localEvents = ekEvents.map { ekEvent in
            CalendarEvent(
                id: ekEvent.eventIdentifier,
                title: ekEvent.title ?? "Untitled Event",
                start: ekEvent.startDate,
                end: ekEvent.endDate,
                isAllDay: ekEvent.isAllDay,
                location: ekEvent.location,
                notes: ekEvent.notes,
                calendarColor: ekEvent.calendar.cgColor.flatMap { UIColor(cgColor: $0).toHex() },
                calendarName: ekEvent.calendar.title,
                recurrenceRule: ekEvent.recurrenceRules?.first?.description
            )
        }

        self.events = localEvents
        self.selectedDate = date

        #if DEBUG
        print("[CalendarViewModel] Loaded \(events.count) events from EventKit")
        #endif

        isLoading = false

        // Sync with backend in background
        Task {
            await syncWithBackend(startDate: startDate, endDate: endDate, localEvents: localEvents)
        }
    }

    /// Load events from EventKit only
    private func loadFromEventKit(startDate: Date, endDate: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        return eventStore.events(matching: predicate)
    }

    /// Fall back to backend-only when EventKit access is denied
    private func loadEventsFromBackendOnly(for date: Date) async {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else {
            errorMessage = "Invalid date range"
            isLoading = false
            return
        }

        let startDate = calendar.date(byAdding: .day, value: -7, to: monthInterval.start) ?? monthInterval.start
        let endDate = calendar.date(byAdding: .day, value: 7, to: monthInterval.end) ?? monthInterval.end

        do {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]

            let queryItems = [
                URLQueryItem(name: "start_date", value: isoFormatter.string(from: startDate)),
                URLQueryItem(name: "end_date", value: isoFormatter.string(from: endDate))
            ]

            let backendEvents: [BackendCalendarEvent] = try await apiClient.request(
                .calendarEvents,
                method: .get,
                body: nil as Empty?,
                queryItems: queryItems
            )

            self.events = backendEvents.map { $0.toCalendarEvent() }
            self.selectedDate = date

        } catch let error as APIError {
            if case .notFound = error {
                self.events = []
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Sync local EventKit events with backend and pull web-created events
    private func syncWithBackend(startDate: Date, endDate: Date, localEvents: [CalendarEvent]) async {
        isSyncing = true

        do {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]

            let queryItems = [
                URLQueryItem(name: "start_date", value: isoFormatter.string(from: startDate)),
                URLQueryItem(name: "end_date", value: isoFormatter.string(from: endDate))
            ]

            // Fetch backend events
            let backendEvents: [BackendCalendarEvent] = try await apiClient.request(
                .calendarEvents,
                method: .get,
                body: nil as Empty?,
                queryItems: queryItems
            )

            // Find web-created events that aren't in EventKit (no eventkit_id or eventkit_id not found locally)
            let webOnlyEvents = backendEvents.filter { backendEvent in
                guard let eventkitId = backendEvent.eventkitId else {
                    // No eventkit_id means it was created on web
                    return true
                }
                // Check if this eventkit_id exists locally
                return !localEvents.contains { $0.id == eventkitId }
            }

            // Add web-created events to EventKit
            for webEvent in webOnlyEvents {
                await addWebEventToEventKit(webEvent)
            }

            // Upload local events to backend (for cross-platform sync)
            await uploadLocalEventsToBackend(localEvents)

            // Reload to show merged events
            if !webOnlyEvents.isEmpty {
                let ekEvents = loadFromEventKit(startDate: startDate, endDate: endDate)
                await MainActor.run {
                    self.events = ekEvents.map { ekEvent in
                        CalendarEvent(
                            id: ekEvent.eventIdentifier,
                            title: ekEvent.title ?? "Untitled Event",
                            start: ekEvent.startDate,
                            end: ekEvent.endDate,
                            isAllDay: ekEvent.isAllDay,
                            location: ekEvent.location,
                            notes: ekEvent.notes,
                            calendarColor: ekEvent.calendar.cgColor.flatMap { UIColor(cgColor: $0).toHex() },
                            calendarName: ekEvent.calendar.title,
                            recurrenceRule: ekEvent.recurrenceRules?.first?.description
                        )
                    }
                }
            }

            #if DEBUG
            print("[CalendarViewModel] Synced with backend. Web events: \(webOnlyEvents.count)")
            #endif

        } catch {
            #if DEBUG
            print("[CalendarViewModel] Sync error: \(error)")
            #endif
        }

        isSyncing = false
    }

    /// Add a web-created event to EventKit
    private func addWebEventToEventKit(_ backendEvent: BackendCalendarEvent) async {
        guard isAuthorized else { return }

        let event = EKEvent(eventStore: eventStore)
        event.title = backendEvent.title

        // Parse start date with fallback
        guard let startDate = parseISO8601Date(backendEvent.start) else {
            #if DEBUG
            print("[CalendarViewModel] Could not parse start date for event: \(backendEvent.title) - \(backendEvent.start)")
            #endif
            return
        }
        event.startDate = startDate

        // Parse end date with fallback (use start + 1 hour if missing)
        if let endDate = parseISO8601Date(backendEvent.end) {
            event.endDate = endDate
        } else {
            event.endDate = startDate.addingTimeInterval(3600) // 1 hour default
        }

        event.isAllDay = backendEvent.isAllDay
        event.location = backendEvent.location
        event.notes = backendEvent.notes
        event.calendar = eventStore.defaultCalendarForNewEvents

        do {
            try eventStore.save(event, span: .thisEvent)

            // Update backend with the eventkit_id for future sync
            let updateRequest = BackendCalendarEventUpdate(eventkitId: event.eventIdentifier)
            let _: BackendCalendarEvent = try await apiClient.request(
                .calendarEvent(id: backendEvent.id),
                method: .put,
                body: updateRequest
            )

            #if DEBUG
            print("[CalendarViewModel] Added web event to EventKit: \(backendEvent.title)")
            #endif
        } catch {
            #if DEBUG
            print("[CalendarViewModel] Failed to add web event to EventKit: \(error)")
            #endif
        }
    }

    /// Upload local EventKit events to backend for cross-platform access
    private func uploadLocalEventsToBackend(_ localEvents: [CalendarEvent]) async {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        for event in localEvents {
            let createRequest = BackendCalendarEventCreate(
                title: event.title,
                start: isoFormatter.string(from: event.start),
                end: isoFormatter.string(from: event.end),
                isAllDay: event.isAllDay,
                location: event.location,
                description: event.notes,
                calendarName: event.calendarName,
                source: "ios",
                eventkitId: event.id
            )

            do {
                // Use sync endpoint which handles upsert
                let _: [BackendCalendarEvent] = try await apiClient.request(
                    .calendarEventsSync,
                    method: .post,
                    body: [createRequest]
                )
            } catch {
                #if DEBUG
                print("[CalendarViewModel] Failed to sync event to backend: \(error)")
                #endif
            }
        }
    }

    func refresh() async {
        await loadEvents(for: selectedDate)
    }

    func selectDate(_ date: Date) {
        selectedDate = date
    }

    func goToToday() {
        selectedDate = Date()
        Task {
            await loadEvents(for: selectedDate)
        }
    }

    func goToPreviousMonth() {
        let calendar = Calendar.current
        if let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
            selectedDate = previousMonth
            Task {
                await loadEvents(for: previousMonth)
            }
        }
    }

    func goToNextMonth() {
        let calendar = Calendar.current
        if let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
            selectedDate = nextMonth
            Task {
                await loadEvents(for: nextMonth)
            }
        }
    }

    func goToPreviousWeek() {
        let calendar = Calendar.current
        if let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) {
            selectedDate = previousWeek
            Task {
                await loadEvents(for: previousWeek)
            }
        }
    }

    func goToNextWeek() {
        let calendar = Calendar.current
        if let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) {
            selectedDate = nextWeek
            Task {
                await loadEvents(for: nextWeek)
            }
        }
    }

    func hasEvents(on date: Date) -> Bool {
        let calendar = Calendar.current
        return events.contains { event in
            calendar.isDate(event.start, inSameDayAs: date)
        }
    }

    func eventCount(on date: Date) -> Int {
        let calendar = Calendar.current
        return events.filter { event in
            calendar.isDate(event.start, inSameDayAs: date)
        }.count
    }

    // MARK: - Event Creation

    /// Creates event in EventKit AND backend
    func createEvent(title: String, startDate: Date, endDate: Date, isAllDay: Bool = false, location: String? = nil, notes: String? = nil) async throws {
        guard isAuthorized else {
            throw CalendarError.unauthorized
        }

        // Create in EventKit
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents

        try eventStore.save(event, span: .thisEvent)

        // Also create in backend for cross-platform sync
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let createRequest = BackendCalendarEventCreate(
            title: title,
            start: isoFormatter.string(from: startDate),
            end: isoFormatter.string(from: endDate),
            isAllDay: isAllDay,
            location: location,
            description: notes,
            calendarName: event.calendar.title,
            source: "ios",
            eventkitId: event.eventIdentifier
        )

        do {
            let _: BackendCalendarEvent = try await apiClient.request(
                .calendarEvents,
                method: .post,
                body: createRequest
            )
        } catch {
            #if DEBUG
            print("[CalendarViewModel] Failed to sync new event to backend: \(error)")
            #endif
        }

        // Refresh events
        await loadEvents(for: selectedDate)
    }

    // MARK: - Event Update

    /// Updates event in EventKit AND backend
    func updateEvent(id: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool = false, location: String? = nil, notes: String? = nil) async throws {
        guard isAuthorized else {
            throw CalendarError.unauthorized
        }

        guard let event = eventStore.event(withIdentifier: id) else {
            throw CalendarError.eventNotFound
        }

        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes

        try eventStore.save(event, span: .thisEvent)

        // Also update in backend
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let updateRequest = BackendCalendarEventCreate(
            title: title,
            start: isoFormatter.string(from: startDate),
            end: isoFormatter.string(from: endDate),
            isAllDay: isAllDay,
            location: location,
            description: notes,
            calendarName: event.calendar.title,
            source: "ios",
            eventkitId: id
        )

        do {
            // Use sync endpoint which handles upsert by eventkit_id
            let _: [BackendCalendarEvent] = try await apiClient.request(
                .calendarEventsSync,
                method: .post,
                body: [updateRequest]
            )
        } catch {
            #if DEBUG
            print("[CalendarViewModel] Failed to sync updated event to backend: \(error)")
            #endif
        }

        // Refresh events
        await loadEvents(for: selectedDate)
    }

    // MARK: - Event Deletion

    /// Deletes event from EventKit AND backend
    func deleteEvent(id: String) async throws {
        guard isAuthorized else {
            throw CalendarError.unauthorized
        }

        guard let event = eventStore.event(withIdentifier: id) else {
            throw CalendarError.eventNotFound
        }

        try eventStore.remove(event, span: .thisEvent)

        // Also delete from backend (find by eventkit_id)
        // Note: Backend would need an endpoint to delete by eventkit_id
        // For now, we just remove locally

        // Remove from local list
        events.removeAll { $0.id == id }
    }

    // MARK: - Date Parsing Helpers

    /// Parses ISO8601 date strings with multiple format fallbacks
    private func parseISO8601Date(_ dateString: String) -> Date? {
        // Try with fractional seconds first
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = isoFormatter.date(from: dateString) {
            return date
        }

        // Try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            return date
        }

        // Try with timezone offset format (+00:00)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        if let date = dateFormatter.date(from: dateString) {
            return date
        }

        // Try basic ISO format
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = dateFormatter.date(from: dateString) {
            return date
        }

        return nil
    }
}

// MARK: - Supporting Types

enum CalendarViewMode: String, CaseIterable {
    case month = "Month"
    case week = "Week"
}

enum CalendarError: LocalizedError {
    case invalidDateRange
    case networkError
    case unauthorized
    case eventNotFound
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return "Invalid date range"
        case .networkError:
            return "Network error occurred"
        case .unauthorized:
            return "Calendar access is required"
        case .eventNotFound:
            return "Event not found"
        case .saveFailed:
            return "Failed to save event"
        }
    }
}

// MARK: - Backend API Models

/// Backend calendar event response
struct BackendCalendarEvent: Codable {
    let id: String
    let title: String
    let start: String
    let end: String
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let attendees: [String]
    let calendarColor: String?
    let calendarName: String?
    let recurrenceRule: String?
    let isProtected: Bool
    let eventkitId: String?

    func toCalendarEvent() -> CalendarEvent {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let startDate = isoFormatter.date(from: start) ?? Date()
        let endDate = isoFormatter.date(from: end) ?? Date()

        return CalendarEvent(
            id: eventkitId ?? id,
            title: title,
            start: startDate,
            end: endDate,
            isAllDay: isAllDay,
            location: location,
            notes: notes,
            calendarColor: calendarColor,
            calendarName: calendarName,
            recurrenceRule: recurrenceRule
        )
    }
}

/// Backend calendar event create request
struct BackendCalendarEventCreate: Codable {
    let title: String
    let start: String
    let end: String
    let isAllDay: Bool
    let location: String?
    let description: String?
    let calendarName: String?
    let source: String?
    let eventkitId: String?
}

/// Backend calendar event update request
struct BackendCalendarEventUpdate: Codable {
    let eventkitId: String?
}

// MARK: - UIColor Extension for Hex Conversion

extension UIColor {
    func toHex() -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}
