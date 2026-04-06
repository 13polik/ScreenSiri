import Foundation
import Combine

// MARK: - AppSettings
// Persists user configuration in UserDefaults.
// Injected as an @EnvironmentObject throughout the app.

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: Stored Properties

    @Published var backendURL: String {
        didSet { UserDefaults.standard.set(backendURL, forKey: Keys.backendURL) }
    }

    /// Direct OpenAI key — stored in Keychain (never plain UserDefaults)
    @Published var openAIKey: String {
        didSet { KeychainService.save(openAIKey, key: Keys.openAIKey) }
    }

    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: Keys.selectedModel) }
    }

    @Published var voiceEnabled: Bool {
        didSet { UserDefaults.standard.set(voiceEnabled, forKey: Keys.voiceEnabled) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    @Published var captureQuality: CaptureQuality {
        didSet { UserDefaults.standard.set(captureQuality.rawValue, forKey: Keys.captureQuality) }
    }

    // MARK: Init

    private init() {
        self.backendURL        = UserDefaults.standard.string(forKey: Keys.backendURL) ?? "http://localhost:8000"

        // Load from Keychain; migrate legacy UserDefaults value on first run
        if let keychainKey = KeychainService.load(key: Keys.openAIKey) {
            self.openAIKey = keychainKey
        } else if let legacyKey = UserDefaults.standard.string(forKey: Keys.openAIKey), !legacyKey.isEmpty {
            KeychainService.save(legacyKey, key: Keys.openAIKey)
            UserDefaults.standard.removeObject(forKey: Keys.openAIKey)
            self.openAIKey = legacyKey
        } else {
            self.openAIKey = ""
        }
        self.selectedModel     = UserDefaults.standard.string(forKey: Keys.selectedModel) ?? "gpt-4o"
        self.voiceEnabled      = UserDefaults.standard.bool(forKey: Keys.voiceEnabled)
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)
        let qualityRaw         = UserDefaults.standard.string(forKey: Keys.captureQuality) ?? CaptureQuality.medium.rawValue
        self.captureQuality    = CaptureQuality(rawValue: qualityRaw) ?? .medium
    }

    // MARK: Keys

    private enum Keys {
        static let backendURL            = "backend_url"
        static let openAIKey             = "openai_api_key"
        static let selectedModel         = "selected_model"
        static let voiceEnabled          = "voice_enabled"
        static let hasCompletedOnboarding = "has_completed_onboarding"
        static let captureQuality        = "capture_quality"
    }

    // MARK: Helpers

    var isConfigured: Bool {
        !backendURL.isEmpty || !openAIKey.isEmpty
    }
}

// MARK: - Capture Quality

enum CaptureQuality: String, CaseIterable, Identifiable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:    return "Low (faster, less data)"
        case .medium: return "Medium (recommended)"
        case .high:   return "High (best accuracy)"
        }
    }

    /// Target size for downscaling captured frames
    var targetSize: CGSize {
        switch self {
        case .low:    return CGSize(width: 512, height: 910)
        case .medium: return CGSize(width: 768, height: 1366)
        case .high:   return CGSize(width: 1080, height: 1920)
        }
    }

    /// JPEG compression quality (0–1)
    var compressionQuality: CGFloat {
        switch self {
        case .low:    return 0.5
        case .medium: return 0.7
        case .high:   return 0.9
        }
    }
}
