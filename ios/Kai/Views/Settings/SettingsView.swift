import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            // Account Section
            Section("Account") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.userName)
                            .font(.headline)
                        Text(viewModel.userEmail)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)

                NavigationLink {
                    ProfileSettingsView()
                } label: {
                    Label("Edit Profile", systemImage: "pencil")
                }
            }

            // Preferences Section
            Section("Preferences") {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notifications", systemImage: "bell")
                }

                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "paintbrush")
                }

                NavigationLink {
                    PrivacySettingsView()
                } label: {
                    Label("Privacy & Security", systemImage: "lock")
                }
            }

            // Integrations Section
            Section("Integrations") {
                NavigationLink {
                    CalendarIntegrationView()
                } label: {
                    Label("Calendar", systemImage: "calendar")
                }

                NavigationLink {
                    SiriIntegrationView()
                } label: {
                    Label("Siri", systemImage: "waveform")
                }
            }

            // AI Settings Section
            Section("AI Settings") {
                NavigationLink {
                    ModelPreferencesView()
                } label: {
                    Label("Model Preferences", systemImage: "cpu")
                }

                NavigationLink {
                    LearningPreferencesView()
                } label: {
                    Label("Learning & Personalization", systemImage: "brain")
                }
            }

            // Data Section
            Section("Data") {
                NavigationLink {
                    DataExportView()
                } label: {
                    Label("Export Data", systemImage: "arrow.down.doc")
                }

                Button(role: .destructive) {
                    viewModel.showDeleteDataAlert = true
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }

            // About Section
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.appVersion)
                        .foregroundColor(.secondary)
                }

                NavigationLink {
                    LicensesView()
                } label: {
                    Text("Open Source Licenses")
                }

                Link(destination: URL(string: "https://kai.app/privacy")!) {
                    HStack {
                        Text("Privacy Policy")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Link(destination: URL(string: "https://kai.app/terms")!) {
                    HStack {
                        Text("Terms of Service")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            await viewModel.refresh()
        }
        .alert("Delete All Data", isPresented: $viewModel.showDeleteDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteAllData()
                }
            }
        } message: {
            Text("This will permanently delete all your data including conversations, notes, and preferences. This action cannot be undone.")
        }
    }
}

// MARK: - Profile Settings View

struct ProfileSettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var name = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false

    private let commonTimezones = [
        "America/New_York",
        "America/Chicago",
        "America/Denver",
        "America/Los_Angeles",
        "America/Phoenix",
        "Europe/London",
        "Europe/Paris",
        "Asia/Tokyo",
        "Asia/Shanghai",
        "Australia/Sydney",
        "Pacific/Honolulu"
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)

                Picker("Timezone", selection: $timezone) {
                    ForEach(commonTimezones, id: \.self) { tz in
                        Text(formatTimezone(tz)).tag(tz)
                    }
                }
            }

            Section {
                HStack {
                    Text("Email")
                    Spacer()
                    Text(authManager.currentUser?.email ?? "")
                        .foregroundColor(.secondary)
                }
            } footer: {
                Text("Email cannot be changed.")
            }

            Section {
                Button {
                    Task {
                        await saveChanges()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Save Changes")
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving || name.isEmpty)
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let user = authManager.currentUser {
                name = user.name
                timezone = user.timezone
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Profile updated successfully.")
        }
    }

    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let request = UserUpdateRequest(name: name, timezone: timezone)
            let _: User = try await APIClient.shared.request(
                .me,
                method: .put,
                body: request
            )
            try await authManager.refreshUser()
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func formatTimezone(_ identifier: String) -> String {
        guard let tz = TimeZone(identifier: identifier) else { return identifier }
        let offset = tz.secondsFromGMT() / 3600
        let sign = offset >= 0 ? "+" : ""
        let city = identifier.components(separatedBy: "/").last?.replacingOccurrences(of: "_", with: " ") ?? identifier
        return "\(city) (GMT\(sign)\(offset))"
    }
}

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
    @State private var enablePush = true
    @State private var dailyBriefing = true
    @State private var meetingReminders = true
    @State private var taskReminders = true
    @State private var briefingTime = Date()

    var body: some View {
        Form {
            Section {
                Toggle("Push Notifications", isOn: $enablePush)
            }

            Section("Daily Briefing") {
                Toggle("Enable Daily Briefing", isOn: $dailyBriefing)

                if dailyBriefing {
                    DatePicker("Briefing Time", selection: $briefingTime, displayedComponents: .hourAndMinute)
                }
            }

            Section("Reminders") {
                Toggle("Meeting Reminders", isOn: $meetingReminders)
                Toggle("Task Reminders", isOn: $taskReminders)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Appearance Settings View

struct AppearanceSettingsView: View {
    @State private var selectedTheme = 0
    @State private var useDynamicType = true

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $selectedTheme) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.segmented)
            }

            Section("Text") {
                Toggle("Use Dynamic Type", isOn: $useDynamicType)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy Settings View

struct PrivacySettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var autoLock = true
    @State private var lockTimeout = 1

    var body: some View {
        Form {
            Section("Authentication") {
                Toggle(biometricLabel, isOn: Binding(
                    get: { authManager.requiresBiometric },
                    set: { authManager.setBiometricEnabled($0) }
                ))
                .disabled(authManager.biometricType == .none)

                if authManager.biometricType == .none {
                    Text("Biometric authentication is not available on this device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle("Auto-Lock", isOn: $autoLock)

                if autoLock {
                    Picker("Lock After", selection: $lockTimeout) {
                        Text("Immediately").tag(0)
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                    }
                }
            }

            Section("Data") {
                NavigationLink {
                    DataUsageView()
                } label: {
                    Text("Data Usage")
                }
            }
        }
        .navigationTitle("Privacy & Security")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var biometricLabel: String {
        switch authManager.biometricType {
        case .faceID:
            return "Use Face ID"
        case .touchID:
            return "Use Touch ID"
        default:
            return "Use Biometrics"
        }
    }
}

// MARK: - Calendar Integration View

struct CalendarIntegrationView: View {
    @StateObject private var viewModel = CalendarIntegrationViewModel()
    @State private var showCalendarPicker = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    switch viewModel.authorizationStatus {
                    case .fullAccess, .writeOnly:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .denied, .restricted:
                        Label("Denied", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    default:
                        Label("Not Connected", systemImage: "circle")
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.authorizationStatus == .notDetermined {
                    Button("Connect Apple Calendar") {
                        Task { await viewModel.requestAccess() }
                    }
                }

                if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            if viewModel.isAuthorized {
                Section("Selected Calendars") {
                    if viewModel.selectedCalendars.isEmpty {
                        Text("No calendars selected")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.selectedCalendars, id: \.calendarIdentifier) { calendar in
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor))
                                    .frame(width: 12, height: 12)
                                Text(calendar.title)
                            }
                        }
                    }

                    Button("Select Calendars") {
                        showCalendarPicker = true
                    }
                }

                Section {
                    Toggle("Sync to Backend", isOn: $viewModel.syncEnabled)
                        .onChange(of: viewModel.syncEnabled) { _, _ in
                            viewModel.saveSyncPreference()
                        }
                } footer: {
                    Text("When enabled, calendar events sync with Kai for briefings and scheduling.")
                }
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.checkAuthorizationStatus()
        }
        .sheet(isPresented: $showCalendarPicker) {
            CalendarPickerView(viewModel: viewModel)
        }
    }
}

// MARK: - Calendar Picker View

struct CalendarPickerView: View {
    @ObservedObject var viewModel: CalendarIntegrationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.availableCalendars, id: \.calendarIdentifier) { calendar in
                    Button {
                        viewModel.toggleCalendar(calendar)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 12, height: 12)

                            Text(calendar.title)
                                .foregroundColor(.primary)

                            Spacer()

                            if viewModel.isCalendarSelected(calendar) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Calendar Integration View Model

import EventKit

@MainActor
class CalendarIntegrationViewModel: ObservableObject {
    @Published var isAuthorized = false
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var availableCalendars: [EKCalendar] = []
    @Published var selectedCalendarIds: Set<String> = []
    @Published var syncEnabled = true

    private let eventStore = EKEventStore()
    private let selectedCalendarsKey = "kai_selected_calendar_ids"
    private let syncEnabledKey = "kai_calendar_sync_enabled"

    var selectedCalendars: [EKCalendar] {
        availableCalendars.filter { selectedCalendarIds.contains($0.calendarIdentifier) }
    }

    init() {
        loadSavedPreferences()
        checkAuthorizationStatus()
    }

    func checkAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            isAuthorized = authorizationStatus == .fullAccess
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            isAuthorized = authorizationStatus == .authorized
        }

        if isAuthorized {
            loadCalendars()
        }
    }

    func requestAccess() async {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                isAuthorized = granted
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                isAuthorized = granted
            }
            checkAuthorizationStatus()
        } catch {
            #if DEBUG
            print("[CalendarIntegrationViewModel] Failed to request access: \(error)")
            #endif
        }
    }

    func loadCalendars() {
        availableCalendars = eventStore.calendars(for: .event)
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        // If no calendars selected, select all by default
        if selectedCalendarIds.isEmpty {
            selectedCalendarIds = Set(availableCalendars.map { $0.calendarIdentifier })
            saveSelectedCalendars()
        }
    }

    func toggleCalendar(_ calendar: EKCalendar) {
        if selectedCalendarIds.contains(calendar.calendarIdentifier) {
            selectedCalendarIds.remove(calendar.calendarIdentifier)
        } else {
            selectedCalendarIds.insert(calendar.calendarIdentifier)
        }
        saveSelectedCalendars()
    }

    func isCalendarSelected(_ calendar: EKCalendar) -> Bool {
        selectedCalendarIds.contains(calendar.calendarIdentifier)
    }

    private func loadSavedPreferences() {
        if let savedIds = UserDefaults.standard.stringArray(forKey: selectedCalendarsKey) {
            selectedCalendarIds = Set(savedIds)
        }
        syncEnabled = UserDefaults.standard.bool(forKey: syncEnabledKey)
        if UserDefaults.standard.object(forKey: syncEnabledKey) == nil {
            syncEnabled = true  // Default to true
        }
    }

    private func saveSelectedCalendars() {
        UserDefaults.standard.set(Array(selectedCalendarIds), forKey: selectedCalendarsKey)
    }

    func saveSyncPreference() {
        UserDefaults.standard.set(syncEnabled, forKey: syncEnabledKey)
    }
}

// MARK: - Siri Integration View

struct SiriIntegrationView: View {
    @State private var siriEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable Siri Shortcuts", isOn: $siriEnabled)
            }

            Section("Available Shortcuts") {
                Text("\"Hey Siri, what's on my calendar?\"")
                    .foregroundColor(.secondary)
                Text("\"Hey Siri, create a note\"")
                    .foregroundColor(.secondary)
                Text("\"Hey Siri, start recording meeting\"")
                    .foregroundColor(.secondary)
            }

            Section {
                Button("Add Siri Shortcut") {
                    // Add shortcut
                }
            }
        }
        .navigationTitle("Siri")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Model Preferences View

struct ModelPreferencesView: View {
    @StateObject private var viewModel = ModelPreferencesViewModel()

    var body: some View {
        Form {
            if viewModel.isLoading && !viewModel.hasLoaded {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else {
                Section {
                    Toggle("Smart Model Routing", isOn: $viewModel.useSmartRouting)
                        .onChange(of: viewModel.useSmartRouting) { _, _ in
                            Task { await viewModel.saveSettings() }
                        }
                } footer: {
                    Text("Automatically selects the best model based on task complexity.")
                }

                if !viewModel.useSmartRouting {
                    Section("Preferred Model") {
                        Picker("Model", selection: $viewModel.preferredModel) {
                            Text("Haiku (Fast)").tag("haiku")
                            Text("Sonnet (Balanced)").tag("sonnet")
                            Text("Opus (Powerful)").tag("opus")
                        }
                        .onChange(of: viewModel.preferredModel) { _, _ in
                            Task { await viewModel.saveSettings() }
                        }
                    }
                }

                Section {
                    Toggle("Prefer Speed", isOn: $viewModel.preferSpeed)
                        .onChange(of: viewModel.preferSpeed) { _, newValue in
                            if newValue { viewModel.preferQuality = false }
                            Task { await viewModel.saveSettings() }
                        }

                    Toggle("Prefer Quality", isOn: $viewModel.preferQuality)
                        .onChange(of: viewModel.preferQuality) { _, newValue in
                            if newValue { viewModel.preferSpeed = false }
                            Task { await viewModel.saveSettings() }
                        }
                } footer: {
                    Text("Influences model selection when smart routing is enabled.")
                }
            }

            if let error = viewModel.error {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Model Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadSettings()
        }
    }
}

// MARK: - Model Preferences View Model

@MainActor
class ModelPreferencesViewModel: ObservableObject {
    @Published var useSmartRouting = true
    @Published var preferredModel = "sonnet"
    @Published var preferSpeed = false
    @Published var preferQuality = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasLoaded = false

    func loadSettings() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let settings: RoutingSettingsResponse = try await APIClient.shared.request(
                .routingConfig,
                method: .get
            )
            useSmartRouting = settings.enableChaining
            preferredModel = settings.defaultModel
            preferSpeed = settings.preferSpeed
            preferQuality = settings.preferQuality
            hasLoaded = true
        } catch {
            self.error = error.localizedDescription
            hasLoaded = true
            #if DEBUG
            print("[ModelPreferencesViewModel] Failed to load settings: \(error)")
            #endif
        }
    }

    func saveSettings() async {
        guard hasLoaded else { return }

        do {
            let request = RoutingSettingsUpdate(
                defaultModel: useSmartRouting ? nil : preferredModel,
                enableChaining: useSmartRouting,
                preferSpeed: preferSpeed,
                preferQuality: preferQuality
            )
            let _: RoutingSettingsResponse = try await APIClient.shared.request(
                .routingConfig,
                method: .put,
                body: request
            )
            error = nil
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
            #if DEBUG
            print("[ModelPreferencesViewModel] Failed to save settings: \(error)")
            #endif
        }
    }
}

// MARK: - Routing Settings Models

struct RoutingSettingsResponse: Codable {
    let defaultModel: String
    let enableChaining: Bool
    let preferSpeed: Bool
    let preferQuality: Bool

    enum CodingKeys: String, CodingKey {
        case defaultModel = "default_model"
        case enableChaining = "enable_chaining"
        case preferSpeed = "prefer_speed"
        case preferQuality = "prefer_quality"
    }
}

struct RoutingSettingsUpdate: Codable {
    let defaultModel: String?
    let enableChaining: Bool?
    let preferSpeed: Bool?
    let preferQuality: Bool?

    enum CodingKeys: String, CodingKey {
        case defaultModel = "default_model"
        case enableChaining = "enable_chaining"
        case preferSpeed = "prefer_speed"
        case preferQuality = "prefer_quality"
    }
}

// MARK: - Learning Preferences View

struct LearningPreferencesView: View {
    @State private var enableLearning = true
    @State private var learnSchedulingPreferences = true
    @State private var learnCommunicationStyle = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable Personalization", isOn: $enableLearning)
            } footer: {
                Text("Allow Kai to learn from your interactions to provide better suggestions.")
            }

            if enableLearning {
                Section("What Kai Learns") {
                    Toggle("Scheduling Preferences", isOn: $learnSchedulingPreferences)
                    Toggle("Communication Style", isOn: $learnCommunicationStyle)
                }

                Section {
                    Button("Reset Learning Data") {
                        // Reset learning
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Learning")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data Export View

struct DataExportView: View {
    @State private var isExporting = false

    var body: some View {
        Form {
            Section {
                Button {
                    exportData()
                } label: {
                    HStack {
                        Text("Export All Data")
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting)
            } footer: {
                Text("Export all your data including conversations, notes, meetings, and preferences as a JSON file.")
            }
        }
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func exportData() {
        isExporting = true
        // Export data
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isExporting = false
        }
    }
}

// MARK: - Licenses View

struct LicensesView: View {
    var body: some View {
        List {
            Section {
                Text("Kai uses the following frameworks and services.")
                    .foregroundColor(.secondary)
            }

            Section("Apple Frameworks") {
                LicenseRow(
                    name: "EventKit",
                    description: "Calendar and reminders access"
                )
                LicenseRow(
                    name: "LocalAuthentication",
                    description: "Face ID and Touch ID"
                )
                LicenseRow(
                    name: "Speech",
                    description: "Speech recognition"
                )
                LicenseRow(
                    name: "AVFoundation",
                    description: "Audio recording and playback"
                )
                LicenseRow(
                    name: "UserNotifications",
                    description: "Push notifications"
                )
            }

            Section("AI Services") {
                LicenseRow(
                    name: "Anthropic Claude API",
                    description: "AI assistant capabilities",
                    url: "https://www.anthropic.com"
                )
            }

            Section("Backend") {
                LicenseRow(
                    name: "FastAPI",
                    description: "Python web framework",
                    license: "MIT License"
                )
                LicenseRow(
                    name: "SQLAlchemy",
                    description: "Database ORM",
                    license: "MIT License"
                )
                LicenseRow(
                    name: "OpenAI Whisper",
                    description: "Speech transcription",
                    license: "MIT License"
                )
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicenseRow: View {
    let name: String
    let description: String
    var license: String? = nil
    var url: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let license = license {
                    Text(license)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            if let urlString = url, let link = URL(string: urlString) {
                Link(urlString, destination: link)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthenticationManager.shared)
    }
}
