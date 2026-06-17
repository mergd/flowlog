import Foundation
import GRDB

final class RulesEngine: @unchecked Sendable {
    static let shared = RulesEngine()

    private var cache: [String: ClassificationResult] = [:]
    private var aiCache: [String: ClassificationResult] = [:]
    private let lock = NSLock()

    private init() {}

    func reloadCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        guard let rules = try? DatabaseManager.shared.allRules() else { return }
        for rule in rules {
            let key = "\(rule.patternType):\(rule.pattern.lowercased())"
            cache[key] = ClassificationResult(
                category: rule.activityCategory,
                siteLabel: rule.siteLabel,
                confidence: 1.0,
                reason: "User rule",
                source: .rule
            )
        }
    }

    func match(bundleId: String, windowTitle: String?, siteLabel: String?) -> ClassificationResult? {
        lock.lock()
        defer { lock.unlock() }

        if let title = windowTitle?.lowercased(), !title.isEmpty,
           let hit = aiCache["windowTitle:\(title)"] {
            return hit
        }
        if let siteLabel, let hit = cache["siteLabel:\(siteLabel.lowercased())"] ?? aiCache["siteLabel:\(siteLabel.lowercased())"] { return hit }
        if let hit = cache["bundleId:\(bundleId.lowercased())"] { return hit }

        if let title = windowTitle?.lowercased() {
            for (key, result) in cache where key.hasPrefix("windowTitle:") {
                let pattern = String(key.dropFirst("windowTitle:".count))
                if title.contains(pattern) { return result }
            }
            for (key, result) in cache where key.hasPrefix("domain:") {
                let domain = String(key.dropFirst("domain:".count))
                if title.contains(domain) { return result }
            }
            for (key, result) in aiCache where key.hasPrefix("domain:") {
                let domain = String(key.dropFirst("domain:".count))
                if title.contains(domain) { return result }
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
            aiCache["windowTitle:\(title)"] = result
        }
        if let siteLabel {
            aiCache["siteLabel:\(siteLabel.lowercased())"] = result
        }
        if let domain {
            aiCache["domain:\(domain.lowercased())"] = result
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
