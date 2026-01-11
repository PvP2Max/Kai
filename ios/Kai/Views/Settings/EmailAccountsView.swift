import SwiftUI

// MARK: - Email Account Model

struct EmailAccount: Codable, Identifiable {
    let id: String
    let provider: String
    let emailAddress: String
    var displayName: String
    var includeInBriefing: Bool
    var briefingDays: [String]?
    var priority: Int
    var maxEmailsInBriefing: Int
    var categoriesToInclude: [String]?
    var isActive: Bool
    let lastSync: Date?
    let syncError: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case emailAddress = "email_address"
        case displayName = "display_name"
        case includeInBriefing = "include_in_briefing"
        case briefingDays = "briefing_days"
        case priority
        case maxEmailsInBriefing = "max_emails_in_briefing"
        case categoriesToInclude = "categories_to_include"
        case isActive = "is_active"
        case lastSync = "last_sync"
        case syncError = "sync_error"
        case createdAt = "created_at"
    }
}

struct EmailBriefingConfig: Codable {
    let id: String
    var briefingEnabled: Bool
    var morningBriefingTime: String?
    var weekdayAccounts: [String]?
    var weekendAccounts: [String]?
    var skipDays: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case briefingEnabled = "briefing_enabled"
        case morningBriefingTime = "morning_briefing_time"
        case weekdayAccounts = "weekday_accounts"
        case weekendAccounts = "weekend_accounts"
        case skipDays = "skip_days"
    }
}

struct EmailAccountListResponse: Codable {
    let accounts: [EmailAccount]
    let count: Int
}

struct OAuthStartResponse: Codable {
    let authUrl: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case authUrl = "auth_url"
        case state
    }
}

struct EmailAccountUpdateRequest: Codable {
    let displayName: String
    let includeInBriefing: Bool
    let briefingDays: [String]
    let priority: Int
    let maxEmailsInBriefing: Int
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case includeInBriefing = "include_in_briefing"
        case briefingDays = "briefing_days"
        case priority
        case maxEmailsInBriefing = "max_emails_in_briefing"
        case isActive = "is_active"
    }
}

struct EmailBriefingConfigUpdateRequest: Codable {
    let briefingEnabled: Bool
    let morningBriefingTime: String?
    let weekdayAccounts: [String]?
    let weekendAccounts: [String]?
    let skipDays: [String]?

    enum CodingKeys: String, CodingKey {
        case briefingEnabled = "briefing_enabled"
        case morningBriefingTime = "morning_briefing_time"
        case weekdayAccounts = "weekday_accounts"
        case weekendAccounts = "weekend_accounts"
        case skipDays = "skip_days"
    }
}

struct EmptyBody: Codable {}

// MARK: - View Model

@MainActor
class EmailAccountsViewModel: ObservableObject {
    @Published var accounts: [EmailAccount] = []
    @Published var briefingConfig: EmailBriefingConfig?
    @Published var isLoading = false
    @Published var error: String?
    @Published var showAddAccount = false

    func loadAccounts() async {
        isLoading = true
        error = nil

        do {
            let response: EmailAccountListResponse = try await APIClient.shared.request(
                .custom("/email-accounts"),
                method: .get
            )
            accounts = response.accounts
        } catch {
            self.error = error.localizedDescription
        }

        // Load briefing config
        do {
            let config: EmailBriefingConfig = try await APIClient.shared.request(
                .custom("/email-accounts/briefing/config"),
                method: .get
            )
            briefingConfig = config
        } catch {
            // Config may not exist yet
        }

        isLoading = false
    }

    func updateAccount(_ account: EmailAccount) async {
        do {
            let body = EmailAccountUpdateRequest(
                displayName: account.displayName,
                includeInBriefing: account.includeInBriefing,
                briefingDays: account.briefingDays ?? ["all"],
                priority: account.priority,
                maxEmailsInBriefing: account.maxEmailsInBriefing,
                isActive: account.isActive
            )

            let _: EmailAccount = try await APIClient.shared.request(
                .custom("/email-accounts/\(account.id)"),
                method: .put,
                body: body
            )

            await loadAccounts()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAccount(_ account: EmailAccount) async {
        do {
            let _: EmptyBody = try await APIClient.shared.request(
                .custom("/email-accounts/\(account.id)"),
                method: .delete
            )

            accounts.removeAll { $0.id == account.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateBriefingConfig() async {
        guard let config = briefingConfig else { return }

        do {
            let body = EmailBriefingConfigUpdateRequest(
                briefingEnabled: config.briefingEnabled,
                morningBriefingTime: config.morningBriefingTime,
                weekdayAccounts: config.weekdayAccounts,
                weekendAccounts: config.weekendAccounts,
                skipDays: config.skipDays
            )

            let _: EmailBriefingConfig = try await APIClient.shared.request(
                .custom("/email-accounts/briefing/config"),
                method: .put,
                body: body
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startOAuth(provider: String) async -> URL? {
        do {
            let response: OAuthStartResponse = try await APIClient.shared.request(
                .custom("/email-accounts/oauth/\(provider)/start"),
                method: .get
            )
            return URL(string: response.authUrl)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}

// MARK: - Main View

struct EmailAccountsView: View {
    @StateObject private var viewModel = EmailAccountsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    // Accounts Section
                    Section("Email Accounts") {
                        if viewModel.accounts.isEmpty {
                            Text("No email accounts connected")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.accounts) { account in
                                NavigationLink {
                                    EmailAccountDetailView(account: account, viewModel: viewModel)
                                } label: {
                                    EmailAccountRow(account: account)
                                }
                            }
                            .onDelete { indexSet in
                                Task {
                                    for index in indexSet {
                                        await viewModel.deleteAccount(viewModel.accounts[index])
                                    }
                                }
                            }
                        }

                        Button {
                            viewModel.showAddAccount = true
                        } label: {
                            Label("Add Email Account", systemImage: "plus.circle.fill")
                        }
                    }

                    // Briefing Settings Section
                    if let config = viewModel.briefingConfig {
                        Section("Email Briefing") {
                            Toggle("Include Emails in Briefing", isOn: Binding(
                                get: { config.briefingEnabled },
                                set: { newValue in
                                    viewModel.briefingConfig?.briefingEnabled = newValue
                                    Task { await viewModel.updateBriefingConfig() }
                                }
                            ))

                            if config.briefingEnabled && !viewModel.accounts.isEmpty {
                                NavigationLink {
                                    BriefingScheduleView(
                                        accounts: viewModel.accounts,
                                        config: Binding(
                                            get: { viewModel.briefingConfig! },
                                            set: { viewModel.briefingConfig = $0 }
                                        ),
                                        onSave: {
                                            Task { await viewModel.updateBriefingConfig() }
                                        }
                                    )
                                } label: {
                                    HStack {
                                        Text("Briefing Schedule")
                                        Spacer()
                                        Text(briefingScheduleSummary(config))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Email Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddAccount) {
                AddEmailAccountView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadAccounts()
            }
            .refreshable {
                await viewModel.loadAccounts()
            }
        }
    }

    private func briefingScheduleSummary(_ config: EmailBriefingConfig) -> String {
        if config.skipDays?.contains("saturday") == true &&
           config.skipDays?.contains("sunday") == true {
            return "Weekdays only"
        }
        if config.weekdayAccounts != nil || config.weekendAccounts != nil {
            return "Custom"
        }
        return "All days"
    }
}

// MARK: - Email Account Row

struct EmailAccountRow: View {
    let account: EmailAccount

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: providerIcon)
                .font(.title2)
                .foregroundStyle(account.isActive ? .blue : .gray)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.headline)

                Text(account.emailAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let error = account.syncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if account.includeInBriefing {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var providerIcon: String {
        switch account.provider.lowercased() {
        case "gmail": return "envelope.fill"
        case "outlook": return "envelope.badge.fill"
        case "icloud": return "icloud.fill"
        default: return "envelope"
        }
    }
}

// MARK: - Email Account Detail View

struct EmailAccountDetailView: View {
    @State var account: EmailAccount
    let viewModel: EmailAccountsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Text("Email")
                    Spacer()
                    Text(account.emailAddress)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Provider")
                    Spacer()
                    Text(account.provider.capitalized)
                        .foregroundStyle(.secondary)
                }

                TextField("Display Name", text: $account.displayName)
            }

            Section("Status") {
                Toggle("Active", isOn: $account.isActive)

                if let lastSync = account.lastSync {
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        Text(lastSync, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = account.syncError {
                    HStack {
                        Text("Error")
                        Spacer()
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Briefing Settings") {
                Toggle("Include in Briefing", isOn: $account.includeInBriefing)

                if account.includeInBriefing {
                    Stepper("Max Emails: \(account.maxEmailsInBriefing)",
                            value: $account.maxEmailsInBriefing, in: 1...50)

                    NavigationLink {
                        BriefingDaysPickerView(selectedDays: Binding(
                            get: { account.briefingDays ?? ["all"] },
                            set: { account.briefingDays = $0 }
                        ))
                    } label: {
                        HStack {
                            Text("Days")
                            Spacer()
                            Text(daysSummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Save Changes") {
                    Task {
                        await viewModel.updateAccount(account)
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Section {
                Button("Remove Account", role: .destructive) {
                    Task {
                        await viewModel.deleteAccount(account)
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(account.displayName)
    }

    private var daysSummary: String {
        guard let days = account.briefingDays, !days.isEmpty else {
            return "All days"
        }
        if days.contains("all") { return "All days" }
        if days.contains("weekdays") { return "Weekdays" }
        if days.contains("weekends") { return "Weekends" }
        return "\(days.count) days"
    }
}

// MARK: - Add Email Account View

struct AddEmailAccountView: View {
    @ObservedObject var viewModel: EmailAccountsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Choose Provider") {
                    providerButton("Gmail", provider: "gmail", icon: "envelope.fill", color: .red)
                    providerButton("Outlook", provider: "outlook", icon: "envelope.badge.fill", color: .blue)
                        .disabled(true)
                    providerButton("iCloud", provider: "icloud", icon: "icloud.fill", color: .cyan)
                        .disabled(true)
                }

                Section {
                    Text("Connect your email account to include emails in your daily briefing and allow Kai to help manage your inbox.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Email Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func providerButton(_ name: String, provider: String, icon: String, color: Color) -> some View {
        Button {
            Task {
                if let url = await viewModel.startOAuth(provider: provider) {
                    await UIApplication.shared.open(url)
                    dismiss()
                }
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 32)

                Text(name)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Briefing Days Picker

struct BriefingDaysPickerView: View {
    @Binding var selectedDays: [String]
    @Environment(\.dismiss) private var dismiss

    let allDays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    let presets = [
        ("All days", ["all"]),
        ("Weekdays only", ["weekdays"]),
        ("Weekends only", ["weekends"]),
    ]

    var body: some View {
        List {
            Section("Presets") {
                ForEach(presets, id: \.0) { preset in
                    Button {
                        selectedDays = preset.1
                    } label: {
                        HStack {
                            Text(preset.0)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedDays == preset.1 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            Section("Custom Days") {
                ForEach(allDays, id: \.self) { day in
                    Button {
                        toggleDay(day)
                    } label: {
                        HStack {
                            Text(day.capitalized)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isDaySelected(day) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Briefing Days")
    }

    private func isDaySelected(_ day: String) -> Bool {
        if selectedDays.contains("all") { return true }
        if selectedDays.contains("weekdays") && !["saturday", "sunday"].contains(day) { return true }
        if selectedDays.contains("weekends") && ["saturday", "sunday"].contains(day) { return true }
        return selectedDays.contains(day)
    }

    private func toggleDay(_ day: String) {
        // Remove presets when selecting individual days
        selectedDays.removeAll { $0 == "all" || $0 == "weekdays" || $0 == "weekends" }

        if selectedDays.contains(day) {
            selectedDays.removeAll { $0 == day }
        } else {
            selectedDays.append(day)
        }

        if selectedDays.isEmpty {
            selectedDays = ["all"]
        }
    }
}

// MARK: - Briefing Schedule View

struct BriefingScheduleView: View {
    let accounts: [EmailAccount]
    @Binding var config: EmailBriefingConfig
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Weekday Emails (Mon-Fri)") {
                ForEach(accounts) { account in
                    Toggle(account.displayName, isOn: Binding(
                        get: { isAccountSelectedForWeekdays(account) },
                        set: { toggleWeekdayAccount(account, selected: $0) }
                    ))
                }
            }

            Section("Weekend Emails (Sat-Sun)") {
                ForEach(accounts) { account in
                    Toggle(account.displayName, isOn: Binding(
                        get: { isAccountSelectedForWeekends(account) },
                        set: { toggleWeekendAccount(account, selected: $0) }
                    ))
                }
            }

            Section("Skip Days") {
                Toggle("Skip Saturday", isOn: Binding(
                    get: { config.skipDays?.contains("saturday") ?? false },
                    set: { toggleSkipDay("saturday", skip: $0) }
                ))

                Toggle("Skip Sunday", isOn: Binding(
                    get: { config.skipDays?.contains("sunday") ?? false },
                    set: { toggleSkipDay("sunday", skip: $0) }
                ))
            }

            Section {
                Button("Save Schedule") {
                    onSave()
                    dismiss()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Briefing Schedule")
    }

    private func isAccountSelectedForWeekdays(_ account: EmailAccount) -> Bool {
        guard let weekdayAccounts = config.weekdayAccounts else {
            return true // Default to all
        }
        return weekdayAccounts.contains(account.id)
    }

    private func isAccountSelectedForWeekends(_ account: EmailAccount) -> Bool {
        guard let weekendAccounts = config.weekendAccounts else {
            return true // Default to all
        }
        return weekendAccounts.contains(account.id)
    }

    private func toggleWeekdayAccount(_ account: EmailAccount, selected: Bool) {
        if config.weekdayAccounts == nil {
            config.weekdayAccounts = accounts.map { $0.id }
        }
        if selected {
            if !config.weekdayAccounts!.contains(account.id) {
                config.weekdayAccounts!.append(account.id)
            }
        } else {
            config.weekdayAccounts!.removeAll { $0 == account.id }
        }
    }

    private func toggleWeekendAccount(_ account: EmailAccount, selected: Bool) {
        if config.weekendAccounts == nil {
            config.weekendAccounts = accounts.map { $0.id }
        }
        if selected {
            if !config.weekendAccounts!.contains(account.id) {
                config.weekendAccounts!.append(account.id)
            }
        } else {
            config.weekendAccounts!.removeAll { $0 == account.id }
        }
    }

    private func toggleSkipDay(_ day: String, skip: Bool) {
        if config.skipDays == nil {
            config.skipDays = []
        }
        if skip {
            if !config.skipDays!.contains(day) {
                config.skipDays!.append(day)
            }
        } else {
            config.skipDays!.removeAll { $0 == day }
        }
    }
}

#Preview {
    EmailAccountsView()
}
