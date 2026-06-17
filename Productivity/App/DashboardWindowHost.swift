import AppKit
import SwiftUI

@MainActor
enum DashboardWindowHost {
    private static var controller: NSWindowController?

    static func present(appState: AppState) {
        if controller == nil {
            let hostingController = NSHostingController(
                rootView: DashboardWindow(appState: appState)
                    .hiddenTitleBar(id: "dashboard")
            )
            let window = NSWindow(contentViewController: hostingController)
            WindowChrome.apply(to: window, id: "dashboard")
            window.minSize = NSSize(
                width: DashboardTheme.minWidth,
                height: DashboardTheme.minHeight
            )
            window.setContentSize(NSSize(
                width: DashboardTheme.defaultWidth,
                height: DashboardTheme.defaultHeight
            ))
            window.center()
            window.isReleasedWhenClosed = false
            controller = NSWindowController(window: window)
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
