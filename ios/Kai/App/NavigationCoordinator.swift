//
//  NavigationCoordinator.swift
//  Kai
//
//  Handles navigation from Siri intents and deep links.
//

import SwiftUI
import EventKit

/// Coordinates navigation from Siri intents and deep links
@MainActor
class NavigationCoordinator: ObservableObject {
    static let shared = NavigationCoordinator()

    // MARK: - Published Properties

    /// Current tab selection
    @Published var selectedTab: MainTab = .chat

    /// Whether to show the recording view
    @Published var showRecordingView = false

    /// Pending meeting session ID from Siri
    @Published var pendingMeetingId: String?

    /// Pending meeting title from Siri (or from calendar)
    @Published var pendingMeetingTitle: String?

    /// Whether recording should auto-start
    @Published var shouldAutoStartRecording = false

    // MARK: - Private Properties

    private let userDefaults = UserDefaults(suiteName: "group.com.arcticauradesigns.kai")
    private let eventStore = EKEventStore()

    // MARK: - Initialization

    private init() {}

    // MARK: - Navigation Intent Handling

    /// Check for pending navigation from Siri intents
    func checkForPendingNavigation() {
        guard let defaults = userDefaults else { return }

        // Check for recording intent
        if let navigationIntent = defaults.string(forKey: "appNavigationIntent") {
            handleNavigationIntent(navigationIntent)
            defaults.removeObject(forKey: "appNavigationIntent")
        }

        // Check for pending meeting session
        if let sessionId = defaults.string(forKey: "pendingMeetingSessionId") {
            pendingMeetingId = sessionId
            defaults.removeObject(forKey: "pendingMeetingSessionId")
            navigateToRecording()
        }

        // Check for pending meeting title
        if let title = defaults.string(forKey: "pendingMeetingTitle") {
            pendingMeetingTitle = title
            defaults.removeObject(forKey: "pendingMeetingTitle")
            navigateToRecording()
        }

        // Check for stop recording intent
        if defaults.bool(forKey: "stopRecordingIntent") {
            defaults.removeObject(forKey: "stopRecordingIntent")
            NotificationCenter.default.post(name: .stopRecordingRequested, object: nil)
        }
    }

    /// Handle a navigation intent string
    private func handleNavigationIntent(_ intent: String) {
        if intent.hasPrefix("recording:") {
            let components = intent.split(separator: ":")
            if components.count > 1 {
                let idOrNew = String(components[1])
                if idOrNew == "new" {
                    // New recording without ID - check calendar for current event
                    Task {
                        await checkCalendarForMeetingTitle()
                        navigateToRecording()
                    }
                } else {
                    pendingMeetingId = idOrNew
                    navigateToRecording()
                }
            }
        }
    }

    /// Navigate to the recording view
    func navigateToRecording() {
        // Switch to the appropriate tab (assuming meetings tab)
        selectedTab = .meetings
        showRecordingView = true
        shouldAutoStartRecording = true
    }

    /// Check the calendar for a current or upcoming event to use as meeting title
    func checkCalendarForMeetingTitle() async {
        // Only check if we don't already have a title
        guard pendingMeetingTitle == nil else { return }

        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else { return }

        let now = Date()
        let calendar = Calendar.current

        // Look for events in the current hour
        guard let startOfHour = calendar.date(bySetting: .minute, value: 0, of: now),
              let endOfHour = calendar.date(byAdding: .hour, value: 1, to: startOfHour) else {
            return
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startOfHour,
            end: endOfHour,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)

        // Find an event that's happening now or starting soon
        for event in events {
            // Skip all-day events
            if event.isAllDay { continue }

            // Check if event is currently happening or starting within 15 minutes
            let eventStart = event.startDate!
            let eventEnd = event.endDate!

            if now >= eventStart && now <= eventEnd {
                // Currently in this meeting
                pendingMeetingTitle = event.title
                #if DEBUG
                print("[NavigationCoordinator] Using current event title: \(event.title ?? "Untitled")")
                #endif
                return
            } else if eventStart > now && eventStart.timeIntervalSince(now) < 900 {
                // Event starting within 15 minutes
                pendingMeetingTitle = event.title
                #if DEBUG
                print("[NavigationCoordinator] Using upcoming event title: \(event.title ?? "Untitled")")
                #endif
                return
            }
        }

        #if DEBUG
        print("[NavigationCoordinator] No matching calendar event found")
        #endif
    }

    /// Reset navigation state after handling
    func resetNavigationState() {
        pendingMeetingId = nil
        pendingMeetingTitle = nil
        showRecordingView = false
        shouldAutoStartRecording = false
    }
}

// MARK: - Tab Enum

enum MainTab: Hashable {
    case chat
    case calendar
    case meetings
    case more
}

// MARK: - Notification Names

extension Notification.Name {
    static let stopRecordingRequested = Notification.Name("stopRecordingRequested")
}
