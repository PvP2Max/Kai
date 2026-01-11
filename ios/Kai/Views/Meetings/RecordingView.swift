//
//  RecordingView.swift
//  Kai
//
//  Created by Kai on 2024.
//

import SwiftUI

struct RecordingView: View {

    // MARK: - Properties

    let onRecordingComplete: (URL, String?) async -> Void

    // MARK: - State

    @StateObject private var recordingService = AudioRecordingService()
    @State private var meetingTitle: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isUploading: Bool = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Microphone visualization
                microphoneView

                // Duration display
                durationView

                // Title input (when not recording)
                if !recordingService.isRecording {
                    titleInputView
                }

                Spacer()

                // Record button
                recordButton

                // Instructions
                instructionText

                Spacer()
            }
            .padding()
            .navigationTitle("Record Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if recordingService.isRecording {
                            _ = recordingService.stopRecording()
                        }
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isUploading {
                        ProgressView()
                    }
                }
            }
            .alert("Recording Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .interactiveDismissDisabled(recordingService.isRecording || isUploading)
        }
    }

    // MARK: - Microphone View

    private var microphoneView: some View {
        ZStack {
            // Outer pulsing circles (when recording)
            if recordingService.isRecording {
                ForEach(0..<3, id: \.self) { index in
                    PulsingCircle(
                        delay: Double(index) * 0.3,
                        audioLevel: recordingService.audioLevel
                    )
                }
            }

            // Main circle
            Circle()
                .fill(recordingService.isRecording ? Color.red.opacity(0.2) : Color.gray.opacity(0.1))
                .frame(width: 160, height: 160)

            // Inner circle with icon
            Circle()
                .fill(recordingService.isRecording ? Color.red : Color.gray.opacity(0.3))
                .frame(width: 100, height: 100)
                .overlay {
                    if recordingService.isRecording {
                        // Waveform visualization
                        WaveformView(level: recordingService.audioLevel)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                }
                .shadow(color: recordingService.isRecording ? .red.opacity(0.3) : .clear, radius: 20)
        }
        .animation(.easeInOut(duration: 0.3), value: recordingService.isRecording)
    }

    // MARK: - Duration View

    private var durationView: some View {
        Text(AudioRecordingService.formatDuration(recordingService.recordingDuration))
            .font(.system(size: 48, weight: .light, design: .monospaced))
            .foregroundStyle(recordingService.isRecording ? .primary : .secondary)
    }

    // MARK: - Title Input View

    private var titleInputView: some View {
        VStack(spacing: 8) {
            Text("Meeting Title (Optional)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("e.g., Weekly Standup", text: $meetingTitle)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .multilineTextAlignment(.center)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            Task {
                await handleRecordButtonTap()
            }
        } label: {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(recordingService.isRecording ? Color.red : Color.blue, lineWidth: 4)
                    .frame(width: 80, height: 80)

                // Inner content
                if recordingService.isRecording {
                    // Stop icon (rounded square)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red)
                        .frame(width: 30, height: 30)
                } else {
                    // Record icon (circle)
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 64, height: 64)
                }
            }
        }
        .disabled(isUploading)
        .buttonStyle(.plain)
        .accessibilityLabel(recordingService.isRecording ? "Stop Recording" : "Start Recording")
    }

    // MARK: - Instruction Text

    private var instructionText: some View {
        Text(recordingService.isRecording
             ? "Tap to stop recording"
             : "Tap to start recording your meeting")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Methods

    private func handleRecordButtonTap() async {
        if recordingService.isRecording {
            // Stop recording
            if let recordingURL = recordingService.stopRecording() {
                isUploading = true
                let title = meetingTitle.isEmpty ? nil : meetingTitle
                await onRecordingComplete(recordingURL, title)
                isUploading = false
                dismiss()
            }
        } else {
            // Start recording
            do {
                let title = meetingTitle.isEmpty ? nil : meetingTitle
                try await recordingService.startRecording(for: title)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Pulsing Circle

struct PulsingCircle: View {
    let delay: Double
    let audioLevel: Float

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .stroke(Color.red.opacity(0.3), lineWidth: 2)
            .frame(width: 160 + CGFloat(audioLevel * 60), height: 160 + CGFloat(audioLevel * 60))
            .scaleEffect(isAnimating ? 1.3 : 1.0)
            .opacity(isAnimating ? 0 : 0.6)
            .animation(
                .easeOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let level: Float

    private let barCount = 5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    level: level,
                    index: index,
                    totalBars: barCount
                )
            }
        }
    }
}

struct WaveformBar: View {
    let level: Float
    let index: Int
    let totalBars: Int

    @State private var randomOffset: Double = 0

    private var height: CGFloat {
        let baseHeight: CGFloat = 10
        let maxHeight: CGFloat = 40

        // Create variation based on bar position
        let centerIndex = Double(totalBars - 1) / 2.0
        let distanceFromCenter = abs(Double(index) - centerIndex) / centerIndex
        let positionMultiplier = 1.0 - (distanceFromCenter * 0.5)

        // Combine audio level with position
        let normalizedLevel = CGFloat(level) * positionMultiplier
        let variation = CGFloat.random(in: 0.8...1.2)

        return baseHeight + (maxHeight - baseHeight) * normalizedLevel * variation
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: 6, height: height)
            .animation(.easeInOut(duration: 0.1), value: level)
    }
}

// MARK: - Preview

#Preview("Not Recording") {
    RecordingView { _, _ in }
}

#Preview("Recording") {
    RecordingViewPreviewWrapper()
}

struct RecordingViewPreviewWrapper: View {
    var body: some View {
        RecordingView { _, _ in }
    }
}
