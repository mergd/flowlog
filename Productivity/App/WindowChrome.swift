import AppKit
import SwiftUI

enum WindowChrome {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var configuredWindowIDs = Set<ObjectIdentifier>()

    static func apply(to window: NSWindow, id: String) {
        let key = ObjectIdentifier(window)
        lock.lock()
        let alreadyConfigured = configuredWindowIDs.contains(key)
        if !alreadyConfigured {
            configuredWindowIDs.insert(key)
        }
        lock.unlock()

        if alreadyConfigured {
            if window.identifier?.rawValue != id {
                window.identifier = NSUserInterfaceItemIdentifier(id)
            }
            return
        }

        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.isOpaque = true
    }
}

struct WindowChromeObserver: NSViewRepresentable {
    let windowID: String

    func makeNSView(context: Context) -> WindowChromeObserverView {
        WindowChromeObserverView(windowID: windowID)
    }

    func updateNSView(_ nsView: WindowChromeObserverView, context: Context) {
        nsView.windowID = windowID
        nsView.applyIfNeeded()
    }
}

private final class WindowChromeObserverView: NSView {
    var windowID: String

    init(windowID: String) {
        self.windowID = windowID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyIfNeeded()
    }

    func applyIfNeeded() {
        guard let window else { return }
        WindowChrome.apply(to: window, id: windowID)
    }
}

extension View {
    func observeWindowChrome(id: String) -> some View {
        background(WindowChromeObserver(windowID: id))
    }
}
