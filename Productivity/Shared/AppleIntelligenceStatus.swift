import Foundation

enum AppleIntelligenceStatus: Equatable, Sendable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    case frameworkUnavailable
    case osVersionUnsupported

    var isAvailable: Bool {
        self == .available
    }

    var title: String {
        switch self {
        case .available: "Ready"
        case .deviceNotEligible: "Unavailable"
        case .notEnabled: "Not enabled"
        case .modelNotReady: "Downloading"
        case .frameworkUnavailable: "Unsupported"
        case .osVersionUnsupported: "Requires macOS 26"
        }
    }

    var detail: String {
        switch self {
        case .available:
            "On-device models are ready for classification."
        case .deviceNotEligible:
            "This Mac cannot run Apple Intelligence."
        case .notEnabled:
            "Turn on Apple Intelligence in System Settings."
        case .modelNotReady:
            "Apple Intelligence is enabled but models are still downloading."
        case .frameworkUnavailable:
            "Foundation Models are not available in this build."
        case .osVersionUnsupported:
            "Upgrade to macOS 26 to use Apple Intelligence."
        }
    }

    var systemImage: String {
        switch self {
        case .available: "sparkles"
        case .deviceNotEligible: "desktopcomputer.trianglebadge.exclamationmark"
        case .notEnabled: "sparkles.rectangle.stack"
        case .modelNotReady: "arrow.down.circle"
        case .frameworkUnavailable, .osVersionUnsupported: "exclamationmark.triangle"
        }
    }
}
