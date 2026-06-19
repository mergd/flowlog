import AppKit
import SwiftUI

@MainActor
enum OnboardingWindowHost {
    private static var controller: NSWindowController?

    static func present(appState: AppState) {
        if controller == nil {
            let hostingController = NSHostingController(
                rootView: OnboardingView(appState: appState)
                    .hiddenTitleBar(id: "onboarding")
            )
            let window = NSWindow(contentViewController: hostingController)
            WindowChrome.apply(to: window, id: "onboarding")
            window.styleMask.remove(.resizable)
            window.setContentSize(NSSize(width: 420, height: 368))
            window.center()
            window.isReleasedWhenClosed = false
            controller = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        controller?.showWindow(nil)
        controller?.window?.flowlogEnsureVisible()
        controller?.window?.makeKeyAndOrderFront(nil)
        controller?.window?.orderFrontRegardless()
    }

    static func isVisible() -> Bool {
        controller?.window?.isVisible == true
    }
}
