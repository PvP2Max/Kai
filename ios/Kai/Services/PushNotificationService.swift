//
//  PushNotificationService.swift
//  Kai
//
//  Push notification handling and device registration.
//

import Foundation
import UserNotifications
import UIKit
import Combine

/// Manages push notification permissions, registration, and handling.
@MainActor
final class PushNotificationService: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = PushNotificationService()

    // MARK: - Published Properties

    /// Whether push notifications are currently authorized.
    @Published private(set) var isAuthorized: Bool = false

    /// The current authorization status.
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// The current device token (hex string).
    @Published private(set) var deviceToken: String?

    /// Whether we're currently registering with the backend.
    @Published private(set) var isRegistering: Bool = false

    // MARK: - Notification Types

    /// Types of notifications Kai can send.
    enum NotificationType: String {
        case briefing = "briefing"
        case reminder = "reminder"
        case followUp = "follow_up"
        case meetingStart = "meeting_start"
        case actionRequired = "action_required"
        case chat = "chat"
    }

    /// Notification action identifiers.
    enum NotificationAction: String {
        case reply = "REPLY_ACTION"
        case snooze = "SNOOZE_ACTION"
        case complete = "COMPLETE_ACTION"
        case dismiss = "DISMISS_ACTION"
    }

    /// Notification category identifiers.
    enum NotificationCategory: String {
        case reminder = "REMINDER_CATEGORY"
        case chat = "CHAT_CATEGORY"
        case briefing = "BRIEFING_CATEGORY"
    }

    // MARK: - Private Properties

    private let notificationCenter = UNUserNotificationCenter.current()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Callbacks

    /// Called when a notification is tapped.
    var onNotificationTapped: ((UNNotificationResponse) -> Void)?

    /// Called when a notification is received in foreground.
    var onNotificationReceived: ((UNNotification) -> Void)?

    // MARK: - Initialization

    private override init() {
        super.init()
        notificationCenter.delegate = self
        checkAuthorizationStatus()
    }

    // MARK: - Public Methods

    /// Requests notification permission from the user.
    /// - Returns: Whether permission was granted.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound, .provisional, .criticalAlert]
            let granted = try await notificationCenter.requestAuthorization(options: options)

            await MainActor.run {
                self.isAuthorized = granted
            }

            if granted {
                await registerForRemoteNotifications()
                setupNotificationCategories()
            }

            await checkAuthorizationStatus()

            #if DEBUG
            print("[PushNotificationService] Permission granted: \(granted)")
            #endif

            return granted
        } catch {
            #if DEBUG
            print("[PushNotificationService] Permission request failed: \(error)")
            #endif
            return false
        }
    }

    /// Registers for remote notifications with APNs.
    func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Called when the device token is received from APNs.
    /// - Parameter deviceToken: The raw device token data.
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString

        #if DEBUG
        print("[PushNotificationService] Device token: \(tokenString)")
        #endif

        // Register with backend
        Task {
            await registerDeviceWithBackend(token: tokenString)
        }
    }

    /// Called when remote notification registration fails.
    /// - Parameter error: The registration error.
    func didFailToRegisterForRemoteNotifications(error: Error) {
        #if DEBUG
        print("[PushNotificationService] Failed to register: \(error)")
        #endif
    }

    /// Registers the device token with the Kai backend.
    /// - Parameter token: The hex-encoded device token.
    func registerDeviceWithBackend(token: String) async {
        guard AuthenticationManager.shared.isAuthenticated else {
            #if DEBUG
            print("[PushNotificationService] Not authenticated, skipping device registration")
            #endif
            return
        }

        isRegistering = true

        defer { isRegistering = false }

        do {
            // Backend expects token and device_name as query parameters
            var queryItems = [URLQueryItem(name: "token", value: token)]
            if let deviceName = UIDevice.current.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                queryItems.append(URLQueryItem(name: "device_name", value: deviceName))
            }

            let _: DeviceRegistrationResponse = try await APIClient.shared.request(
                .registerDevice,
                method: .post,
                body: nil as Empty?,
                queryItems: queryItems
            )

            #if DEBUG
            print("[PushNotificationService] Device registered with backend")
            #endif

        } catch {
            #if DEBUG
            print("[PushNotificationService] Failed to register device: \(error)")
            #endif
        }
    }

    /// Unregisters from remote notifications.
    func unregisterForRemoteNotifications() {
        UIApplication.shared.unregisterForRemoteNotifications()
        deviceToken = nil
    }

    /// Clears all delivered notifications.
    func clearAllNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.setBadgeCount(0)
    }

    /// Clears notifications for a specific conversation or item.
    /// - Parameter identifier: The notification identifier prefix.
    func clearNotifications(matching identifier: String) {
        Task { @MainActor in
            let notifications = await notificationCenter.deliveredNotifications()
            let identifiersToRemove = notifications
                .filter { $0.request.identifier.hasPrefix(identifier) }
                .map { $0.request.identifier }

            notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
        }
    }

    /// Schedules a local notification.
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: The notification body.
    ///   - type: The notification type.
    ///   - userInfo: Additional data to include.
    ///   - delay: Delay in seconds before showing (default: 0 = immediate).
    func scheduleLocalNotification(
        title: String,
        body: String,
        type: NotificationType,
        userInfo: [String: Any] = [:],
        delay: TimeInterval = 0
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier(for: type)

        var info = userInfo
        info["type"] = type.rawValue
        content.userInfo = info

        let trigger: UNNotificationTrigger?
        if delay > 0 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        } else {
            trigger = nil
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            #if DEBUG
            print("[PushNotificationService] Local notification scheduled")
            #endif
        } catch {
            #if DEBUG
            print("[PushNotificationService] Failed to schedule notification: \(error)")
            #endif
        }
    }

    // MARK: - Private Methods

    private func checkAuthorizationStatus() {
        Task {
            let settings = await notificationCenter.notificationSettings()
            await MainActor.run {
                self.authorizationStatus = settings.authorizationStatus
                self.isAuthorized = settings.authorizationStatus == .authorized ||
                                   settings.authorizationStatus == .provisional
            }
        }
    }

    private func setupNotificationCategories() {
        // Reminder category with actions
        let completeAction = UNNotificationAction(
            identifier: NotificationAction.complete.rawValue,
            title: "Complete",
            options: .foreground
        )

        let snoozeAction = UNNotificationAction(
            identifier: NotificationAction.snooze.rawValue,
            title: "Snooze 15 min",
            options: []
        )

        let reminderCategory = UNNotificationCategory(
            identifier: NotificationCategory.reminder.rawValue,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        // Chat category with reply action
        let replyAction = UNTextInputNotificationAction(
            identifier: NotificationAction.reply.rawValue,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type your message..."
        )

        let chatCategory = UNNotificationCategory(
            identifier: NotificationCategory.chat.rawValue,
            actions: [replyAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        // Briefing category (no actions, just tap to open)
        let briefingCategory = UNNotificationCategory(
            identifier: NotificationCategory.briefing.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([
            reminderCategory,
            chatCategory,
            briefingCategory
        ])
    }

    private func categoryIdentifier(for type: NotificationType) -> String {
        switch type {
        case .reminder, .meetingStart, .followUp, .actionRequired:
            return NotificationCategory.reminder.rawValue
        case .chat:
            return NotificationCategory.chat.rawValue
        case .briefing:
            return NotificationCategory.briefing.rawValue
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {

    /// Called when a notification is received while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        #if DEBUG
        print("[PushNotificationService] Notification received in foreground: \(userInfo)")
        #endif

        Task { @MainActor in
            self.onNotificationReceived?(notification)
        }

        // Show banner and play sound even when in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Called when the user interacts with a notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        #if DEBUG
        print("[PushNotificationService] Notification tapped: \(actionIdentifier), userInfo: \(userInfo)")
        #endif

        Task { @MainActor in
            await handleNotificationAction(response: response)
            self.onNotificationTapped?(response)
        }

        completionHandler()
    }

    @MainActor
    private func handleNotificationAction(response: UNNotificationResponse) async {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo

        switch actionIdentifier {
        case NotificationAction.reply.rawValue:
            if let textResponse = response as? UNTextInputNotificationResponse {
                let replyText = textResponse.userText
                await handleReplyAction(text: replyText, userInfo: userInfo)
            }

        case NotificationAction.snooze.rawValue:
            await handleSnoozeAction(userInfo: userInfo)

        case NotificationAction.complete.rawValue:
            await handleCompleteAction(userInfo: userInfo)

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            handleDefaultTap(userInfo: userInfo)

        case UNNotificationDismissActionIdentifier:
            // User dismissed the notification
            break

        default:
            break
        }
    }

    @MainActor
    private func handleReplyAction(text: String, userInfo: [AnyHashable: Any]) async {
        guard let conversationId = userInfo["conversation_id"] as? String else {
            // Start a new conversation with the reply
            return
        }

        // Send the reply via API
        do {
            let conversationUUID = UUID(uuidString: conversationId)
            let request = ChatRequest(message: text, conversationId: conversationUUID, source: .ios)
            let _: ChatResponse = try await APIClient.shared.request(.chat, method: .post, body: request)

            #if DEBUG
            print("[PushNotificationService] Reply sent successfully")
            #endif
        } catch {
            #if DEBUG
            print("[PushNotificationService] Failed to send reply: \(error)")
            #endif
        }
    }

    @MainActor
    private func handleSnoozeAction(userInfo: [AnyHashable: Any]) async {
        // Reschedule the notification for 15 minutes later
        let title = userInfo["title"] as? String ?? "Reminder"
        let body = userInfo["body"] as? String ?? ""

        await scheduleLocalNotification(
            title: title,
            body: body,
            type: .reminder,
            userInfo: userInfo as? [String: Any] ?? [:],
            delay: 15 * 60 // 15 minutes
        )
    }

    @MainActor
    private func handleCompleteAction(userInfo: [AnyHashable: Any]) async {
        guard let reminderId = userInfo["reminder_id"] as? String else {
            return
        }

        // Mark the reminder as complete via API
        #if DEBUG
        print("[PushNotificationService] Would mark reminder \(reminderId) as complete")
        #endif

        // TODO: Implement reminder completion API call
    }

    private func handleDefaultTap(userInfo: [AnyHashable: Any]) {
        // Navigate to appropriate screen based on notification type
        guard let typeString = userInfo["type"] as? String,
              let type = NotificationType(rawValue: typeString) else {
            return
        }

        // Post notification for app navigation
        NotificationCenter.default.post(
            name: .didTapPushNotification,
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
    /// Posted when a push notification is tapped.
    static let didTapPushNotification = Notification.Name("didTapPushNotification")

    /// Posted when a push notification is received in foreground.
    static let didReceivePushNotification = Notification.Name("didReceivePushNotification")
}
