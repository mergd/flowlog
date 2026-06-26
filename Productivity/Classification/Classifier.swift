import Foundation

actor Classifier {
    static let shared = Classifier()

    private var lastVisionCallDate: Date?
    private var lastTextCallByTitle: [String: Date] = [:]
    private let visionDebounceInterval: TimeInterval = 30
    private let textDebounceInterval: TimeInterval = 8

    func refreshAppleAvailability() {
        AppleClassifier.shared.refreshAvailability()
    }

    var appleSupported: Bool {
        AppleClassifier.shared.isSupported
    }

    func classify(_ request: ClassificationRequest, force: Bool = false) async -> ClassificationResult {
        let browserContext = SiteCatalog.parse(windowTitle: request.windowTitle)

        // Authority ladder — first hit wins and stops the cascade.
        // user rule → app catalog → site catalog → cached AI.
        if let deterministic = deterministicMatch(request: request, browserContext: browserContext) {
            return deterministic
        }

        // Live AI runs only for genuinely unknown / ambiguous contexts.
        let aiEnabled = await MainActor.run { AppSettings.shared.aiClassificationEnabled }
        if aiEnabled, !shouldDebounce(request: request, force: force) {
            // A text-only request with no real context (title missing, equal to the
            // app name, or a generic placeholder) gives the model nothing to reason
            // about — it just coin-flips, which is what produced the same app
            // flip-flopping across productive/distracting/neutral. Abstain instead.
            // The vision path (imageData != nil) still runs: a screenshot is context.
            if request.imageData == nil,
               Self.isContextlessForAI(title: request.windowTitle, appName: request.appName) {
                return uncategorized(
                    siteLabel: SiteCatalog.sanitizedSiteLabel(
                        browserContext.siteLabel,
                        bundleId: request.bundleId,
                        appName: request.appName
                    )
                )
            }
            if let result = await runAI(request) {
                return result
            }
        }

        // Abstain rather than guess.
        return uncategorized(
            siteLabel: SiteCatalog.sanitizedSiteLabel(
                browserContext.siteLabel,
                bundleId: request.bundleId,
                appName: request.appName
            )
        )
    }

    /// The deterministic rungs of the authority ladder, in order. Returns nil if
    /// nothing recognizes this context (caller may then fall through to live AI).
    /// `nonisolated` so the tracking loop can resolve a known context synchronously
    /// without spinning up the live-AI path.
    nonisolated func deterministicMatch(
        request: ClassificationRequest,
        browserContext: ParsedBrowserContext
    ) -> ClassificationResult? {
        // 1. User rules / manual corrections — highest authority.
        if let rule = RulesEngine.shared.userRule(
            bundleId: request.bundleId,
            windowTitle: request.windowTitle,
            siteLabel: browserContext.siteLabel
        ) {
            return rule
        }

        // 2. App-level hardcode — authoritative for apps where the app *is* the
        //    intent (editors, IDEs, terminals). AI never overrides these.
        if !BrowserDetector.isBrowser(request.bundleId),
           let appHit = RulesEngine.shared.bundleHeuristic(bundleId: request.bundleId) {
            return appHit
        }

        // 3. Known site/domain catalog.
        if let domain = browserContext.domain,
           let siteHit = RulesEngine.shared.siteHeuristic(
               domain: domain,
               siteLabel: browserContext.siteLabel
           ) {
            return siteHit
        }

        // 4. Cached AI verdict from a prior resolution.
        return RulesEngine.shared.cachedAI(
            bundleId: request.bundleId,
            windowTitle: request.windowTitle,
            siteLabel: browserContext.siteLabel
        )
    }

    /// A window title carries no signal the model could classify on: it's missing,
    /// just the app's own name, or a generic placeholder. Asking the AI to judge
    /// these yields inconsistent guesses, so we abstain to uncategorized instead.
    private static func isContextlessForAI(title: String?, appName: String) -> Bool {
        guard let raw = title?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return true
        }
        let lower = raw.lowercased()
        if lower == appName.lowercased() { return true }
        let placeholders: Set<String> = ["untitled", "new tab", "new window"]
        return placeholders.contains(lower)
    }

    private func shouldDebounce(request: ClassificationRequest, force: Bool) -> Bool {
        if force { return false }

        if request.imageData != nil {
            if let last = lastVisionCallDate,
               Date().timeIntervalSince(last) < visionDebounceInterval {
                return true
            }
            return false
        }

        guard let title = request.windowTitle?.lowercased(), !title.isEmpty else { return false }
        if let last = lastTextCallByTitle[title],
           Date().timeIntervalSince(last) < textDebounceInterval {
            return true
        }
        return false
    }

    private func runAI(_ request: ClassificationRequest) async -> ClassificationResult? {
        let openRouterOnly = await MainActor.run { AppSettings.shared.openRouterOnly }
        let openRouterAPIKey = await MainActor.run { AppSettings.shared.openRouterAPIKey }

        let sanitized: (ClassificationResult) -> ClassificationResult = { result in
            ClassificationResult(
                category: result.category,
                siteLabel: SiteCatalog.sanitizedSiteLabel(
                    result.siteLabel,
                    bundleId: request.bundleId,
                    appName: request.appName
                ),
                confidence: result.confidence,
                reason: result.reason,
                source: result.source
            )
        }

        if !openRouterOnly, AppleClassifier.shared.isSupported {
            do {
                let result = try await AppleClassifier.shared.classify(request: request)
                let cleaned = sanitized(result)
                recordAICall(request: request)
                cacheResult(request: request, result: cleaned)
                return cleaned
            } catch {
                // fall through to OpenRouter
            }
        }

        guard !openRouterAPIKey.isEmpty else { return nil }

        do {
            let result = try await OpenRouterClassifier.shared.classify(request: request)
            let cleaned = sanitized(result)
            recordAICall(request: request)
            cacheResult(request: request, result: cleaned)
            return cleaned
        } catch {
            return nil
        }
    }

    private func recordAICall(request: ClassificationRequest) {
        if request.imageData != nil {
            lastVisionCallDate = Date()
        } else if let title = request.windowTitle?.lowercased(), !title.isEmpty {
            lastTextCallByTitle[title] = Date()
        }
    }

    private func cacheResult(request: ClassificationRequest, result: ClassificationResult) {
        let domain = SiteCatalog.parse(windowTitle: request.windowTitle).domain
            ?? OCRPreprocessor.extractDomain(from: request.windowTitle)
        RulesEngine.shared.cacheAIResult(
            windowTitle: request.windowTitle,
            siteLabel: result.siteLabel,
            domain: domain,
            result: result
        )
    }

    func applyManualCorrection(
        session: Session,
        category: ActivityCategory,
        siteLabel: String?,
        remember: SessionRememberScope = .none
    ) throws {
        try DatabaseManager.shared.queue.write { db in
            var updated = session
            updated.category = category.rawValue
            updated.categorySource = ClassificationSource.manual.rawValue
            updated.siteLabel = siteLabel
            try updated.update(db)
        }

        switch remember {
        case .none:
            return
        case .app:
            try RulesEngine.shared.addRule(
                patternType: .bundleId,
                pattern: session.bundleId,
                category: category,
                siteLabel: siteLabel
            )
        case .site:
            let label = siteLabel ?? session.siteLabel
            if let label,
               RuleValidator.isValid(pattern: label, type: .siteLabel) {
                try RulesEngine.shared.addRule(
                    patternType: .siteLabel,
                    pattern: label,
                    category: category,
                    siteLabel: label
                )
            }
            if let domain = SiteCatalog.parse(windowTitle: session.windowTitle).domain
                ?? SiteCatalog.domain(from: session.windowTitle ?? ""),
               RuleValidator.isValid(pattern: domain, type: .domain) {
                try RulesEngine.shared.addRule(
                    patternType: .domain,
                    pattern: domain,
                    category: category,
                    siteLabel: label
                )
            }
        case .windowTitle(let keyword):
            guard RuleValidator.isValid(pattern: keyword, type: .windowTitle) else { return }
            let pattern = RuleValidator.normalizedPattern(keyword, type: .windowTitle)
            try RulesEngine.shared.addRule(
                patternType: .windowTitle,
                pattern: pattern,
                category: category,
                siteLabel: siteLabel ?? session.siteLabel
            )
        }
    }

    private func uncategorized(siteLabel: String?) -> ClassificationResult {
        ClassificationResult(
            category: .uncategorized,
            siteLabel: siteLabel,
            confidence: 0,
            reason: nil,
            source: .fallback
        )
    }
}
