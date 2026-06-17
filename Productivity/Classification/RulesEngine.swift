import Foundation
import GRDB

final class RulesEngine: @unchecked Sendable {
    static let shared = RulesEngine()

    private var exactRules: [String: ClassificationResult] = [:]
    private var windowTitlePatterns: [(pattern: String, result: ClassificationResult)] = []
    private var domainPatterns: [(pattern: String, result: ClassificationResult)] = []

    private var aiWindowTitles: [String: ClassificationResult] = [:]
    private var aiSiteLabels: [String: ClassificationResult] = [:]
    private var aiDomainPatterns: [(pattern: String, result: ClassificationResult)] = []

    private let lock = NSLock()

    private init() {}

    func reloadCache() {
        lock.lock()
        defer { lock.unlock() }

        exactRules.removeAll()
        windowTitlePatterns.removeAll()
        domainPatterns.removeAll()

        guard let rules = try? DatabaseManager.shared.allRules() else {
            FlowlogLog.tracking("Rules cache reload failed")
            return
        }
        for rule in rules {
            let result = ClassificationResult(
                category: rule.activityCategory,
                siteLabel: rule.siteLabel,
                confidence: 1.0,
                reason: "User rule",
                source: .rule
            )
            let pattern = rule.pattern.lowercased()
            switch rule.patternTypeEnum {
            case .windowTitle:
                windowTitlePatterns.append((pattern: pattern, result: result))
            case .domain:
                domainPatterns.append((pattern: pattern, result: result))
            case .bundleId, .siteLabel, .none:
                exactRules["\(rule.patternType):\(pattern)"] = result
            }
        }
    }

    func match(bundleId: String, windowTitle: String?, siteLabel: String?) -> ClassificationResult? {
        lock.lock()
        defer { lock.unlock() }

        if let title = windowTitle?.lowercased(), !title.isEmpty,
           let hit = aiWindowTitles[title] {
            return hit
        }
        if let siteLabel,
           let hit = exactRules["siteLabel:\(siteLabel.lowercased())"] ?? aiSiteLabels[siteLabel.lowercased()] {
            return hit
        }
        if let hit = exactRules["bundleId:\(bundleId.lowercased())"] { return hit }

        if let title = windowTitle?.lowercased() {
            for entry in windowTitlePatterns where title.contains(entry.pattern) {
                return entry.result
            }
            for entry in domainPatterns where title.contains(entry.pattern) {
                return entry.result
            }
            for entry in aiDomainPatterns where title.contains(entry.pattern) {
                return entry.result
            }
        }
        return nil
    }

    func bundleHeuristic(bundleId: String) -> ClassificationResult? {
        guard let (category, source) = AppCatalog.classification(for: bundleId) else { return nil }
        return ClassificationResult(
            category: category,
            siteLabel: nil,
            confidence: 0.85,
            reason: "Known app",
            source: source
        )
    }

    func siteHeuristic(domain: String, siteLabel: String?) -> ClassificationResult? {
        guard let (category, label, source) = SiteCatalog.classification(for: domain) else { return nil }
        return ClassificationResult(
            category: category,
            siteLabel: siteLabel ?? label,
            confidence: 0.9,
            reason: "Known site",
            source: source
        )
    }

    func cacheAIResult(
        windowTitle: String?,
        siteLabel: String?,
        domain: String?,
        result: ClassificationResult
    ) {
        lock.lock()
        defer { lock.unlock() }
        if let title = windowTitle?.lowercased(), !title.isEmpty {
            aiWindowTitles[title] = result
        }
        if let siteLabel {
            aiSiteLabels[siteLabel.lowercased()] = result
        }
        if let domain {
            let normalized = domain.lowercased()
            if let index = aiDomainPatterns.firstIndex(where: { $0.pattern == normalized }) {
                aiDomainPatterns[index] = (pattern: normalized, result: result)
            } else {
                aiDomainPatterns.append((pattern: normalized, result: result))
            }
        }
    }

    func addRule(
        patternType: Rule.PatternType,
        pattern: String,
        category: ActivityCategory,
        siteLabel: String? = nil
    ) throws {
        var rule = Rule(
            id: nil,
            patternType: patternType.rawValue,
            pattern: pattern,
            category: category.rawValue,
            siteLabel: siteLabel,
            createdAt: Date()
        )
        try DatabaseManager.shared.queue.write { db in
            try rule.insert(db)
        }
        reloadCache()
    }

    func deleteRule(id: Int64) throws {
        try DatabaseManager.shared.queue.write { db in
            _ = try Rule.deleteOne(db, key: id)
        }
        reloadCache()
    }
}
