import AppKit
import SwiftUI

@main
struct ProductivityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        Window("", id: "dashboard") {
            DashboardWindow(appState: appState)
                .hiddenTitleBar(id: "dashboard")
                .background(WindowRegistration())
        }
        .defaultSize(width: DashboardTheme.defaultWidth, height: DashboardTheme.defaultHeight)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    SparkleUpdater.checkForUpdates()
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("Open Flowlog") {
                    WindowPresenter.openDashboard()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Setup") {
                Button("Show Setup") {
                    AppSettings.shared.hasCompletedOnboarding = false
                    AppSettings.shared.onboardingResumeStep = nil
                    AppState.shared.syncOnboardingState()
                    AppState.shared.presentOnboarding()
                }
            }
        }

        Window("", id: "onboarding") {
            OnboardingView(appState: appState)
                .hiddenTitleBar(id: "onboarding")
                .background(WindowRegistration())
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 368)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(appState.showOnboarding ? .presented : .suppressed)

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarPanel(appState: appState)
                .background(WindowRegistration())
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .background(WindowRegistration())
        }
    }

    init() {
        AppleClassifier.shared.refreshAvailability()
        AppState.shared.bootstrap()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppleClassifier.shared.refreshAvailability()
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject private var coordinator = TrackingCoordinator.shared

    var body: some View {
        ring
            .accessibilityLabel(coordinator.isSnoozed ? "Flowlog — paused" : "Flowlog")
    }

    @ViewBuilder
    private var ring: some View {
        let base = Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()

        if coordinator.isSnoozed {
            // The "zzz" glyph is ~3× wider than a single letter, so it won't fit as a
            // corner badge inside an 18pt icon (it gets clipped, and blends into the
            // logo at the same menu-bar tint). Widen the item and set it beside a
            // dimmed logo so the whole sleep glyph is legible.
            HStack(spacing: 1.5) {
                base
                    .opacity(0.45)
                    .frame(width: 16, height: 16)
                Image(systemName: "zzz")
                    .renderingMode(.template)
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(height: 18)
        } else {
            base.frame(width: 18, height: 18)
        }
    }
}
