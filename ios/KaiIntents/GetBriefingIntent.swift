import AppIntents
import SwiftUI
import Foundation

/// Quick briefing intent for getting a daily summary
/// Returns a spoken summary of weather, calendar, and tasks
@available(iOS 17.0, *)
struct GetBriefingIntent: AppIntent {

    // MARK: - Intent Metadata

    static var title: LocalizedStringResource = "Get Daily Briefing"

    static var description = IntentDescription(
        "Get your personalized daily briefing from Kai including weather, calendar events, and tasks",
        categoryName: "Briefing",
        searchKeywords: ["briefing", "summary", "daily", "morning", "schedule", "today"]
    )

    static var openAppWhenRun = false

    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    // MARK: - Parameters

    @Parameter(
        title: "Include Weather",
        description: "Include weather information in the briefing",
        default: true
    )
    var includeWeather: Bool

    @Parameter(
        title: "Include Tasks",
        description: "Include pending tasks in the briefing",
        default: true
    )
    var includeTasks: Bool

    // MARK: - Initialization

    init() {}

    init(includeWeather: Bool = true, includeTasks: Bool = true) {
        self.includeWeather = includeWeather
        self.includeTasks = includeTasks
    }

    // MARK: - Perform

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = IntentAPIClient.shared

        do {
            let briefing = try await client.getDailyBriefing()

            // Build spoken summary
            let spokenSummary = buildSpokenSummary(from: briefing)

            return .result(dialog: IntentDialog(stringLiteral: spokenSummary))

        } catch let error as IntentAPIError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: IntentDialog("Sorry, I couldn't fetch your briefing right now."))
        }
    }

    // MARK: - Summary Builder

    private func buildSpokenSummary(from briefing: BriefingResponse) -> String {
        var parts: [String] = []

        // Greeting
        parts.append(briefing.greeting)

        // Weather
        if includeWeather, let weather = briefing.weather {
            let temp = Int(weather.temperature)
            var weatherText = "It's currently \(temp) degrees and \(weather.condition)."

            if let high = weather.high, let low = weather.low {
                weatherText += " Today's high is \(Int(high)) with a low of \(Int(low))."
            }

            parts.append(weatherText)
        }

        // Calendar events
        if !briefing.upcomingEvents.isEmpty {
            let eventCount = briefing.upcomingEvents.count
            if eventCount == 1 {
                let event = briefing.upcomingEvents[0]
                parts.append("You have one event: \(event.title) at \(formatTime(event.startTime)).")
            } else {
                parts.append("You have \(eventCount) events today.")

                // Mention first 3 events
                let eventsToMention = Array(briefing.upcomingEvents.prefix(3))
                for event in eventsToMention {
                    parts.append("\(event.title) at \(formatTime(event.startTime)).")
                }

                if eventCount > 3 {
                    parts.append("And \(eventCount - 3) more.")
                }
            }
        } else {
            parts.append("Your calendar is clear today.")
        }

        // Tasks
        if includeTasks && !briefing.tasks.isEmpty {
            let taskCount = briefing.tasks.count
            if taskCount == 1 {
                parts.append("You have one task: \(briefing.tasks[0].title).")
            } else {
                let highPriorityTasks = briefing.tasks.filter { $0.priority?.lowercased() == "high" }
                if !highPriorityTasks.isEmpty {
                    parts.append("You have \(taskCount) tasks, \(highPriorityTasks.count) marked as high priority.")
                } else {
                    parts.append("You have \(taskCount) tasks to complete.")
                }
            }
        }

        // Unread emails
        if let emailCount = briefing.unreadEmailCount, emailCount > 0 {
            if emailCount == 1 {
                parts.append("You have 1 unread email.")
            } else {
                parts.append("You have \(emailCount) unread emails.")
            }
        }

        return parts.joined(separator: " ")
    }

    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: isoString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else {
                return isoString
            }
            return formatTimeOnly(date)
        }

        return formatTimeOnly(date)
    }

    private func formatTimeOnly(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        return timeFormatter.string(from: date)
    }
}

// MARK: - Parameter Summary

@available(iOS 17.0, *)
extension GetBriefingIntent {
    static var parameterSummary: some ParameterSummary {
        Summary("Get daily briefing") {
            \.$includeWeather
            \.$includeTasks
        }
    }
}
