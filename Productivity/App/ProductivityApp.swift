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
            MenuBarMenu(appState: appState)
        } label: {
            MenuBarLabel(scorePercent: appState.coordinator.menuBarScorePercent)
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
    let scorePercent: Int?

    var body: some View {
        HStack(spacing: 3) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)

            if let scorePercent {
                Text("\(scorePercent)%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .fixedSize()
        .accessibilityLabel(scorePercent.map { "Flowlog, \($0) percent focused" } ?? "Flowlog")
    }
}

private struct MenuBarMenu: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if appState.showOnboarding {
                Button("Continue Setup") {
                    WindowPresenter.openOnboarding()
                }
                Divider()
            }

            Button("Open") {
                WindowPresenter.openDashboard()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .background(WindowRegistration())
        .onChange(of: appState.showDashboard) { _, show in
            guard show else { return }
            if appState.showOnboarding {
                WindowPresenter.openOnboarding()
            } else {
                WindowPresenter.openDashboard()
            }
            appState.showDashboard = false
        }
    }
}
