import AVFoundation
import Speech
import Combine

// MARK: - SpeechService
//
// Handles Text-to-Speech (AVSpeechSynthesizer) and Speech-to-Text (SFSpeechRecognizer).
//
// Key safety invariants:
//   • `isTapInstalled` guards every removeTap call — prevents CFRelease(NULL) crash.
//   • `resumeOnce` is a one-shot gate so only the first result/error/timeout wins.
//   • All recognition callbacks are marshalled back to MainActor before touching state.

@MainActor
final class SpeechService: NSObject, ObservableObject {

    static let shared = SpeechService()

    // MARK: Published

    @Published private(set) var isSpeaking  = false
    @Published private(set) var isListening = false
    @Published private(set) var transcribedText = ""

    // MARK: Private state

    private let synthesizer     = AVSpeechSynthesizer()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private let audioEngine     = AVAudioEngine()

    /// Tracks whether a tap is currently installed on the input node.
    /// Guards every removeTap call to prevent CFRelease(NULL) crashes.
    private var isTapInstalled  = false

    private override init() {
        super.init()
        synthesizer.delegate = self
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Text-to-Speech

    func speak(_ text: String) async {
        stopSpeaking()

        await withCheckedContinuation { continuation in
            let utterance             = AVSpeechUtterance(string: text)
            utterance.rate            = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
            utterance.voice           = AVSpeechSynthesisVoice(language: "en-US")
            utterance.postUtteranceDelay = 0.1

            isSpeaking = true
            synthesizer.speak(utterance)

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

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let micGranted = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else { return false }

        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization {
                cont.resume(returning: $0 == .authorized)
            }
        }
    }

    // MARK: - Speech-to-Text

    func listenForQuestion(timeout: TimeInterval = 8.0) async throws -> String {
        guard !isListening else { throw SpeechError.alreadyListening }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        transcribedText = ""
        isListening     = true

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: SpeechError.requestFailed)
                return
            }

            // ── One-shot gate ─────────────────────────────────────────────────
            // All competing paths (isFinal result / silence timer / hard timeout /
            // error) call through gate.tryFire(). Only the first returns true;
            // the rest are dropped. stopListening() is hopped to MainActor.
            let gate = OnceFire()

            func finishOnce(returning text: String) {
                guard gate.tryFire() else { return }
                Task { @MainActor in self.stopListening() }
                continuation.resume(returning: text)
            }

            func finishOnce(throwing error: Error) {
                guard gate.tryFire() else { return }
                Task { @MainActor in self.stopListening() }
                continuation.resume(throwing: error)
            }

            do {
                // 1. Activate audio session BEFORE reading inputNode format.
                //    Without this, outputFormat can return sampleRate == 0.
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                // 2. Build recognition request.
                let request = SFSpeechAudioBufferRecognitionRequest()
                self.recognitionRequest = request
                request.shouldReportPartialResults = true
                request.taskHint = .dictation

                // 3. Get format after session is active.
                let inputNode = self.audioEngine.inputNode
                let format    = inputNode.outputFormat(forBus: 0)

                guard format.sampleRate > 0 else {
                    throw SpeechError.requestFailed
                }

                // 4. Recognition task — callback on arbitrary background thread,
                //    so dispatch to main for safe flag/state access.
                var lastTranscript = ""
                var silenceTimer: Timer?

                self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                    DispatchQueue.main.async {
                        if let result {
                            lastTranscript          = result.bestTranscription.formattedString
                            self.transcribedText    = lastTranscript
                            silenceTimer?.invalidate()

                            if result.isFinal {
                                finishOnce(returning: lastTranscript)
                                return
                            }

                            // Auto-finish after 2 s of silence
                            silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0,
                                                                repeats: false) { _ in
                                if !lastTranscript.isEmpty {
                                    finishOnce(returning: lastTranscript)
                                }
                            }
                        }

                        if let error {
                            if !lastTranscript.isEmpty {
                                finishOnce(returning: lastTranscript)
                            } else {
                                finishOnce(throwing: error)
                            }
                        }
                    }
                }

                // 5. Install audio tap — guard with flag so removeTap is safe.
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    request.append(buffer)
                }
                self.isTapInstalled = true

                self.audioEngine.prepare()
                try self.audioEngine.start()

                // 6. Hard timeout — runs on MainActor so `fired` access is safe.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if !lastTranscript.isEmpty {
                        finishOnce(returning: lastTranscript)
                    } else {
                        finishOnce(throwing: SpeechError.timeout)
                    }
                }

            } catch {
                isListening = false
                continuation.resume(throwing: error)
            }
        }
    }

    /// Tears down the audio pipeline safely.
    /// Guards every operation so it is safe to call even if nothing was started.
    func stopListening() {
        // Stop engine first, then remove tap — order matters.
        if audioEngine.isRunning { audioEngine.stop() }

        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask    = nil
        isListening        = false

        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: - OnceFire
// Thread-safe one-shot gate. The first call to `tryFire()` returns true;
// all subsequent calls return false. Used to ensure a continuation is
// resumed exactly once regardless of which race (result / silence / timeout / error) wins.

private final class OnceFire: @unchecked Sendable {
    private let lock = NSLock()
    private var _fired = false

    func tryFire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !_fired else { return false }
        _fired = true
        return true
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
