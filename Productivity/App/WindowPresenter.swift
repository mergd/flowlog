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

        if pendingOnboardingOpen, AppState.shared.showOnboarding, !OnboardingWindowHost.isVisible() {
            pendingOnboardingOpen = false
            openOnboarding()
        } else {
            pendingOnboardingOpen = false
        }

        if (pendingDashboardOpen || AppState.shared.showDashboard), !DashboardWindowHost.isVisible() {
            pendingDashboardOpen = false
            openDashboard()
        } else {
            pendingDashboardOpen = false
        }
    }

    static func openOnboarding() {
        guard openOnboardingWindow != nil else {
            pendingOnboardingOpen = true
            OnboardingWindowHost.present(appState: AppState.shared)
            return
        }
        guard let app = NSApp else { return }
        app.activate(ignoringOtherApps: true)
        openOnboardingWindow?()
        bringOnboardingWindowToFront()

        if !NSApp.windows.contains(where: { $0.matches(id: "onboarding") && $0.isVisible }) {
            OnboardingWindowHost.present(appState: AppState.shared)
        }
    }

    static func openDashboard() {
        pendingDashboardOpen = false
        DashboardWindowHost.present(appState: AppState.shared)
    }

    private static func bringOnboardingWindowToFront() {
        guard let app = NSApp else { return }
        for window in app.windows where window.matches(id: "onboarding") {
            window.flowlogEnsureVisible()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
    }
}

extension NSWindow {
    func flowlogEnsureVisible() {
        if frame.width < 200 || frame.height < 200 {
            setContentSize(NSSize(
                width: DashboardTheme.defaultWidth,
                height: DashboardTheme.defaultHeight
            ))
        }

        guard let screen = screen ?? NSScreen.main else {
            center()
            return
        }

        let visible = screen.visibleFrame
        let frame = self.frame
        let margin: CGFloat = 48
        let offscreen = frame.maxY < visible.minY + margin
            || frame.minY > visible.maxY - margin
            || frame.maxX < visible.minX + margin
            || frame.minX > visible.maxX - margin

        if offscreen {
            center()
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
        // Stay an accessory (menu-bar) app for the whole lifetime. Toggling the
        // activation policy at runtime makes the MenuBarExtra status item reflow
        // and leaves an empty slot beside the icon on the active display.
        NSApp.setActivationPolicy(.accessory)

        // Subscribe early so MetricKit delivers any crash diagnostics batched
        // since the last run. Persists them to Application Support (read with
        // `flowlog crashes`).
        CrashReporter.shared.start()

        // Pop the system Screen Recording prompt if we don't have the grant — a
        // rebuilt binary loses it, and screenshot capture fails silently without it.
        if !Permissions.isScreenRecordingGranted() {
            Permissions.requestScreenRecordingAccess()
        }

        if AppState.shared.showOnboarding {
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
