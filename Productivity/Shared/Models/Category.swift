import Foundation

enum ActivityCategory: String, Codable, CaseIterable, Sendable {
    case productive
    case neutral
    case distracting
    case uncategorized

    var displayName: String {
        switch self {
        case .productive: "Productive"
        case .neutral: "Neutral"
        case .distracting: "Distracting"
        case .uncategorized: "Uncategorized"
        }
    }

    var colorName: String {
        switch self {
        case .productive: "productive"
        case .neutral: "neutral"
        case .distracting: "distracting"
        case .uncategorized: "uncategorized"
        }
    }
}

enum ClassificationSource: String, Codable, Sendable {
    case rule
    case cache
    case apple
    case openRouter
    case manual
}
