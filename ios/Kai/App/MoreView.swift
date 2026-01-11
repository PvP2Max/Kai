import SwiftUI

struct MoreView: View {
    @EnvironmentObject var authManager: AuthenticationManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        NotesListView()
                    } label: {
                        MoreRowView(
                            icon: "note.text",
                            iconColor: .orange,
                            title: "Notes",
                            subtitle: "View and create notes"
                        )
                    }

                    NavigationLink {
                        BriefingsView()
                    } label: {
                        MoreRowView(
                            icon: "doc.text.fill",
                            iconColor: .purple,
                            title: "Briefings",
                            subtitle: "Daily summaries and updates"
                        )
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        MoreRowView(
                            icon: "gearshape.fill",
                            iconColor: .gray,
                            title: "Settings",
                            subtitle: "Preferences and account"
                        )
                    }
                }

                Section("Integrations") {
                    NavigationLink {
                        EmailAccountsView()
                    } label: {
                        MoreRowView(
                            icon: "envelope.fill",
                            iconColor: .blue,
                            title: "Email Accounts",
                            subtitle: "Manage connected email accounts"
                        )
                    }

                    NavigationLink {
                        RemindersSettingsView()
                    } label: {
                        MoreRowView(
                            icon: "checklist",
                            iconColor: .orange,
                            title: "Reminders",
                            subtitle: "Apple Reminders sync settings"
                        )
                    }
                }

                Section {
                    NavigationLink {
                        ActivityLogView()
                    } label: {
                        MoreRowView(
                            icon: "clock.arrow.circlepath",
                            iconColor: .blue,
                            title: "Activity Log",
                            subtitle: "Recent actions and history"
                        )
                    }

                    NavigationLink {
                        HelpView()
                    } label: {
                        MoreRowView(
                            icon: "questionmark.circle.fill",
                            iconColor: .green,
                            title: "Help & Support",
                            subtitle: "FAQs and contact support"
                        )
                    }
                }

                Section {
                    Button(action: signOut) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                                .frame(width: 28)

                            Text("Sign Out")
                                .foregroundColor(.red)

                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("More")
            .listStyle(.insetGrouped)
        }
    }

    private func signOut() {
        authManager.logout()
    }
}

// MARK: - More Row View

struct MoreRowView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Activity Log View

struct ActivityLogView: View {
    @StateObject private var viewModel = ActivityLogViewModel()
    @State private var showUndoError = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.activities.isEmpty {
                ProgressView("Loading activity...")
            } else if let error = viewModel.error, viewModel.activities.isEmpty {
                ContentUnavailableView {
                    Label("Unable to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.loadActivities() }
                    }
                }
            } else if viewModel.activities.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Your actions in Kai will appear here.")
                )
            } else {
                activityList
            }
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadActivities()
        }
        .alert("Undo Failed", isPresented: $showUndoError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.undoError ?? "An error occurred while undoing the action.")
        }
    }

    private var activityList: some View {
        List {
            ForEach(viewModel.activities) { activity in
                ActivityRow(
                    activity: activity,
                    isUndoing: viewModel.isUndoing,
                    onUndo: {
                        Task {
                            let success = await viewModel.undo(activity: activity)
                            if !success {
                                showUndoError = true
                            }
                        }
                    }
                )
            }

            // Load more indicator
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let activity: ActivityLogItem
    let isUndoing: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: activity.actionIcon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.actionDescription)
                    .font(.subheadline)
                    .strikethrough(activity.reversed)
                    .foregroundColor(activity.reversed ? .secondary : .primary)

                HStack(spacing: 8) {
                    Text(activity.relativeTime)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let source = activity.source {
                        Text("via \(source)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if activity.reversed {
                        Text("(Undone)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // Undo button
            if activity.reversible && !activity.reversed {
                Button {
                    onUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .disabled(isUndoing)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconColor: Color {
        switch activity.actionColor {
        case "orange": return .orange
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "indigo": return .indigo
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Placeholder Views

struct HelpView: View {
    var body: some View {
        List {
            Section("About Kai") {
                Text("Kai is your personal AI assistant that helps manage your schedule, meetings, notes, and more.")
                    .foregroundColor(.secondary)
            }

            Section("Contact Support") {
                Link(destination: URL(string: "mailto:support@kai.app")!) {
                    Label("Email Support", systemImage: "envelope")
                }
            }

            Section("Version") {
                HStack {
                    Text("App Version")
                    Spacer()
                    Text(Bundle.main.appVersion)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct RemindersSettingsView: View {
    @StateObject private var remindersManager = RemindersManager.shared
    @State private var autoSync = true
    @State private var syncFrequency = "hourly"

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    switch remindersManager.authorizationStatus {
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

                // Show Connect button only when not determined
                if remindersManager.authorizationStatus == .notDetermined {
                    Button("Connect Apple Reminders") {
                        Task {
                            await remindersManager.requestAccess()
                        }
                    }
                }

                // Show Open Settings button when denied
                if remindersManager.authorizationStatus == .denied || remindersManager.authorizationStatus == .restricted {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            if remindersManager.authorizationStatus == .fullAccess || remindersManager.authorizationStatus == .writeOnly {
                Section("Sync Settings") {
                    Toggle("Auto-Sync to Kai", isOn: $autoSync)

                    if autoSync {
                        Picker("Sync Frequency", selection: $syncFrequency) {
                            Text("Every Hour").tag("hourly")
                            Text("Every 6 Hours").tag("6hours")
                            Text("Daily").tag("daily")
                        }
                    }

                    Button("Sync Now") {
                        Task {
                            try? await remindersManager.syncToBackend()
                        }
                    }
                }

                Section("Reminders") {
                    HStack {
                        Text("Total Reminders")
                        Spacer()
                        Text("\(remindersManager.reminders.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Incomplete")
                        Spacer()
                        Text("\(remindersManager.reminders.filter { !$0.isCompleted }.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            remindersManager.checkAuthorizationStatus()
        }
    }
}

// MARK: - Preview

#Preview {
    MoreView()
        .environmentObject(AuthenticationManager.shared)
}
