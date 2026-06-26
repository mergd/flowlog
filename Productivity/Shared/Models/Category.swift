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

    /// SF Symbol representing the category in badges, lists, and the menu bar.
    var iconName: String {
        switch self {
        case .productive: "bolt.fill"
        case .neutral: "circle.lefthalf.filled"
        case .distracting: "exclamationmark.triangle.fill"
        case .uncategorized: "questionmark.circle"
        }
    }
}

enum ClassificationSource: String, Codable, Sendable {
    case rule          // user-defined rule
    case manual        // manual correction
    case appCatalog    // known app hardcode (authoritative)
    case siteCatalog   // known site/domain
    case cachedAI      // previously-resolved AI verdict, reused
    case apple         // live on-device AI
    case openRouter    // live remote AI
    case fallback      // no signal — abstained to uncategorized

    /// AI-derived verdicts (live or cached). These are guesses and must never
    /// override a deterministic authority such as a hardcoded app catalog entry.
    var isAIDerived: Bool {
        switch self {
        case .cachedAI, .apple, .openRouter: return true
        case .rule, .manual, .appCatalog, .siteCatalog, .fallback: return false
        }
    }
}

enum FocusScore {
    static let minimumTrackedSeconds: TimeInterval = 5 * 60

    static func percent(from totals: [String: TimeInterval]) -> Int? {
        let total = totals.values.reduce(0, +)
        guard total >= minimumTrackedSeconds else { return nil }
        let productive = totals[ActivityCategory.productive.rawValue] ?? 0
        return Int((productive / total) * 100)
    }
}
