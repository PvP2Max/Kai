//
//  DataUsageView.swift
//  Kai
//
//  Displays usage statistics for tokens, requests, and costs.
//

import SwiftUI

// MARK: - Usage Models

struct UsageSummaryResponse: Codable {
    let totals: UsageTotals
    let byModel: [String: ModelUsage]
    let period: String?

    enum CodingKeys: String, CodingKey {
        case totals
        case byModel = "by_model"
        case period
    }
}

struct UsageTotals: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
    let requests: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cost
        case requests
    }

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}

struct ModelUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
    let requests: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cost
        case requests
    }
}

// MARK: - View Model

@MainActor
class DataUsageViewModel: ObservableObject {
    @Published var usage: UsageSummaryResponse?
    @Published var isLoading = false
    @Published var error: String?

    func loadUsage() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: UsageSummaryResponse = try await APIClient.shared.request(
                .usageSummary,
                method: .get
            )
            usage = response
        } catch {
            self.error = error.localizedDescription
            #if DEBUG
            print("[DataUsageViewModel] Failed to load usage: \(error)")
            #endif
        }
    }
}

// MARK: - Data Usage View

struct DataUsageView: View {
    @StateObject private var viewModel = DataUsageViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.usage == nil {
                ProgressView("Loading usage data...")
            } else if let error = viewModel.error, viewModel.usage == nil {
                ContentUnavailableView {
                    Label("Unable to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.loadUsage() }
                    }
                }
            } else if let usage = viewModel.usage {
                usageContent(usage)
            } else {
                ContentUnavailableView(
                    "No Usage Data",
                    systemImage: "chart.bar",
                    description: Text("Usage statistics will appear here after you start using Kai.")
                )
            }
        }
        .navigationTitle("Data Usage")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadUsage()
        }
        .task {
            await viewModel.loadUsage()
        }
    }

    @ViewBuilder
    private func usageContent(_ usage: UsageSummaryResponse) -> some View {
        List {
            // Summary Section
            Section("Summary") {
                StatRow(label: "Total Requests", value: "\(usage.totals.requests)")
                StatRow(label: "Total Tokens", value: formatNumber(usage.totals.totalTokens))
                StatRow(label: "Input Tokens", value: formatNumber(usage.totals.inputTokens))
                StatRow(label: "Output Tokens", value: formatNumber(usage.totals.outputTokens))
            }

            // Cost Section
            Section("Estimated Cost") {
                StatRow(label: "Total Cost", value: formatCurrency(usage.totals.cost))
            }

            // By Model Section
            if !usage.byModel.isEmpty {
                Section("Usage by Model") {
                    ForEach(Array(usage.byModel.keys.sorted()), id: \.self) { model in
                        if let modelUsage = usage.byModel[model] {
                            ModelUsageRow(model: model, usage: modelUsage)
                        }
                    }
                }
            }
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.4f", amount))"
    }
}

// MARK: - Supporting Views

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
        }
    }
}

struct ModelUsageRow: View {
    let model: String
    let usage: ModelUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(modelDisplayName)
                    .font(.headline)
                Spacer()
                Text("\(usage.requests) requests")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Tokens")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(formatNumber(usage.inputTokens + usage.outputTokens))")
                        .font(.subheadline)
                }

                VStack(alignment: .leading) {
                    Text("Cost")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(usage.cost))
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var modelDisplayName: String {
        switch model.lowercased() {
        case let m where m.contains("opus"):
            return "Claude Opus"
        case let m where m.contains("sonnet"):
            return "Claude Sonnet"
        case let m where m.contains("haiku"):
            return "Claude Haiku"
        default:
            return model
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.4f", amount))"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DataUsageView()
    }
}
