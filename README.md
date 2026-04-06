# ScreenSiri

A Siri-style AI assistant for iOS that feels like a system overlay. Bring it up from any app via a Siri phrase, Back Tap, or the in-app button — ask a question by voice or text — get a streaming GPT-4o response.

Built entirely in SwiftUI with no third-party dependencies.

---

## What it does

- **Siri & Shortcuts integration** — say *"Hey Siri, help me here with ScreenSiri"* from any app
- **Back Tap trigger** — double-tap the back of your iPhone (Settings → Accessibility → Touch → Back Tap)
- **Screen-aware** — optionally start a screen recording session so the AI can see what's on your screen
- **Streaming chat** — text responses stream token-by-token in real time
- **Voice I/O** — speak your question; the assistant reads the answer back
- **Session memory** — the assistant remembers context across turns within a session
- **Secure key storage** — your OpenAI API key is stored in the iOS Keychain, never in plain text

---

## Requirements

- Xcode 15+ (project targets iOS 16.4+)
- An iPhone running iOS 16.4 or later
- An OpenAI API key from [platform.openai.com](https://platform.openai.com)

> The app requires a physical device for screen recording. ReplayKit does not work in the simulator.

---

## Build & Run

```bash
git clone https://github.com/YOUR_USERNAME/screensiri.git
```

1. Open `iOS/ScreenAssistant/ScreenAssistant.xcodeproj` in Xcode
2. Select your device in the toolbar → **Cmd+R**
3. On first launch, grant mic + speech permissions, then paste your OpenAI key on the Settings tab

---

## Architecture

```
ScreenAssistant/
├── App/
│   └── ScreenSiriApp.swift          # Entry point, injects environment objects
├── Intents/
│   ├── AppShortcuts.swift           # Registers Siri phrases via AppShortcutsProvider
│   └── AssistMeIntent.swift         # App Intent powering Siri / Shortcuts
├── Managers/
│   ├── InteractionManager.swift     # Orchestrates voice/text → AI → speech loop
│   ├── SessionManager.swift         # ReplayKit screen recording lifecycle
│   └── MemoryManager.swift          # In-session conversation memory
├── Models/
│   ├── ChatMessage.swift            # Value type for chat bubbles
│   ├── AppSettings.swift            # User preferences (UserDefaults)
│   └── SessionMemory.swift          # Cross-turn memory model
├── Services/
│   ├── AIClient.swift               # OpenAI chat completions + streaming
│   ├── KeychainService.swift        # Secure API key storage
│   └── SpeechService.swift          # AVSpeechSynthesizer TTS + SFSpeechRecognizer STT
└── Views/
    ├── ContentView.swift            # Root shell — TabView + overlay
    ├── AssistantPanelView.swift     # The Siri-style bottom panel
    ├── HomeView.swift               # Dashboard — session controls, quick actions
    ├── OnboardingView.swift         # First-launch permissions + API key setup
    └── SettingsView.swift           # Key management, voice toggle, model picker
```

---

## How It Works

1. User triggers via Siri phrase, Back Tap, or in-app button
2. `AssistMeIntent` fires → `InteractionManager.handleInteraction()` is called
3. If a screen session is active, the current frame is captured via ReplayKit
4. The user speaks → `SpeechService` transcribes it
5. `AIClient` streams the response from OpenAI token-by-token
6. `SpeechService` reads the response aloud; `MemoryManager` stores it for context

---

## Notes & Limitations

- iOS sandbox prevents true system-level overlays — the panel appears within the app
- Screen recording requires explicit user permission each session (red dot in status bar is expected)
- Text-only chat works fine without an active screen session

---

## License

MIT
