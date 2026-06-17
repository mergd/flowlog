# Flowlog

Native macOS menu bar app for tracking time, focus, and productivity.

## Copy

- Do not use em dashes in user-facing copy. Use periods, commas, or colons instead.
- Keep onboarding and UI text minimal, left-aligned, and plain.
- App name is **Flowlog** (`AppInfo.name`).

## UI

- Prefer minimal macOS-native patterns: hidden title bars, left-aligned onboarding, no unnecessary chrome.
- Onboarding welcome: app icon on top, name and copy below it.
- Do not add manual restart/check-again flows for permissions; macOS handles relaunch prompts.
- Persist onboarding progress (`onboardingResumeStep`) so a relaunch after granting permissions can skip ahead to the next incomplete step.

## Code

- Swift 6, macOS 26 target, unsandboxed.
- Do not run or push DB migrations unless explicitly asked.
- Prefer migrations over ad-hoc schema changes; clear schema before implementing DB changes.
- Avoid dynamic imports unless required.
- Import hooks directly (`useEffect`, not `React.useEffect`).

## Project layout

- `Productivity/App/` — entry, window presentation, app state
- `Productivity/Views/` — SwiftUI views
- `Productivity/Tracking/` — workspace monitor, sessions, screenshots
- `Productivity/Classification/` — rules + LLM classifiers
- `Productivity/Storage/` — GRDB + screenshot store
