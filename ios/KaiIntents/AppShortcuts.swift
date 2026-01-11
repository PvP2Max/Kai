import AppIntents

/// App Shortcuts configuration for Kai
/// Defines Siri phrases and shortcuts for quick access to Kai features
@available(iOS 17.0, *)
struct KaiAppShortcuts: AppShortcutsProvider {

    // MARK: - App Shortcuts

    static var appShortcuts: [AppShortcut] {
        // Ask Kai - Main conversational shortcut
        AppShortcut(
            intent: AskKaiIntent(),
            phrases: [
                "Ask \(.applicationName) something",
                "Hey \(.applicationName)",
                "Talk to \(.applicationName)",
                "Ask \(.applicationName)"
            ],
            shortTitle: "Ask Kai",
            systemImageName: "brain.head.profile"
        )

        // Daily Briefing
        AppShortcut(
            intent: GetBriefingIntent(),
            phrases: [
                "Get my \(.applicationName) briefing",
                "Good morning \(.applicationName)",
                "What's my day look like \(.applicationName)",
                "\(.applicationName) daily briefing",
                "\(.applicationName) what's on today",
                "Brief me \(.applicationName)",
                "What do I have today \(.applicationName)"
            ],
            shortTitle: "Daily Briefing",
            systemImageName: "sun.max"
        )

        // Start Recording
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording with \(.applicationName)",
                "\(.applicationName) record meeting",
                "\(.applicationName) start recording",
                "Record this meeting \(.applicationName)"
            ],
            shortTitle: "Record Meeting",
            systemImageName: "mic.circle"
        )

        // Quick Schedule Check
        AppShortcut(
            intent: CheckScheduleIntent(),
            phrases: [
                "What's next \(.applicationName)",
                "\(.applicationName) what's my next meeting",
                "\(.applicationName) check my schedule",
                "When is my next event \(.applicationName)",
                "\(.applicationName) what's coming up"
            ],
            shortTitle: "Check Schedule",
            systemImageName: "calendar"
        )

        // Quick Task Check
        AppShortcut(
            intent: CheckTasksIntent(),
            phrases: [
                "\(.applicationName) what are my tasks",
                "What do I need to do \(.applicationName)",
                "\(.applicationName) show my tasks",
                "My todos \(.applicationName)"
            ],
            shortTitle: "Check Tasks",
            systemImageName: "checkmark.circle"
        )

        // Create Event
        AppShortcut(
            intent: CreateEventIntent(),
            phrases: [
                "\(.applicationName) create an event",
                "Schedule something with \(.applicationName)",
                "\(.applicationName) add to calendar",
                "Create meeting with \(.applicationName)"
            ],
            shortTitle: "Create Event",
            systemImageName: "calendar.badge.plus"
        )
    }
}

// MARK: - Additional Quick Intents

/// Quick schedule check intent
@available(iOS 17.0, *)
struct CheckScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Schedule"
    static var description = IntentDescription("Check your upcoming schedule")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Use the chat endpoint with a schedule query
        let client = IntentAPIClient.shared

        do {
            let response = try await client.sendChatMessage(
                message: "What's on my schedule for today?",
                conversationId: nil
            )

            return .result(dialog: IntentDialog(stringLiteral: response.response))
        } catch {
            return .result(dialog: IntentDialog("Sorry, I couldn't check your schedule right now."))
        }
    }
}

/// Quick task check intent
@available(iOS 17.0, *)
struct CheckTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Tasks"
    static var description = IntentDescription("Check your pending tasks")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = IntentAPIClient.shared

        do {
            let response = try await client.sendChatMessage(
                message: "What tasks do I have pending?",
                conversationId: nil
            )

            return .result(dialog: IntentDialog(stringLiteral: response.response))
        } catch {
            return .result(dialog: IntentDialog("Sorry, I couldn't check your tasks right now."))
        }
    }
}
