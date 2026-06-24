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

final class WindowChromeObserverView: NSView {
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

    /// Keeps sidebar list items below the traffic lights while the sidebar
    /// background extends under them.
    func sidebarTitleBarInset() -> some View {
        modifier(SidebarTitleBarInsetModifier())
    }
}

private struct SidebarTitleBarInsetModifier: ViewModifier {
    @State private var titleBarInset: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .background(WindowTitleBarInsetReader(inset: $titleBarInset))
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: titleBarInset)
            }
    }
}

private struct WindowTitleBarInsetReader: NSViewRepresentable {
    @Binding var inset: CGFloat

    func makeNSView(context: Context) -> WindowTitleBarInsetView {
        WindowTitleBarInsetView(inset: $inset)
    }

    func updateNSView(_ nsView: WindowTitleBarInsetView, context: Context) {
        nsView.inset = $inset
        nsView.refresh()
    }
}

private final class WindowTitleBarInsetView: NSView {
    var inset: Binding<CGFloat>

    init(inset: Binding<CGFloat>) {
        self.inset = inset
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func layout() {
        super.layout()
        refresh()
    }

    func refresh() {
        guard let window else { return }
        let measured = max(0, window.frame.height - window.contentLayoutRect.height)
        let resolved = measured > 0 ? measured : 28
        if abs(inset.wrappedValue - resolved) > 0.5 {
            inset.wrappedValue = resolved
        }
    }
}
