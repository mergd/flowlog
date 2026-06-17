import AppKit
import SwiftUI

@MainActor
enum DashboardWindowHost {
    private static var controller: NSWindowController?

    static func present(appState: AppState) {
        if controller == nil {
            let rootView = DashboardWindow(appState: appState)
                .hiddenTitleBar(id: "dashboard")

            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            WindowChrome.apply(to: window, id: "dashboard")

            let size = NSSize(
                width: DashboardTheme.defaultWidth,
                height: DashboardTheme.defaultHeight
            )
            window.minSize = NSSize(
                width: DashboardTheme.minWidth,
                height: DashboardTheme.minHeight
            )
            window.setContentSize(size)
            window.center()
            window.isReleasedWhenClosed = false
            controller = NSWindowController(window: window)
        }

        if let window = controller?.window {
            WindowChrome.apply(to: window, id: "dashboard")
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
        controller?.window?.orderFrontRegardless()
    }

    static func isVisible() -> Bool {
        controller?.window?.isVisible == true
    }
}
