import CoreGraphics
import Foundation

enum IdleMonitor {
    static let idleThresholdSeconds: TimeInterval = 180

    static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null)
    }

    static var isIdle: Bool {
        secondsSinceLastInput() >= idleThresholdSeconds
    }
}
