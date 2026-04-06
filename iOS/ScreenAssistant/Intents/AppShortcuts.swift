import AppIntents

// MARK: - ScreenSiriShortcuts
//
// Registers App Shortcuts that appear automatically in the Shortcuts app
// and can be triggered via Siri without the user manually creating a Shortcut.
//
// Siri phrases registered here work out of the box after install.
// Users can also assign custom phrases in the Shortcuts app.

@available(iOS 16.4, *)
struct ScreenSiriShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {

        // ── 1. Ask About Screen ──────────────────────────────────────────────
        AppShortcut(
            intent: AssistMeIntent(),
            phrases: [
                "Help me here with \(.applicationName)",
                "Ask about my screen with \(.applicationName)",
                "What's on my screen with \(.applicationName)",
                "Analyze screen with \(.applicationName)",
                "Guide me with \(.applicationName)"
            ],
            shortTitle: "Ask About Screen",
            systemImageName: "eye.fill"
        )

        // ── 2. Quick Summarize ───────────────────────────────────────────────
        AppShortcut(
            intent: SummarizeScreenIntent(),
            phrases: [
                "Summarize my screen with \(.applicationName)",
                "What am I looking at with \(.applicationName)",
                "Describe my screen with \(.applicationName)"
            ],
            shortTitle: "Summarize Screen",
            systemImageName: "doc.text.viewfinder"
        )

        // ── 3. Start Session ─────────────────────────────────────────────────
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Begin \(.applicationName) session",
                "Activate \(.applicationName)"
            ],
            shortTitle: "Start Session",
            systemImageName: "play.circle.fill"
        )
    }
}

// MARK: - Usage Notes
//
// After install, users can say:
//   "Hey Siri, help me here with ScreenSiri"
//   "Hey Siri, what's on my screen with ScreenSiri"
//   "Hey Siri, summarize my screen with ScreenSiri"
//
// For a shorter phrase, users can create a custom Shortcut in the Shortcuts
// app and set it to "help me here" or any phrase they prefer.
//
// BACK TAP SETUP:
//   Settings → Accessibility → Touch → Back Tap → Double Tap
//   → Select the "Ask About Screen" shortcut
//   Then double-tap the back of the phone from any app!
