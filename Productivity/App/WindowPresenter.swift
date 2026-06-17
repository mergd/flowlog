import AppKit
import SwiftUI

@MainActor
enum WindowPresenter {
    private static var openOnboardingWindow: (() -> Void)?
    private static var openDashboardWindow: (() -> Void)?
    private static var pendingOnboardingOpen = false
    private static var pendingDashboardOpen = false

    static func register(
        openOnboarding: @escaping () -> Void,
        openDashboard: @escaping () -> Void
    ) {
        openOnboardingWindow = openOnboarding
        openDashboardWindow = openDashboard

        if pendingOnboardingOpen, AppState.shared.showOnboarding {
            pendingOnboardingOpen = false
            openOnboarding()
        } else {
            pendingOnboardingOpen = false
        }

        if pendingDashboardOpen || AppState.shared.showDashboard {
            pendingDashboardOpen = false
            openDashboard()
        }
    }

    static func openOnboarding() {
        guard openOnboardingWindow != nil else {
            pendingOnboardingOpen = true
            return
        }
        guard let app = NSApp else { return }
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        openOnboardingWindow?()
        bringOnboardingWindowToFront()
    }

    static func openDashboard() {
        guard openDashboardWindow != nil else {
            pendingDashboardOpen = true
            DashboardWindowHost.present(appState: AppState.shared)
            return
        }
        guard let app = NSApp else { return }
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        openDashboardWindow?()
        bringDashboardWindowToFront()

        if !NSApp.windows.contains(where: { $0.matches(id: "dashboard") && $0.isVisible }) {
            DashboardWindowHost.present(appState: AppState.shared)
        }
    }

    static func returnToMenuBarMode() {
        NSApp?.setActivationPolicy(.accessory)
    }

    private static func bringOnboardingWindowToFront() {
        guard let app = NSApp else { return }
        for window in app.windows where window.matches(id: "onboarding") {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
    }

    private static func bringDashboardWindowToFront() {
        guard let app = NSApp else { return }
        for window in app.windows where window.matches(id: "dashboard") {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
    }
}

private extension NSWindow {
    func matches(id: String) -> Bool {
        identifier?.rawValue == id || title == id
    }
}

struct HiddenTitleBar: ViewModifier {
    let windowID: String

    func body(content: Content) -> some View {
        content.observeWindowChrome(id: windowID)
    }
}

extension View {
    func hiddenTitleBar(id: String) -> some View {
        modifier(HiddenTitleBar(windowID: id))
    }
}

struct WindowRegistration: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                WindowPresenter.register(
                    openOnboarding: { openWindow(id: "onboarding") },
                    openDashboard: { openWindow(id: "dashboard") }
                )
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if AppState.shared.showOnboarding {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            WindowPresenter.openOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppState.shared.showOnboarding {
            WindowPresenter.openOnboarding()
        } else {
            WindowPresenter.openDashboard()
        }
        return true
    }
}
