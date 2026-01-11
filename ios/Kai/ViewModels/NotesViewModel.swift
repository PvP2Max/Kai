import Foundation
import Combine

@MainActor
class NotesViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var notes: [Note] = []
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var sortOrder: NotesSortOrder = .updatedNewest

    // MARK: - Private Properties
    private var allNotes: [Note] = []
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties
    var filteredNotes: [Note] {
        var result = allNotes

        // Apply search filter
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { note in
                (note.title?.lowercased().contains(query) ?? false) ||
                note.content.lowercased().contains(query) ||
                (note.tags?.contains { $0.lowercased().contains(query) } ?? false)
            }
        }

        // Apply sort order
        switch sortOrder {
        case .updatedNewest:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .updatedOldest:
            result.sort { $0.updatedAt < $1.updatedAt }
        case .createdNewest:
            result.sort { $0.createdAt > $1.createdAt }
        case .createdOldest:
            result.sort { $0.createdAt < $1.createdAt }
        case .alphabetical:
            result.sort { ($0.title ?? "").lowercased() < ($1.title ?? "").lowercased() }
        }

        return result
    }

    var isEmpty: Bool {
        allNotes.isEmpty
    }

    var hasSearchResults: Bool {
        !filteredNotes.isEmpty
    }

    // MARK: - Initialization
    init() {
        setupSearchDebounce()
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Methods
    func loadNotes() async {
        isLoading = true
        errorMessage = nil

        do {
            // TODO: Replace with actual API call
            // Simulating API call
            try await Task.sleep(nanoseconds: 500_000_000)

            // In production, this would be:
            // let response = try await APIClient.shared.getNotes()
            // self.allNotes = response.notes

            // Using sample data for now
            self.allNotes = Note.samples
            self.notes = self.allNotes

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func createNote(title: String, content: String, tags: [String]? = nil) async -> Note? {
        isLoading = true
        errorMessage = nil

        do {
            // TODO: Replace with actual API call
            try await Task.sleep(nanoseconds: 300_000_000)

            let newNote = Note(
                id: UUID(),
                title: title.isEmpty ? nil : title,
                content: content,
                source: "ios",
                meetingEventId: nil,
                projectId: nil,
                tags: tags,
                createdAt: Date(),
                updatedAt: Date()
            )

            // In production:
            // let createdNote = try await APIClient.shared.createNote(title: title, content: content)
            // self.allNotes.insert(createdNote, at: 0)

            self.allNotes.insert(newNote, at: 0)
            self.notes = self.allNotes
            isLoading = false
            return newNote

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return nil
        }
    }

    func updateNote(_ note: Note) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            // TODO: Replace with actual API call
            try await Task.sleep(nanoseconds: 300_000_000)

            // In production:
            // let updatedNote = try await APIClient.shared.updateNote(note)

            if let index = allNotes.firstIndex(where: { $0.id == note.id }) {
                var updated = note
                updated.updatedAt = Date()
                allNotes[index] = updated
                self.notes = self.allNotes
            }

            isLoading = false
            return true

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func deleteNote(id: UUID) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            // TODO: Replace with actual API call
            try await Task.sleep(nanoseconds: 300_000_000)

            // In production:
            // try await APIClient.shared.deleteNote(id: id)

            allNotes.removeAll(where: { $0.id == id })
            self.notes = self.allNotes
            isLoading = false
            return true

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func deleteNote(at offsets: IndexSet) async {
        let notesToDelete = offsets.map { filteredNotes[$0] }
        for note in notesToDelete {
            _ = await deleteNote(id: note.id)
        }
    }

    func refresh() async {
        await loadNotes()
    }

    func clearSearch() {
        searchQuery = ""
    }
}

// MARK: - Supporting Types
enum NotesSortOrder: String, CaseIterable {
    case updatedNewest = "Recently Updated"
    case updatedOldest = "Oldest Updated"
    case createdNewest = "Recently Created"
    case createdOldest = "Oldest Created"
    case alphabetical = "Alphabetical"

    var icon: String {
        switch self {
        case .updatedNewest, .createdNewest:
            return "arrow.down"
        case .updatedOldest, .createdOldest:
            return "arrow.up"
        case .alphabetical:
            return "textformat.abc"
        }
    }
}
