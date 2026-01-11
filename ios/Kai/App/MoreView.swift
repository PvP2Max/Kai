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

// MARK: - Placeholder Views

struct ActivityLogView: View {
    var body: some View {
        List {
            Text("Activity log will appear here")
                .foregroundColor(.secondary)
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.large)
    }
}

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

                if remindersManager.authorizationStatus != .fullAccess {
                    Button("Connect Apple Reminders") {
                        Task {
                            await remindersManager.requestAccess()
                        }
                    }
                }
            }

            if remindersManager.authorizationStatus == .fullAccess {
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
        .task {
            await remindersManager.requestAccess()
        }
    }
}

// MARK: - Preview

#Preview {
    MoreView()
        .environmentObject(AuthenticationManager.shared)
}
