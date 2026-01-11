//
//  SpeechService.swift
//  Kai
//
//  Text-to-speech service using AVSpeechSynthesizer.
//

import AVFoundation
import Foundation

// MARK: - Speech Service

@MainActor
final class SpeechService: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = SpeechService()

    // MARK: - Published Properties

    @Published private(set) var isSpeaking: Bool = false
    @Published var isEnabled: Bool = true
    @Published var autoSpeakForVoiceInput: Bool = true
    @Published var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var speechPitch: Float = 1.0

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?

    // MARK: - Voice Selection

    /// Gets the preferred voice for speech
    private var preferredVoice: AVSpeechSynthesisVoice? {
        // Try to get a premium/enhanced voice first
        let voices = AVSpeechSynthesisVoice.speechVoices()

        // Prefer enhanced quality voices
        if let enhancedVoice = voices.first(where: {
            $0.language.hasPrefix("en-US") && $0.quality == .enhanced
        }) {
            return enhancedVoice
        }

        // Fall back to default US English voice
        if let defaultVoice = AVSpeechSynthesisVoice(language: "en-US") {
            return defaultVoice
        }

        // Last resort - any English voice
        return voices.first { $0.language.hasPrefix("en") }
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        synthesizer.delegate = self
        loadSettings()
    }

    // MARK: - Public Methods

    /// Speaks the given text
    /// - Parameter text: The text to speak
    func speak(_ text: String) {
        guard isEnabled else { return }
        guard !text.isEmpty else { return }

        // Stop any current speech
        if isSpeaking {
            stop()
        }

        // Configure audio session for playback
        configureAudioSession()

        // Clean up text for speech (remove markdown, etc.)
        let cleanText = cleanTextForSpeech(text)

        // Create utterance
        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = preferredVoice
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.volume = 1.0

        // Add slight pauses for better comprehension
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1

        currentUtterance = utterance
        isSpeaking = true

        synthesizer.speak(utterance)

        #if DEBUG
        print("[SpeechService] Speaking: \(cleanText.prefix(50))...")
        #endif
    }

    /// Speaks text only if the last input was voice-triggered
    /// - Parameters:
    ///   - text: The text to speak
    ///   - wasVoiceInput: Whether the original input was voice-triggered
    func speakIfVoiceTriggered(_ text: String, wasVoiceInput: Bool) {
        guard autoSpeakForVoiceInput && wasVoiceInput else { return }
        speak(text)
    }

    /// Stops current speech
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        currentUtterance = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Pauses current speech
    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    /// Resumes paused speech
    func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
    }

    /// Toggles speech - stops if speaking, or speaks the provided text
    func toggle(text: String) {
        if isSpeaking {
            stop()
        } else {
            speak(text)
        }
    }

    // MARK: - Settings

    /// Saves settings to UserDefaults
    func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: "kai_speech_enabled")
        UserDefaults.standard.set(autoSpeakForVoiceInput, forKey: "kai_speech_auto_voice")
        UserDefaults.standard.set(speechRate, forKey: "kai_speech_rate")
        UserDefaults.standard.set(speechPitch, forKey: "kai_speech_pitch")
    }

    /// Loads settings from UserDefaults
    private func loadSettings() {
        if UserDefaults.standard.object(forKey: "kai_speech_enabled") != nil {
            isEnabled = UserDefaults.standard.bool(forKey: "kai_speech_enabled")
        }
        if UserDefaults.standard.object(forKey: "kai_speech_auto_voice") != nil {
            autoSpeakForVoiceInput = UserDefaults.standard.bool(forKey: "kai_speech_auto_voice")
        }
        if UserDefaults.standard.object(forKey: "kai_speech_rate") != nil {
            speechRate = UserDefaults.standard.float(forKey: "kai_speech_rate")
        }
        if UserDefaults.standard.object(forKey: "kai_speech_pitch") != nil {
            speechPitch = UserDefaults.standard.float(forKey: "kai_speech_pitch")
        }
    }

    // MARK: - Private Methods

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[SpeechService] Failed to configure audio session: \(error)")
            #endif
        }
    }

    /// Cleans text for better speech output
    private func cleanTextForSpeech(_ text: String) -> String {
        var cleaned = text

        // Remove markdown formatting
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        cleaned = cleaned.replacingOccurrences(of: "__", with: "")
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")
        cleaned = cleaned.replacingOccurrences(of: "_", with: "")
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")

        // Remove markdown links but keep the text
        let linkPattern = "\\[([^\\]]+)\\]\\([^)]+\\)"
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: "$1"
            )
        }

        // Remove bullet points
        cleaned = cleaned.replacingOccurrences(of: "- ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "• ", with: "")

        // Clean up extra whitespace
        cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return cleaned
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentUtterance = nil

            // Deactivate audio session
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentUtterance = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }
}
