import CoreGraphics

enum Permissions {
    static func isScreenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
