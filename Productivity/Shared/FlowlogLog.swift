import os

enum FlowlogLog {
    private static let tracking = Logger(subsystem: "com.productivity.app", category: "Tracking")

    static func tracking(_ message: String) {
        tracking.error("\(message, privacy: .public)")
    }
}
