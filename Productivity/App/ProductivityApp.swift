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
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .accessibilityLabel("Flowlog")
    }
}

private struct MenuBarMenu: View {
    @Bindable var appState: AppState
    @ObservedObject private var coordinator = TrackingCoordinator.shared
    @Environment(\.openWindow) private var openWindow
    @State private var now = Date()

    var body: some View {
        Group {
            if let session = coordinator.menuBarSession {
                MenuBarSessionHeader(info: session, now: now)
                    .disabled(true)
                Divider()
            }

            MenuBarTodaySection()
                .disabled(true)
                .padding(.horizontal, 12)
            Divider()

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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
        .onReceive(NotificationCenter.default.publisher(for: .productivityDataDidChange)) { _ in
            coordinator.refreshMenuBarSession()
        }
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
