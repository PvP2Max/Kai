import SwiftUI

struct NotesListView: View {
    @StateObject private var viewModel = NotesViewModel()
    @State private var showingNewNote = false
    @State private var showingSortOptions = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.isEmpty {
                    loadingView
                } else if viewModel.isEmpty {
                    emptyStateView
                } else {
                    notesListContent
                }
            }
            .navigationTitle("Notes")
            .searchable(
                text: $viewModel.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search notes..."
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    sortButton
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewNote = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadNotes()
            }
            .sheet(isPresented: $showingNewNote) {
                NewNoteSheet(viewModel: viewModel)
            }
            .confirmationDialog("Sort By", isPresented: $showingSortOptions) {
                ForEach(NotesSortOrder.allCases, id: \.self) { order in
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading notes...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Notes", systemImage: "note.text")
        } description: {
            Text("Create your first note to get started.")
        } actions: {
            Button {
                showingNewNote = true
            } label: {
                Text("Create Note")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Notes List Content
    private var notesListContent: some View {
        Group {
            if !viewModel.hasSearchResults && !viewModel.searchQuery.isEmpty {
                noSearchResultsView
            } else {
                List {
                    ForEach(viewModel.filteredNotes) { note in
                        NavigationLink {
                            NoteDetailView(note: note, viewModel: viewModel)
                        } label: {
                            NoteRowView(note: note)
                        }
                    }
                    .onDelete { offsets in
                        Task {
                            await viewModel.deleteNote(at: offsets)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - No Search Results View
    private var noSearchResultsView: some View {
        ContentUnavailableView.search(text: viewModel.searchQuery)
    }

    // MARK: - Sort Button
    private var sortButton: some View {
        Button {
            showingSortOptions = true
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }
}

// MARK: - Note Row View
struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(note.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if note.title != nil {
                Text(note.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let tags = note.tags, !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags.prefix(3), id: \.self) { tag in
                        TagView(tag: tag)
                    }
                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tag View
struct TagView: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.1))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }
}

// MARK: - New Note Sheet
struct NewNoteSheet: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var isSaving: Bool = false

    private var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.headline)
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func saveNote() {
        isSaving = true
        Task {
            if await viewModel.createNote(title: title, content: content) != nil {
                dismiss()
            }
            isSaving = false
        }
    }
}

// MARK: - Preview
#Preview {
    NotesListView()
}
