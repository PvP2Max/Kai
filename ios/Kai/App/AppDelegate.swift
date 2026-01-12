import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure push notifications
        configureNotifications(application)

        // Sync reminders when user is authenticated
        syncRemindersIfAuthenticated()

        return true
    }

    /// Syncs Apple Reminders to Kai backend if user is authenticated and has reminders access
    private func syncRemindersIfAuthenticated() {
        Task { @MainActor in
            // Wait a bit for auth state to stabilize
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            guard AuthenticationManager.shared.isAuthenticated else {
                #if DEBUG
                print("[AppDelegate] Skipping reminders sync - not authenticated")
                #endif
                return
            }

            let remindersManager = RemindersManager.shared

            // Check if we have reminders access
            remindersManager.checkAuthorizationStatus()

            guard remindersManager.isAuthorized else {
                #if DEBUG
                print("[AppDelegate] Skipping reminders sync - not authorized")
                #endif
                return
            }

            // Sync reminders to backend
            do {
                let result = try await remindersManager.syncToBackend()
                #if DEBUG
                print("[AppDelegate] Reminders synced: \(result.syncedCount) total, \(result.createdCount) new")
                #endif
            } catch {
                #if DEBUG
                print("[AppDelegate] Reminders sync failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - Push Notification Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Convert token to string
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("Successfully registered for remote notifications with token: \(tokenString)")

        // Store the device token and send to backend
        Task { @MainActor in
            PushNotificationService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")

        // Notify the app that registration failed
        NotificationCenter.default.post(
            name: .pushNotificationRegistrationFailed,
            object: nil,
            userInfo: ["error": error]
        )
    }

    // MARK: - Handle Incoming Notifications

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle silent push notifications for background updates
        handleRemoteNotification(userInfo: userInfo) { result in
            completionHandler(result)
        }
    }

    // MARK: - Private Methods

    private func configureNotifications(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
                return
            }

            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
    }

    private func handleRemoteNotification(
        userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Parse notification type
        guard let notificationType = userInfo["type"] as? String else {
            completion(.noData)
            return
        }

        switch notificationType {
        case "calendar_reminder":
            handleCalendarReminder(userInfo: userInfo, completion: completion)
        case "meeting_summary":
            handleMeetingSummary(userInfo: userInfo, completion: completion)
        case "briefing":
            handleBriefing(userInfo: userInfo, completion: completion)
        case "task_reminder":
            handleTaskReminder(userInfo: userInfo, completion: completion)
        default:
            completion(.noData)
        }
    }

    private func handleCalendarReminder(
        userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Process calendar reminder notification
        NotificationCenter.default.post(
            name: .calendarReminderReceived,
            object: nil,
            userInfo: userInfo
        )
        completion(.newData)
    }

    private func handleMeetingSummary(
        userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Process meeting summary notification
        NotificationCenter.default.post(
            name: .meetingSummaryReceived,
            object: nil,
            userInfo: userInfo
        )
        completion(.newData)
    }

    private func handleBriefing(
        userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Process briefing notification
        NotificationCenter.default.post(
            name: .briefingReceived,
            object: nil,
            userInfo: userInfo
        )
        completion(.newData)
    }

    private func handleTaskReminder(
        userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Process task reminder notification
        NotificationCenter.default.post(
            name: .taskReminderReceived,
            object: nil,
            userInfo: userInfo
        )
        completion(.newData)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    // Handle notifications when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .badge, .sound])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Handle notification tap based on type
        if let notificationType = userInfo["type"] as? String {
            handleNotificationTap(type: notificationType, userInfo: userInfo)
        }

        completionHandler()
    }

    private func handleNotificationTap(type: String, userInfo: [AnyHashable: Any]) {
        // Post notification to navigate to appropriate screen
        NotificationCenter.default.post(
            name: .notificationTapped,
            object: nil,
            userInfo: [
                "type": type,
                "data": userInfo
            ]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pushNotificationRegistrationFailed = Notification.Name("pushNotificationRegistrationFailed")
    static let calendarReminderReceived = Notification.Name("calendarReminderReceived")
    static let meetingSummaryReceived = Notification.Name("meetingSummaryReceived")
    static let briefingReceived = Notification.Name("briefingReceived")
    static let taskReminderReceived = Notification.Name("taskReminderReceived")
    static let notificationTapped = Notification.Name("notificationTapped")
}
