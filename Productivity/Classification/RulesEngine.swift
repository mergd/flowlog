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

        // Drop cached AI verdicts so an edited/deleted rule isn't shadowed by
        // a stale guess until the next app restart.
        aiWindowTitles.removeAll()
        aiSiteLabels.removeAll()
        aiDomainPatterns.removeAll()

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

    /// Deterministic match against user-defined rules only. Highest authority.
    func userRule(bundleId: String, windowTitle: String?, siteLabel: String?) -> ClassificationResult? {
        lock.lock()
        defer { lock.unlock() }

        if let siteLabel, let hit = exactRules["siteLabel:\(siteLabel.lowercased())"] {
            return hit
        }
        if let hit = exactRules["bundleId:\(bundleId.lowercased())"] { return hit }

        if let title = windowTitle?.lowercased(), !title.isEmpty {
            for entry in windowTitlePatterns where title.contains(entry.pattern) {
                return entry.result
            }
            for entry in domainPatterns where title.contains(entry.pattern) {
                return entry.result
            }
        }
        return nil
    }

    /// Previously-resolved AI verdicts, reused. Lower authority than rules/catalogs.
    func cachedAI(bundleId: String, windowTitle: String?, siteLabel: String?) -> ClassificationResult? {
        lock.lock()
        defer { lock.unlock() }

        if let title = windowTitle?.lowercased(), !title.isEmpty, let hit = aiWindowTitles[title] {
            return hit
        }
        if let siteLabel, let hit = aiSiteLabels[siteLabel.lowercased()] { return hit }
        if let title = windowTitle?.lowercased(), !title.isEmpty {
            for entry in aiDomainPatterns where title.contains(entry.pattern) {
                return entry.result
            }
        }
        return nil
    }

    /// Convenience: any non-live-AI deterministic match (user rule, then cached AI).
    func match(bundleId: String, windowTitle: String?, siteLabel: String?) -> ClassificationResult? {
        userRule(bundleId: bundleId, windowTitle: windowTitle, siteLabel: siteLabel)
            ?? cachedAI(bundleId: bundleId, windowTitle: windowTitle, siteLabel: siteLabel)
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
            siteLabel: label,  // prefer the catalog's clean name for consistent rounding
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
        // Reuse of this verdict is a cache hit, not a fresh AI call — record that.
        let cached = ClassificationResult(
            category: result.category,
            siteLabel: result.siteLabel,
            confidence: result.confidence,
            reason: result.reason,
            source: .cachedAI
        )
        if let title = windowTitle?.lowercased(), !title.isEmpty {
            aiWindowTitles[title] = cached
        }
        if let siteLabel {
            aiSiteLabels[siteLabel.lowercased()] = cached
        }
        if let domain {
            let normalized = domain.lowercased()
            if let index = aiDomainPatterns.firstIndex(where: { $0.pattern == normalized }) {
                aiDomainPatterns[index] = (pattern: normalized, result: cached)
            } else {
                aiDomainPatterns.append((pattern: normalized, result: cached))
            }
        }
    }

    func addRule(
        patternType: Rule.PatternType,
        pattern: String,
        category: ActivityCategory,
        siteLabel: String? = nil
    ) throws {
        let normalized = RuleValidator.normalizedPattern(pattern, type: patternType)
        guard RuleValidator.isValid(pattern: normalized, type: patternType) else { return }

        let storedSiteLabel: String?
        if patternType == .siteLabel {
            storedSiteLabel = siteLabel ?? pattern
        } else {
            storedSiteLabel = siteLabel
        }

        try DatabaseManager.shared.queue.write { db in
            if var existing = try Rule
                .filter(Rule.Columns.patternType == patternType.rawValue)
                .filter(Rule.Columns.pattern == normalized)
                .fetchOne(db) {
                existing.category = category.rawValue
                existing.siteLabel = storedSiteLabel
                try existing.update(db)
                return
            }

            var rule = Rule(
                id: nil,
                patternType: patternType.rawValue,
                pattern: normalized,
                category: category.rawValue,
                siteLabel: storedSiteLabel,
                createdAt: Date()
            )
            try rule.insert(db)
        }
        reloadCache()
        try reapplyRulesToStoredSessions()
        NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
    }

    /// Re-applies every stored user rule to past sessions. Manual corrections are
    /// left alone. Called when rules change and once on startup to backfill history.
    @discardableResult
    func reapplyRulesToStoredSessions() throws -> Int {
        try DatabaseManager.shared.queue.write { db in
            let sessions = try Session.fetchAll(db)
            var updated = 0
            for var session in sessions {
                guard session.categorySource != ClassificationSource.manual.rawValue else { continue }

                let browserContext = SiteCatalog.parse(windowTitle: session.windowTitle)
                let siteLabel = session.siteLabel ?? browserContext.siteLabel
                guard let result = userRule(
                    bundleId: session.bundleId,
                    windowTitle: session.windowTitle,
                    siteLabel: siteLabel
                ) else { continue }

                let categoryChanged = session.category != result.category.rawValue
                let sourceChanged = session.categorySource != result.source.rawValue
                let siteLabelChanged = result.siteLabel != nil && session.siteLabel != result.siteLabel
                guard categoryChanged || sourceChanged || siteLabelChanged else { continue }

                session.category = result.category.rawValue
                session.categorySource = result.source.rawValue
                if let label = result.siteLabel {
                    session.siteLabel = label
                }
                try session.update(db)
                updated += 1
            }
            return updated
        }
    }

    func deleteRule(id: Int64) throws {
        try DatabaseManager.shared.queue.write { db in
            _ = try Rule.deleteOne(db, key: id)
        }
        reloadCache()
        NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
    }

    @discardableResult
    func deleteInvalidRules() throws -> Int {
        let invalid = try DatabaseManager.shared.allRules().filter { !RuleValidator.isValid($0) }
        guard !invalid.isEmpty else { return 0 }
        try DatabaseManager.shared.queue.write { db in
            for rule in invalid {
                if let id = rule.id {
                    _ = try Rule.deleteOne(db, key: id)
                }
            }
        }
        reloadCache()
        NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
        return invalid.count
    }
}
