import AppKit
import SwiftUI

@main
struct ProductivityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

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
                WindowRegistration()
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

        MenuBarExtra {
            MenuBarPanel(appState: appState)
                .background(WindowRegistration())
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)

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
    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .accessibilityLabel("Flowlog")
    }
}
