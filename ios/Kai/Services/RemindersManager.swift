//
//  RemindersManager.swift
//  Kai
//
//  Manages access to Apple Reminders via EventKit and syncs with backend.
//

import EventKit
import Foundation

// MARK: - Reminder Model for Sync

struct SyncableReminder: Codable {
    let appleReminderId: String
    let title: String
    let notes: String?
    let dueDate: Date?
    let priority: Int
    let isCompleted: Bool
    let completedAt: Date?
    let listName: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case appleReminderId = "apple_reminder_id"
        case title
        case notes
        case dueDate = "due_date"
        case priority
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case listName = "list_name"
        case tags
    }
}

struct ReminderSyncRequest: Codable {
    let reminders: [SyncableReminder]
}

struct ReminderSyncResponse: Codable {
    let syncedCount: Int
    let createdCount: Int
    let updatedCount: Int
    let deletedCount: Int

    enum CodingKeys: String, CodingKey {
        case syncedCount = "synced_count"
        case createdCount = "created_count"
        case updatedCount = "updated_count"
        case deletedCount = "deleted_count"
    }
}

// MARK: - Reminders Manager

@MainActor
final class RemindersManager: ObservableObject {

    // MARK: - Singleton

    static let shared = RemindersManager()

    // MARK: - Published Properties

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var reminders: [EKReminder] = []
    @Published private(set) var reminderLists: [EKCalendar] = []
    @Published private(set) var isSyncing: Bool = false
    @Published var lastSyncDate: Date?

    // MARK: - Private Properties

    private let eventStore = EKEventStore()

    // MARK: - Initialization

    private init() {
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Requests access to Reminders
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToReminders()
                isAuthorized = granted
                return granted
            } else {
                let granted = try await eventStore.requestAccess(to: .reminder)
                isAuthorized = granted
                return granted
            }
        } catch {
            #if DEBUG
            print("[RemindersManager] Failed to request access: \(error)")
            #endif
            isAuthorized = false
            return false
        }
    }

    /// Checks current authorization status
    func checkAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            isAuthorized = authorizationStatus == .fullAccess
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            isAuthorized = authorizationStatus == .authorized
        }
    }

    // MARK: - Fetch Reminders

    /// Fetches all reminders from all lists
    func fetchAllReminders() async -> [EKReminder] {
        guard isAuthorized else {
            let granted = await requestAccess()
            if !granted { return [] }
            return await fetchAllReminders()
        }

        let calendars = eventStore.calendars(for: .reminder)
        reminderLists = calendars

        let predicate = eventStore.predicateForReminders(in: calendars)

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                Task { @MainActor in
                    let result = reminders ?? []
                    self.reminders = result
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Fetches incomplete reminders only
    func fetchIncompleteReminders() async -> [EKReminder] {
        let allReminders = await fetchAllReminders()
        return allReminders.filter { !$0.isCompleted }
    }

    /// Fetches reminders from specific lists
    func fetchReminders(from listNames: [String]) async -> [EKReminder] {
        guard isAuthorized else {
            let granted = await requestAccess()
            if !granted { return [] }
            return await fetchReminders(from: listNames)
        }

        let calendars = eventStore.calendars(for: .reminder)
            .filter { listNames.contains($0.title) }

        guard !calendars.isEmpty else { return [] }

        let predicate = eventStore.predicateForReminders(in: calendars)

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    /// Fetches reminders due today or overdue
    func fetchRemindersDueToday() async -> [EKReminder] {
        guard isAuthorized else {
            let granted = await requestAccess()
            if !granted { return [] }
            return await fetchRemindersDueToday()
        }

        let calendars = eventStore.calendars(for: .reminder)
        let now = Date()
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now)!

        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: endOfDay,
            calendars: calendars
        )

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    // MARK: - Create/Update Reminders

    /// Creates a new reminder
    func createReminder(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        listName: String? = nil,
        priority: Int = 0
    ) async throws -> EKReminder {
        guard isAuthorized else {
            let granted = await requestAccess()
            if !granted {
                throw RemindersError.notAuthorized
            }
            return try await createReminder(title: title, notes: notes, dueDate: dueDate, listName: listName, priority: priority)
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority

        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        // Find or use default calendar
        if let listName = listName,
           let calendar = eventStore.calendars(for: .reminder).first(where: { $0.title == listName }) {
            reminder.calendar = calendar
        } else {
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }

        try eventStore.save(reminder, commit: true)

        return reminder
    }

    /// Marks a reminder as completed
    func completeReminder(_ reminder: EKReminder) async throws {
        guard isAuthorized else {
            throw RemindersError.notAuthorized
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()

        try eventStore.save(reminder, commit: true)
    }

    /// Deletes a reminder
    func deleteReminder(_ reminder: EKReminder) async throws {
        guard isAuthorized else {
            throw RemindersError.notAuthorized
        }

        try eventStore.remove(reminder, commit: true)
    }

    // MARK: - Sync with Backend

    /// Syncs all reminders to the Kai backend
    func syncToBackend() async throws -> ReminderSyncResponse {
        guard AuthenticationManager.shared.isAuthenticated else {
            throw RemindersError.notAuthenticated
        }

        isSyncing = true
        defer { isSyncing = false }

        // Fetch all reminders
        let allReminders = await fetchAllReminders()

        // Convert to syncable format
        let syncableReminders = allReminders.map { reminder -> SyncableReminder in
            let dueDate: Date? = reminder.dueDateComponents.flatMap {
                Calendar.current.date(from: $0)
            }

            return SyncableReminder(
                appleReminderId: reminder.calendarItemIdentifier,
                title: reminder.title ?? "Untitled",
                notes: reminder.notes,
                dueDate: dueDate,
                priority: reminder.priority,
                isCompleted: reminder.isCompleted,
                completedAt: reminder.completionDate,
                listName: reminder.calendar?.title,
                tags: nil
            )
        }

        let syncRequest = ReminderSyncRequest(reminders: syncableReminders)

        let response: ReminderSyncResponse = try await APIClient.shared.request(
            .remindersSync,
            method: .post,
            body: syncRequest
        )

        lastSyncDate = Date()

        #if DEBUG
        print("[RemindersManager] Sync complete: \(response.syncedCount) synced, \(response.createdCount) created, \(response.updatedCount) updated")
        #endif

        return response
    }

    /// Syncs reminders in the background (called periodically or on app foreground)
    func syncInBackground() {
        Task {
            do {
                _ = try await syncToBackend()
            } catch {
                #if DEBUG
                print("[RemindersManager] Background sync failed: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Reminders Error

enum RemindersError: LocalizedError {
    case notAuthorized
    case notAuthenticated
    case syncFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Reminders access not authorized. Please enable in Settings."
        case .notAuthenticated:
            return "Not logged in. Please sign in to sync reminders."
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        }
    }
}
