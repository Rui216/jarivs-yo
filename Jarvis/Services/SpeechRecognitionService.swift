//
//  SpeechRecognitionService.swift
//  JARVIS
//
//  Turns the microphone button into text for the assistant input field.
//  The microphone is opened only while listening, audio is handed to
//  Apple's speech framework for live transcription, and nothing is
//  written to disk.
//

import Foundation
import AVFoundation
import Speech
import os

/// Live dictation for the assistant input field.
@MainActor
@Observable
final class SpeechRecognitionService {

    /// True while the microphone is capturing.
    private(set) var isListening = false

    /// Best transcription so far in the current session.
    private(set) var transcript = ""

    /// Input level between 0 and 1, used to animate the microphone button.
    private(set) var inputLevel: Double = 0

    /// Message describing why dictation could not start.
    private(set) var errorMessage: String?

    /// Called whenever the transcript changes.
    var onTranscriptChange: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Speech")

    // MARK: - Control

    /// Starts dictation, requesting the microphone and speech permissions
    /// the first time it runs.
    func start() async {
        guard !isListening else { return }
        errorMessage = nil
        transcript = ""

        guard await hasPermission() else {
            errorMessage = "Microphone or speech recognition access was declined. Enable it in System Settings, Privacy and Security."
            return
        }

        let locale = Locale.current
        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available for \(locale.identifier) right now."
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            errorMessage = "No microphone input device is available."
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.level(of: buffer)
            Task { @MainActor in
                self?.inputLevel = level
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    self.onTranscriptChange?(text)
                }
                if let error, !resultIsEmpty(error) {
                    self.errorMessage = error.localizedDescription
                    self.stop()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            logger.debug("Dictation started")
        } catch {
            logger.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            errorMessage = "The microphone could not be started: \(error.localizedDescription)"
            stop()
        }
    }

    /// Stops dictation and releases the microphone.
    func stop() {
        guard isListening || recognitionTask != nil else { return }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        inputLevel = 0
        logger.debug("Dictation stopped")
    }

    /// Starts dictation when idle, stops it when already listening.
    func toggle() async {
        if isListening {
            stop()
        } else {
            await start()
        }
    }

    // MARK: - Permissions

    private func hasPermission() async -> Bool {
        let microphoneGranted = await requestMicrophone()
        guard microphoneGranted else { return false }
        return await requestSpeech()
    }

    private func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func requestSpeech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }

    // MARK: - Helpers

    /// Root mean square level of a buffer, mapped to 0 through 1.
    private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, 0.000_000_1))
        let normalized = (Double(decibels) + 60) / 60
        return min(max(normalized, 0), 1)
    }

    /// True when a recognition error is only an empty result notification.
    private static func resultIsEmpty(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("no speech") || description.contains("cancelled")
    }
}
