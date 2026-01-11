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
    @State private var name = ""
    @State private var email = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }

            Section {
                Button("Save Changes") {
                    saveChanges()
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveChanges() {
        isSaving = true
        // Save profile changes
        isSaving = false
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
    @State private var useBiometrics = true
    @State private var autoLock = true
    @State private var lockTimeout = 1

    var body: some View {
        Form {
            Section("Authentication") {
                Toggle("Use Face ID / Touch ID", isOn: $useBiometrics)
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
                    Text("Data usage details")
                } label: {
                    Text("Data Usage")
                }
            }
        }
        .navigationTitle("Privacy & Security")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Calendar Integration View

struct CalendarIntegrationView: View {
    @State private var connectedCalendars: [String] = ["iCloud Calendar"]
    @State private var syncEnabled = true

    var body: some View {
        Form {
            Section("Connected Calendars") {
                ForEach(connectedCalendars, id: \.self) { calendar in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(calendar)
                    }
                }

                Button("Add Calendar") {
                    // Add calendar
                }
            }

            Section {
                Toggle("Sync Events", isOn: $syncEnabled)
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
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
    @State private var preferredModel = 0
    @State private var useSmartRouting = true

    var body: some View {
        Form {
            Section {
                Toggle("Smart Model Routing", isOn: $useSmartRouting)
            } footer: {
                Text("Automatically selects the best model based on task complexity.")
            }

            if !useSmartRouting {
                Section("Preferred Model") {
                    Picker("Model", selection: $preferredModel) {
                        Text("Haiku (Fast)").tag(0)
                        Text("Sonnet (Balanced)").tag(1)
                        Text("Opus (Powerful)").tag(2)
                    }
                }
            }
        }
        .navigationTitle("Model Preferences")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("This app uses open source software.")
                    .foregroundColor(.secondary)
            }

            Section("Libraries") {
                Text("SwiftUI")
                Text("Combine")
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthenticationManager.shared)
    }
}
