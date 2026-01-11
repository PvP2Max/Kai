import SwiftUI

struct NoteDetailView: View {
    let note: Note
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var isEditing: Bool = false
    @State private var isSaving: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var hasChanges: Bool = false

    init(note: Note, viewModel: NotesViewModel) {
        self.note = note
        self.viewModel = viewModel
        _editedTitle = State(initialValue: note.title ?? "")
        _editedContent = State(initialValue: note.content)
    }

    private var canSave: Bool {
        !editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasChanges
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                if isEditing {
                    TextField("Title", text: $editedTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .textFieldStyle(.plain)
                        .padding(.horizontal)
                        .onChange(of: editedTitle) { _, _ in
                            checkForChanges()
                        }
                } else {
                    Text(note.displayTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.horizontal)
                }

                // Metadata
                HStack(spacing: 16) {
                    Label(note.formattedCreatedDate, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if note.hasBeenEdited {
                        Label("Edited \(note.formattedDate)", systemImage: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Tags
                if let tags = note.tags, !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tags, id: \.self) { tag in
                                TagView(tag: tag)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Content
                if isEditing {
                    TextEditor(text: $editedContent)
                        .font(.body)
                        .frame(minHeight: 300)
                        .padding(.horizontal, 12)
                        .scrollContentBackground(.hidden)
                        .onChange(of: editedContent) { _, _ in
                            checkForChanges()
                        }
                } else {
                    Text(note.content.isEmpty ? "No content" : note.content)
                        .font(.body)
                        .foregroundStyle(note.content.isEmpty ? .secondary : .primary)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 100)
            }
            .padding(.top)
        }
        .navigationTitle(isEditing ? "Edit Note" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    HStack(spacing: 16) {
                        Button("Cancel") {
                            cancelEditing()
                        }
                        .foregroundStyle(.secondary)

                        Button("Save") {
                            saveChanges()
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave || isSaving)
                    }
                } else {
                    Menu {
                        Button {
                            startEditing()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Divider()

                        ShareLink(item: shareContent) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Note",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteNote()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this note? This action cannot be undone.")
        }
        .overlay {
            if isSaving {
                savingOverlay
            }
        }
    }

    // MARK: - Computed Properties
    private var shareContent: String {
        if let title = note.title {
            return "\(title)\n\n\(note.content)"
        }
        return note.content
    }

    // MARK: - Saving Overlay
    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Saving...")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Actions
    private func startEditing() {
        editedTitle = note.title ?? ""
        editedContent = note.content
        hasChanges = false
        withAnimation {
            isEditing = true
        }
    }

    private func cancelEditing() {
        editedTitle = note.title ?? ""
        editedContent = note.content
        hasChanges = false
        withAnimation {
            isEditing = false
        }
    }

    private func checkForChanges() {
        hasChanges = editedTitle != (note.title ?? "") || editedContent != note.content
    }

    private func saveChanges() {
        guard canSave else { return }

        isSaving = true
        Task {
            var updatedNote = note
            let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedNote.title = trimmedTitle.isEmpty ? nil : trimmedTitle
            updatedNote.content = editedContent

            let success = await viewModel.updateNote(updatedNote)
            isSaving = false

            if success {
                withAnimation {
                    isEditing = false
                    hasChanges = false
                }
            }
        }
    }

    private func deleteNote() {
        Task {
            let success = await viewModel.deleteNote(id: note.id)
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        NoteDetailView(
            note: Note.sample,
            viewModel: NotesViewModel()
        )
    }
}
