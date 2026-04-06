import ReplayKit
import UIKit
import Combine

// MARK: - SessionManager
//
// CRITICAL: Manages the ReplayKit screen recording session.
// The session is started ONCE and kept alive until the user explicitly stops it.
// Never stop ReplayKit between assistant interactions — the permission prompt
// would reappear, breaking the Siri-like UX.

@MainActor
final class SessionManager: NSObject, ObservableObject {

    static let shared = SessionManager()

    // MARK: Published State

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var errorMessage: String?

    // MARK: Private

    private let recorder = RPScreenRecorder.shared()
    private(set) var latestFrame: UIImage?
    private var frameSubject = PassthroughSubject<UIImage, Never>()

    /// Subscribe to this to receive new frames as they arrive
    var framePublisher: AnyPublisher<UIImage, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    private override init() {
        super.init()
        recorder.delegate = self
    }

    // MARK: - Public API

    /// Starts the screen recording session. Safe to call multiple times — is a no-op if already active.
    func startSession() async throws {
        guard state == .idle || state == .error else { return }
        guard recorder.isAvailable else {
            throw SessionError.notAvailable
        }

        state = .starting

        return try await withCheckedThrowingContinuation { continuation in
            recorder.startCapture(
                handler: { [weak self] sampleBuffer, bufferType, error in
                    if let error = error {
                        // Only report errors during active capture — not on first frame
                        if self?.state == .active {
                            Task { @MainActor in
                                self?.state = .error
                                self?.errorMessage = error.localizedDescription
                            }
                        }
                        return
                    }
                    guard bufferType == .video else { return }
                    self?.processFrame(sampleBuffer)
                },
                completionHandler: { [weak self] error in
                    Task { @MainActor in
                        if let error = error {
                            self?.state = .error
                            self?.errorMessage = error.localizedDescription
                            continuation.resume(throwing: error)
                        } else {
                            self?.state = .active
                            continuation.resume()
                        }
                    }
                }
            )
        }
    }

    /// Stops the session. Should only be called when the user explicitly ends the session.
    func stopSession() async {
        guard state == .active || state == .starting else { return }
        state = .stopping

        await withCheckedContinuation { continuation in
            recorder.stopCapture { [weak self] error in
                Task { @MainActor in
                    self?.state = .idle
                    self?.latestFrame = nil
                    continuation.resume()
                }
            }
        }
    }

    /// Returns the most recently captured frame. Grabs a fresh frame snapshot.
    func captureCurrentFrame() -> UIImage? {
        return latestFrame
    }

    // MARK: - Frame Processing

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let image = UIImage(cgImage: cgImage)
        let quality = AppSettings.shared.captureQuality
        let downscaled = image.downscaled(to: quality.targetSize)

        // Update latest frame on main thread
        Task { @MainActor in
            self.latestFrame = downscaled
            self.frameSubject.send(downscaled)
        }
    }
}

// MARK: - RPScreenRecorderDelegate

extension SessionManager: RPScreenRecorderDelegate {
    nonisolated func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        Task { @MainActor in
            if !screenRecorder.isAvailable && self.state == .active {
                self.state = .error
                self.errorMessage = "Screen recording became unavailable."
            }
        }
    }

    nonisolated func screenRecorder(_ screenRecorder: RPScreenRecorder,
                                    didStopRecordingWith previewViewController: RPPreviewViewController?,
                                    error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.state = .error
                self.errorMessage = error.localizedDescription
            } else {
                self.state = .idle
            }
        }
    }
}

// MARK: - SessionState

enum SessionState: Equatable {
    case idle
    case starting
    case active
    case stopping
    case error

    var displayName: String {
        switch self {
        case .idle:     return "Ready"
        case .starting: return "Starting…"
        case .active:   return "Session Active"
        case .stopping: return "Stopping…"
        case .error:    return "Error"
        }
    }

    var isActive: Bool { self == .active }
}

// MARK: - SessionError

enum SessionError: Error, LocalizedError {
    case notAvailable
    case noFrameAvailable
    case sessionNotActive

    var errorDescription: String? {
        switch self {
        case .notAvailable:      return "Screen recording is not available on this device."
        case .noFrameAvailable:  return "No screen frame available yet. Please wait a moment."
        case .sessionNotActive:  return "No active session. Please start a session first."
        }
    }
}

// MARK: - UIImage Extension

extension UIImage {
    /// Downscales the image to fit within targetSize while maintaining aspect ratio
    func downscaled(to targetSize: CGSize) -> UIImage {
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let ratio       = min(widthRatio, heightRatio)

        // Don't upscale
        guard ratio < 1.0 else { return self }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Encodes to base64 JPEG string
    func base64JPEG(quality: CGFloat = 0.7) -> String? {
        return jpegData(compressionQuality: quality)?.base64EncodedString()
    }
}
