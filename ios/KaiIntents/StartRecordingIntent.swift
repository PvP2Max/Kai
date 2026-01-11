import AppIntents
import SwiftUI
import Foundation

/// Intent to start a meeting recording
/// Opens the app to the recording view
@available(iOS 17.0, *)
struct StartRecordingIntent: AppIntent {

    // MARK: - Intent Metadata

    static var title: LocalizedStringResource = "Start Meeting Recording"

    static var description = IntentDescription(
        "Start recording a meeting with Kai for automatic transcription and summarization",
        categoryName: "Meetings",
        searchKeywords: ["record", "meeting", "transcribe", "audio", "start"]
    )

    // Opens the app to the recording view
    static var openAppWhenRun = true

    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    // MARK: - Parameters

    @Parameter(
        title: "Meeting Title",
        description: "Optional title for the meeting",
        requestValueDialog: IntentDialog("What's the name of this meeting?")
    )
    var meetingTitle: String?

    // MARK: - Initialization

    init() {}

    init(meetingTitle: String?) {
        self.meetingTitle = meetingTitle
    }

    // MARK: - Perform

    func perform() async throws -> some IntentResult & OpensIntent {
        // Create meeting session on the backend
        let client = IntentAPIClient.shared

        do {
            let session = try await client.createMeetingSession(title: meetingTitle)

            // Store the session ID for the app to pick up
            UserDefaults(suiteName: "group.com.arcticauradesigns.kai")?.set(
                session.id,
                forKey: "pendingMeetingSessionId"
            )

            // Return with navigation to open app
            return .result(
                opensIntent: OpenRecordingViewIntent(meetingId: session.id)
            )

        } catch is IntentAPIError {
            // Even if API fails, still open the app to record
            // The app can handle creating the session later
            UserDefaults(suiteName: "group.com.arcticauradesigns.kai")?.set(
                meetingTitle ?? "New Meeting",
                forKey: "pendingMeetingTitle"
            )

            return .result(
                opensIntent: OpenRecordingViewIntent()
            )
        } catch {
            // Open app anyway for recording
            return .result(
                opensIntent: OpenRecordingViewIntent()
            )
        }
    }
}

// MARK: - Open Recording View Intent

/// Helper intent to open the recording view in the app
@available(iOS 17.0, *)
struct OpenRecordingViewIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Recording View"
    static var description = IntentDescription("Opens Kai to the meeting recording view")
    static var openAppWhenRun = true

    @Parameter(title: "Meeting ID")
    var meetingId: String?

    init() {}

    init(meetingId: String? = nil) {
        self.meetingId = meetingId
    }

    func perform() async throws -> some IntentResult {
        // Store navigation intent for app to handle
        if let meetingId = meetingId {
            UserDefaults(suiteName: "group.com.arcticauradesigns.kai")?.set(
                "recording:\(meetingId)",
                forKey: "appNavigationIntent"
            )
        } else {
            UserDefaults(suiteName: "group.com.arcticauradesigns.kai")?.set(
                "recording:new",
                forKey: "appNavigationIntent"
            )
        }

        return .result()
    }
}

// MARK: - Stop Recording Intent

/// Intent to stop an active meeting recording
@available(iOS 17.0, *)
struct StopRecordingIntent: AppIntent {

    static var title: LocalizedStringResource = "Stop Meeting Recording"

    static var description = IntentDescription(
        "Stop the current meeting recording and begin transcription",
        categoryName: "Meetings",
        searchKeywords: ["stop", "end", "finish", "recording", "meeting"]
    )

    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Signal the app to stop recording
        UserDefaults(suiteName: "group.com.arcticauradesigns.kai")?.set(
            true,
            forKey: "stopRecordingIntent"
        )

        return .result(
            dialog: IntentDialog("Stopping the recording. I'll start transcribing your meeting.")
        )
    }
}

// MARK: - Parameter Summary

@available(iOS 17.0, *)
extension StartRecordingIntent {
    static var parameterSummary: some ParameterSummary {
        Summary("Start recording \(\.$meetingTitle)")
    }
}

@available(iOS 17.0, *)
extension StopRecordingIntent {
    static var parameterSummary: some ParameterSummary {
        Summary("Stop meeting recording")
    }
}
