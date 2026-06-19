import Foundation

enum RuleValidator {
    private static let junkPatterns: Set<String> = [
        "unknown", "n/a", "na", "none", "uncategorized", "untitled", "null", "undefined",
    ]

    static func normalizedPattern(_ pattern: String, type: Rule.PatternType) -> String {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .domain, .siteLabel, .windowTitle:
            return trimmed.lowercased()
        case .bundleId:
            return trimmed
        }
    }

    static func isValid(pattern: String, type: Rule.PatternType) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if junkPatterns.contains(trimmed.lowercased()) { return false }
        if type == .windowTitle, trimmed.count < 3 { return false }
        return true
    }

    static func isValid(_ rule: Rule) -> Bool {
        guard let type = rule.patternTypeEnum else { return false }
        return isValid(pattern: rule.pattern, type: type)
    }
}
