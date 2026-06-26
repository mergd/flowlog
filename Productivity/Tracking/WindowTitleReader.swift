import AppKit
import ApplicationServices

enum WindowTitleReader {
    /// PIDs we've already nudged into manual accessibility, so we only do it once each.
    private nonisolated(unsafe) static var manualAccessibilityPIDs = Set<pid_t>()
    private static let manualAccessibilityLock = NSLock()

    /// Chromium/Electron apps (Cursor, VS Code, Slack, Discord, …) build their
    /// accessibility tree lazily and expose nothing — including the window title —
    /// until an assistive client asks for it. Setting `AXManualAccessibility` is the
    /// documented opt-in that turns the tree on. It's a harmless no-op for apps that
    /// don't recognize it, so we attempt it once per process.
    private static func enableManualAccessibility(_ appElement: AXUIElement, pid: pid_t) {
        manualAccessibilityLock.lock()
        let alreadyDone = manualAccessibilityPIDs.contains(pid)
        if !alreadyDone { manualAccessibilityPIDs.insert(pid) }
        manualAccessibilityLock.unlock()
        guard !alreadyDone else { return }
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    static func requestAccessibilityTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// TCC flag — can lag behind System Settings until the app restarts.
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Real trust. NOTE: querying our *own* app element succeeds without any
    /// Accessibility grant, so a self-probe is NOT proof of access — only
    /// `AXIsProcessTrusted()` reflects whether we can read *other* apps' windows.
    static func hasAccessibilityAccess() -> Bool {
        isAccessibilityTrusted()
    }

    static func focusedWindowTitle(for app: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        enableManualAccessibility(appElement, pid: app.processIdentifier)
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard result == .success, let window = windowRef, let element = axUIElement(from: window) else { return nil }
        return stringAttribute(kAXTitleAttribute as CFString, on: element)
    }

    /// Canonical URL of the focused browser window, read straight from the
    /// Accessibility tree (no Automation / Apple Events permission needed).
    /// Primary path: the `AXWebArea` element's `AXURL` — the real document URL,
    /// engine-level so it works across Safari and every Chromium browser (incl.
    /// Arc, whose toolbar is custom but whose web area is still Chromium).
    /// Fallback: the address-bar text field's value (display URL).
    static func focusedURL(for app: NSRunningApplication) -> String? {
        focusedURL(forPID: app.processIdentifier)
    }

    /// PID-based variant so the (potentially expensive) AX subtree walk can run
    /// off the main actor — `pid_t` is Sendable, `NSRunningApplication` is not.
    /// The Accessibility API is callable from any thread.
    static func focusedURL(forPID pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        enableManualAccessibility(appElement, pid: pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef, let root = axUIElement(from: window) else { return nil }
        return findBrowserURL(in: root)
    }

    /// Bounded breadth-first walk of the window's AX subtree. Prefers the web
    /// area's URL; remembers the first URL-looking text field as a fallback.
    private static func findBrowserURL(in root: AXUIElement, maxNodes: Int = 2500) -> String? {
        var queue: [AXUIElement] = [root]
        var visited = 0
        var fallback: String?

        while !queue.isEmpty, visited < maxNodes {
            let element = queue.removeFirst()
            visited += 1

            let role = stringAttribute(kAXRoleAttribute as CFString, on: element)
            if role == "AXWebArea", let url = urlAttribute(on: element) {
                return url  // canonical document URL — done.
            }
            if fallback == nil, role == "AXTextField",
               let value = stringAttribute(kAXValueAttribute as CFString, on: element),
               looksLikeURL(value) {
                fallback = value
            }

            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return fallback
    }

    private static func urlAttribute(on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &value) == .success,
              let value else { return nil }
        if let url = value as? URL { return url.absoluteString }
        if let nsurl = value as? NSURL { return nsurl.absoluteString }
        if let string = value as? String { return string }
        return nil
    }

    private static func looksLikeURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return true }
        return trimmed.contains(".") && !trimmed.contains("/")  // bare "github.com"
            || (trimmed.contains(".") && trimmed.contains("/")) // "github.com/foo"
    }

    static func focusedWindowFrame(for app: NSRunningApplication) -> CGRect? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        enableManualAccessibility(appElement, pid: app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef,
              let element = axUIElement(from: window),
              let position = positionValue(element),
              let size = sizeValue(element) else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func allWindowFrames(for app: NSRunningApplication) -> [CGRect] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return [] }

        return windows.compactMap { window in
            guard let position = positionValue(window), let size = sizeValue(window) else { return nil }
            return CGRect(origin: position, size: size)
        }
    }

    static func allVisibleWindowFrames() -> [(bundleId: String, frame: CGRect)] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [(String, CGRect)] = []
        for info in windowList {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"],
                  w > 50, h > 50 else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let bundleId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? owner
            result.append((bundleId, CGRect(x: x, y: y, width: w, height: h)))
        }
        return result
    }

    private static func axUIElement(from ref: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func axValue(from ref: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return (ref as! AXValue)
    }

    private static func stringAttribute(_ attr: CFString, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success,
              let str = value as? String else { return nil }
        return str
    }

    private static func positionValue(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let axValue = value.flatMap(axValue(from:)) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeValue(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let axValue = value.flatMap(axValue(from:)) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
