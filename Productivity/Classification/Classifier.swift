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

        if let rule = RulesEngine.shared.match(
            bundleId: request.bundleId,
            windowTitle: request.windowTitle,
            siteLabel: browserContext.siteLabel
        ) {
            return rule
        }

        let aiEnabled = await MainActor.run { AppSettings.shared.aiClassificationEnabled }
        if aiEnabled, !shouldDebounce(request: request, force: force) {
            if let result = await runAI(request) {
                return result
            }
        }

        return heuristicFallback(request: request, browserContext: browserContext)
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

        if !openRouterOnly, AppleClassifier.shared.isSupported {
            do {
                let result = try await AppleClassifier.shared.classify(request: request)
                recordAICall(request: request)
                cacheResult(request: request, result: result)
                return result
            } catch {
                // fall through to OpenRouter
            }
        }

        guard !openRouterAPIKey.isEmpty else { return nil }

        do {
            let result = try await OpenRouterClassifier.shared.classify(request: request)
            recordAICall(request: request)
            cacheResult(request: request, result: result)
            return result
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

    private func heuristicFallback(
        request: ClassificationRequest,
        browserContext: ParsedBrowserContext
    ) -> ClassificationResult {
        if let domain = browserContext.domain,
           let site = RulesEngine.shared.siteHeuristic(domain: domain, siteLabel: browserContext.siteLabel) {
            return site
        }

        if !BrowserDetector.isBrowser(request.bundleId),
           let heuristic = RulesEngine.shared.bundleHeuristic(bundleId: request.bundleId) {
            return heuristic
        }

        return uncategorized(siteLabel: browserContext.siteLabel)
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
        saveRule: Bool = true
    ) throws {
        try DatabaseManager.shared.queue.write { db in
            var updated = session
            updated.category = category.rawValue
            updated.categorySource = ClassificationSource.manual.rawValue
            updated.siteLabel = siteLabel
            try updated.update(db)
        }

        guard saveRule else { return }

        if let siteLabel {
            try RulesEngine.shared.addRule(patternType: .siteLabel, pattern: siteLabel.lowercased(), category: category, siteLabel: siteLabel)
            if let domain = SiteCatalog.parse(windowTitle: session.windowTitle).domain
                ?? SiteCatalog.domain(from: session.windowTitle ?? "") {
                try RulesEngine.shared.addRule(patternType: .domain, pattern: domain, category: category, siteLabel: siteLabel)
            }
        } else {
            try RulesEngine.shared.addRule(patternType: .bundleId, pattern: session.bundleId, category: category, siteLabel: siteLabel)
        }
    }

    private func uncategorized(siteLabel: String?) -> ClassificationResult {
        ClassificationResult(
            category: .uncategorized,
            siteLabel: siteLabel,
            confidence: 0,
            reason: nil,
            source: .cache
        )
    }
}
