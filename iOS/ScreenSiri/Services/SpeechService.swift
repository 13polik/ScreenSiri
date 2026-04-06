import AVFoundation
import Speech
import Combine

// MARK: - SpeechService
//
// Handles both Text-to-Speech (AVSpeechSynthesizer) and
// Speech-to-Text (SFSpeechRecognizer) for the voice-first UX.

@MainActor
final class SpeechService: NSObject, ObservableObject {

    static let shared = SpeechService()

    // MARK: Published

    @Published private(set) var isSpeaking = false
    @Published private(set) var isListening = false
    @Published private(set) var transcribedText = ""

    // MARK: TTS

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: STT

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private override init() {
        super.init()
        synthesizer.delegate = self
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Text-to-Speech

    func speak(_ text: String) async {
        stopSpeaking()

        await withCheckedContinuation { continuation in
            let utterance          = AVSpeechUtterance(string: text)
            utterance.rate         = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
            utterance.voice        = AVSpeechSynthesisVoice(language: "en-US")
            utterance.postUtteranceDelay = 0.1

            isSpeaking = true

            // Use a one-shot completion via delegate
            synthesizer.speak(utterance)

            // Poll until done (delegate updates isSpeaking)
            Task {
                while self.isSpeaking {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                continuation.resume()
            }
        }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - Speech-to-Text

    /// Requests microphone + speech recognition permissions
    func requestPermissions() async -> Bool {
        // Microphone
        let micStatus = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard micStatus else { return false }

        // Speech recognition
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        return speechStatus
    }

    /// Listens for a question and returns the transcribed text.
    /// Automatically stops after `timeout` seconds of silence, or when speech ends.
    func listenForQuestion(timeout: TimeInterval = 8.0) async throws -> String {
        guard !isListening else { throw SpeechError.alreadyListening }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        transcribedText = ""
        isListening = true

        defer {
            stopListening()
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
                guard let request = recognitionRequest else {
                    throw SpeechError.requestFailed
                }

                request.shouldReportPartialResults = true
                request.taskHint = .dictation

                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                var lastTranscript = ""
                var silenceTimer: Timer?

                recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    if let result = result {
                        lastTranscript = result.bestTranscription.formattedString
                        self?.transcribedText = lastTranscript

                        // Reset silence timer on new speech
                        silenceTimer?.invalidate()

                        if result.isFinal {
                            continuation.resume(returning: lastTranscript)
                            return
                        }

                        // Auto-stop after 2s of silence
                        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                            if !lastTranscript.isEmpty {
                                continuation.resume(returning: lastTranscript)
                            }
                        }
                    }

                    if let error = error {
                        if !lastTranscript.isEmpty {
                            continuation.resume(returning: lastTranscript)
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }

                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    request.append(buffer)
                }

                audioEngine.prepare()
                try audioEngine.start()

                // Hard timeout
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if !lastTranscript.isEmpty {
                        continuation.resume(returning: lastTranscript)
                    } else {
                        continuation.resume(throwing: SpeechError.timeout)
                    }
                }

            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}

// MARK: - SpeechError

enum SpeechError: Error, LocalizedError {
    case alreadyListening
    case recognizerUnavailable
    case requestFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .alreadyListening:      return "Already listening."
        case .recognizerUnavailable: return "Speech recognizer is unavailable."
        case .requestFailed:         return "Failed to start recognition request."
        case .timeout:               return "No speech detected."
        }
    }
}
