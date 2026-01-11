//
//  AudioRecordingService.swift
//  Kai
//
//  Created by Kai on 2024.
//

import AVFoundation
import Foundation

// MARK: - Recording Error

enum RecordingError: LocalizedError {
    case microphonePermissionDenied
    case microphonePermissionRestricted
    case audioSessionSetupFailed(Error)
    case recorderCreationFailed(Error)
    case recordingFailed(Error)
    case noActiveRecording
    case fileOperationFailed(Error)
    case invalidFileName

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access was denied. Please enable it in Settings to record meetings."
        case .microphonePermissionRestricted:
            return "Microphone access is restricted on this device."
        case .audioSessionSetupFailed(let error):
            return "Failed to set up audio session: \(error.localizedDescription)"
        case .recorderCreationFailed(let error):
            return "Failed to create audio recorder: \(error.localizedDescription)"
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        case .noActiveRecording:
            return "No active recording to stop."
        case .fileOperationFailed(let error):
            return "File operation failed: \(error.localizedDescription)"
        case .invalidFileName:
            return "Invalid file name provided."
        }
    }
}

// MARK: - Audio Recording Service

@MainActor
final class AudioRecordingService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var currentRecordingURL: URL?
    @Published private(set) var audioLevel: Float = 0

    // MARK: - Private Properties

    private var audioRecorder: AVAudioRecorder?
    private var durationTimer: Timer?
    private var levelTimer: Timer?
    private var recordingStartTime: Date?

    // MARK: - Constants

    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    // MARK: - Computed Properties

    var recordingsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: recordingsPath.path) {
            try? FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        }

        return recordingsPath
    }

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Starts recording audio with an optional title for the file name
    /// - Parameter title: Optional title for the recording (used in filename)
    /// - Throws: RecordingError if permission is denied or recording fails to start
    func startRecording(for title: String? = nil) async throws {
        // Request microphone permission
        let permissionGranted = try await requestMicrophonePermission()
        guard permissionGranted else {
            throw RecordingError.microphonePermissionDenied
        }

        // Configure audio session
        try configureAudioSession()

        // Generate file URL
        let fileURL = generateRecordingURL(title: title)

        // Create and start recorder
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            guard audioRecorder?.record() == true else {
                throw RecordingError.recorderCreationFailed(
                    NSError(domain: "AudioRecording", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"])
                )
            }

            currentRecordingURL = fileURL
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0

            startDurationTimer()
            startLevelTimer()

        } catch let error as RecordingError {
            throw error
        } catch {
            throw RecordingError.recorderCreationFailed(error)
        }
    }

    /// Stops the current recording
    /// - Returns: The URL of the recorded file, or nil if no recording was active
    @discardableResult
    func stopRecording() -> URL? {
        guard isRecording, let recorder = audioRecorder else {
            return nil
        }

        recorder.stop()
        stopTimers()

        let recordedURL = currentRecordingURL

        isRecording = false
        audioRecorder = nil
        recordingStartTime = nil
        audioLevel = 0

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return recordedURL
    }

    /// Gets all recordings in the recordings directory
    /// - Returns: Array of recording file URLs sorted by modification date (newest first)
    func getRecordings() -> [URL] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            // Filter for audio files and sort by date
            return fileURLs
                .filter { $0.pathExtension.lowercased() == "m4a" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            print("Error fetching recordings: \(error.localizedDescription)")
            return []
        }
    }

    /// Deletes a recording at the specified URL
    /// - Parameter url: The URL of the recording to delete
    /// - Throws: RecordingError if deletion fails
    func deleteRecording(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw RecordingError.fileOperationFailed(error)
        }
    }

    /// Formats duration in MM:SS format
    /// - Parameter duration: Duration in seconds
    /// - Returns: Formatted string
    static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Private Methods

    private func requestMicrophonePermission() async throws -> Bool {
        if #available(iOS 17.0, *) {
            let status = AVAudioApplication.shared.recordPermission
            switch status {
            case .granted:
                return true
            case .denied:
                throw RecordingError.microphonePermissionDenied
            case .undetermined:
                return await AVAudioApplication.requestRecordPermission()
            @unknown default:
                throw RecordingError.microphonePermissionRestricted
            }
        } else {
            let status = AVAudioSession.sharedInstance().recordPermission
            switch status {
            case .granted:
                return true
            case .denied:
                throw RecordingError.microphonePermissionDenied
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                throw RecordingError.microphonePermissionRestricted
            }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            throw RecordingError.audioSessionSetupFailed(error)
        }
    }

    private func generateRecordingURL(title: String?) -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        let sanitizedTitle: String
        if let title = title, !title.isEmpty {
            // Sanitize title for use in filename
            sanitizedTitle = title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\\", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(50)
                .description
        } else {
            sanitizedTitle = "Recording"
        }

        let fileName = "\(sanitizedTitle)_\(timestamp).m4a"
        return recordingsDirectory.appendingPathComponent(fileName)
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func startLevelTimer() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let recorder = self.audioRecorder else { return }
                recorder.updateMeters()
                let level = recorder.averagePower(forChannel: 0)
                // Normalize level from -160...0 dB to 0...1
                let normalizedLevel = max(0, (level + 60) / 60)
                self.audioLevel = normalizedLevel
            }
        }
    }

    private func stopTimers() {
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                print("Recording finished unsuccessfully")
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("Recording encode error: \(error.localizedDescription)")
            }
            self.stopRecording()
        }
    }
}
