//
//  ActivityLogViewModel.swift
//  Kai
//
//  Manages fetching and undoing activity log items.
//

import Foundation

@MainActor
final class ActivityLogViewModel: ObservableObject {
    @Published var activities: [ActivityLogItem] = []
    @Published var isLoading = false
    @Published var isUndoing = false
    @Published var error: String?
    @Published var undoError: String?

    private var offset = 0
    private let limit = 50
    private var hasMore = true

    func loadActivities() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        offset = 0
        hasMore = true

        defer { isLoading = false }

        do {
            let items: [ActivityLogItem] = try await APIClient.shared.request(
                .custom("/activity?limit=\(limit)&offset=0"),
                method: .get
            )
            activities = items
            hasMore = items.count == limit
            offset = items.count
        } catch {
            self.error = error.localizedDescription
            #if DEBUG
            print("[ActivityLogViewModel] Failed to load activities: \(error)")
            #endif
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let items: [ActivityLogItem] = try await APIClient.shared.request(
                .custom("/activity?limit=\(limit)&offset=\(offset)"),
                method: .get
            )

            activities.append(contentsOf: items)
            hasMore = items.count == limit
            offset += items.count
        } catch {
            #if DEBUG
            print("[ActivityLogViewModel] Failed to load more activities: \(error)")
            #endif
        }
    }

    func undo(activity: ActivityLogItem) async -> Bool {
        guard activity.reversible, !activity.reversed else { return false }

        isUndoing = true
        undoError = nil
        defer { isUndoing = false }

        do {
            let _: UndoResponse = try await APIClient.shared.request(
                .activityUndo(id: activity.id.uuidString),
                method: .post
            )

            // Update local state
            if let index = activities.firstIndex(where: { $0.id == activity.id }) {
                // Create updated activity with reversed = true
                let updated = ActivityLogItem(
                    id: activity.id,
                    actionType: activity.actionType,
                    actionData: activity.actionData,
                    source: activity.source,
                    reversible: activity.reversible,
                    reversed: true,
                    createdAt: activity.createdAt
                )
                activities[index] = updated
            }

            return true
        } catch {
            undoError = error.localizedDescription
            #if DEBUG
            print("[ActivityLogViewModel] Failed to undo activity: \(error)")
            #endif
            return false
        }
    }

    func refresh() async {
        await loadActivities()
    }
}
