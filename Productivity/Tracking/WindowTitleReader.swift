import AppKit
import ApplicationServices

enum WindowTitleReader {
    static func requestAccessibilityTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// TCC flag — can lag behind System Settings until the app restarts.
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Stable probe that doesn't depend on which app is frontmost.
    static func canQueryAccessibilityAPI() -> Bool {
        let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var roleRef: CFTypeRef?
        return AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute as CFString, &roleRef) == .success
    }

    static func hasAccessibilityAccess() -> Bool {
        isAccessibilityTrusted() || canQueryAccessibilityAPI()
    }

    static func focusedWindowTitle(for app: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard result == .success, let window = windowRef, let element = axUIElement(from: window) else { return nil }
        return stringAttribute(kAXTitleAttribute as CFString, on: element)
    }

    static func focusedWindowFrame(for app: NSRunningApplication) -> CGRect? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
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
