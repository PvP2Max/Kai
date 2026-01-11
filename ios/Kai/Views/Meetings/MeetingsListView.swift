//
//  MeetingsListView.swift
//  Kai
//
//  Created by Kai on 2024.
//

import SwiftUI

struct MeetingsListView: View {

    // MARK: - State

    @StateObject private var viewModel = MeetingsViewModel()
    @State private var showRecordingSheet = false
    @State private var showDocumentPicker = false
    @State private var selectedMeeting: Meeting?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.meetings.isEmpty {
                    loadingView
                } else if viewModel.meetings.isEmpty {
                    emptyStateView
                } else {
                    meetingsList
                }
            }
            .navigationTitle("Meetings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showRecordingSheet = true
                        } label: {
                            Label("Record Meeting", systemImage: "mic.fill")
                        }

                        Button {
                            showDocumentPicker = true
                        } label: {
                            Label("Upload Audio", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isLoading && !viewModel.meetings.isEmpty {
                        ProgressView()
                    }
                }
            }
            .refreshable {
                await viewModel.loadMeetings()
            }
            .sheet(isPresented: $showRecordingSheet) {
                RecordingView { recordingURL, title in
                    await uploadRecording(url: recordingURL, title: title)
                }
            }
            .fileImporter(
                isPresented: $showDocumentPicker,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .task {
                await viewModel.loadMeetings()
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading meetings...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Meetings", systemImage: "text.bubble")
        } description: {
            Text("Record or upload audio from your meetings to get transcripts and AI-powered summaries.")
        } actions: {
            Button {
                showRecordingSheet = true
            } label: {
                Label("Record Meeting", systemImage: "mic.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var meetingsList: some View {
        List {
            ForEach(viewModel.meetings) { meeting in
                NavigationLink(value: meeting) {
                    MeetingRowView(meeting: meeting)
                }
            }
            .onDelete(perform: deleteMeetings)
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Meeting.self) { meeting in
            MeetingDetailView(meeting: meeting, viewModel: viewModel)
        }
    }

    // MARK: - Methods

    private func uploadRecording(url: URL, title: String?) async {
        do {
            _ = try await viewModel.uploadRecording(url: url, title: title)
        } catch {
            print("Upload error: \(error)")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                return
            }

            defer { url.stopAccessingSecurityScopedResource() }

            // Copy file to app's documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsPath.appendingPathComponent(url.lastPathComponent)

            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)

                Task {
                    await uploadRecording(url: destinationURL, title: url.deletingPathExtension().lastPathComponent)
                }
            } catch {
                print("Error copying file: \(error)")
            }

        case .failure(let error):
            print("File import error: \(error)")
        }
    }

    private func deleteMeetings(at offsets: IndexSet) {
        let meetingsToDelete = offsets.map { viewModel.meetings[$0] }

        for meeting in meetingsToDelete {
            Task {
                try? await viewModel.deleteMeeting(id: meeting.id)
            }
        }
    }
}

// MARK: - Meeting Row View

struct MeetingRowView: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(meeting.displayDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let time = meeting.displayTime {
                        Text(time)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Status indicators
                HStack(spacing: 12) {
                    StatusBadge(
                        icon: "text.alignleft",
                        label: "Transcript",
                        isActive: meeting.hasTranscript
                    )

                    StatusBadge(
                        icon: "sparkles",
                        label: "Summary",
                        isActive: meeting.hasSummary
                    )
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let icon: String
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)

            Text(label)
                .font(.caption)
        }
        .foregroundStyle(isActive ? .green : .secondary)
    }
}

// MARK: - Preview

#Preview {
    MeetingsListView()
}
