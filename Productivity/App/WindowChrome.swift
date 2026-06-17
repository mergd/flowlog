import AppKit

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
        window.toolbar = nil
    }
}
