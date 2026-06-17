import AppKit
import Foundation

@MainActor
final class TrackingCoordinator: ObservableObject {
    static let shared = TrackingCoordinator()

    private let workspace = WorkspaceMonitor()
    private let recorder = SessionRecorder()
    private var pollTimer: Timer?
    private var screenshotTimer: Timer?
    private var purgeTimer: Timer?
    private var workLogTimer: Timer?

    private var currentApp: NSRunningApplication?
    private var currentTitle: String?
    private var lastBrowserContext: ParsedBrowserContext = .empty
    private var lastScreenshotDate: Date?
    private let screenshotInterval: TimeInterval = 180

    @Published var isTracking = false
    @Published var menuBarScorePercent: Int?

    func start() {
        guard !isTracking else { return }
        try? DatabaseManager.shared.setup()
        RulesEngine.shared.reloadCache()
        Task { await Classifier.shared.refreshAppleAvailability() }

        workspace.onActivate = { [weak self] app in
            Task { await self?.handleAppSwitch(app) }
        }
        workspace.onSleep = { [weak self] in
            Task { try? await self?.recorder.closeCurrentSession() }
        }
        workspace.start()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }

        screenshotTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.maybePeriodicScreenshot() }
        }

        purgeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            ScreenshotStore.shared.purgeOlderThan()
        }

        workLogTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { await self.generateHourlyWorkLogIfNeeded() }
        }

        ScreenshotStore.shared.purgeOlderThan()
        NudgeEngine.shared.start()
        isTracking = true
        refreshMenuBarScore()
    }

    func stop() {
        workspace.stop()
        pollTimer?.invalidate()
        screenshotTimer?.invalidate()
        purgeTimer?.invalidate()
        workLogTimer?.invalidate()
        NudgeEngine.shared.stop()
        Task { try? await recorder.closeCurrentSession() }
        isTracking = false
    }

    private func handleAppSwitch(_ app: NSRunningApplication) async {
        if let prev = currentApp, BrowserDetector.isBrowser(prev.bundleIdentifier ?? "") {
            await captureAndClassify(app: prev, title: currentTitle, reason: .leaveBrowser)
        }
        if !BrowserDetector.isBrowser(app.bundleIdentifier ?? "") {
            lastBrowserContext = .empty
        }
        currentApp = app
        currentTitle = WindowTitleReader.focusedWindowTitle(for: app)
        await openSession(for: app, title: currentTitle)
    }

    private func poll() async {
        guard let app = WorkspaceMonitor.frontmostApplication else { return }
        let bundleId = app.bundleIdentifier ?? ""

        if IdleMonitor.isIdle {
            try? await recorder.setIdlePaused(true)
            return
        }
        try? await recorder.setIdlePaused(false)

        if app != currentApp {
            await handleAppSwitch(app)
            return
        }

        let title = WindowTitleReader.focusedWindowTitle(for: app)
        guard title != currentTitle else {
            try? await recorder.tickDuration()
            refreshMenuBarScore()
            NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
            return
        }

        if BrowserDetector.isBrowser(bundleId) {
            let oldContext = resolvedBrowserContext(title: currentTitle, bundleId: bundleId)
            let newContext = resolvedBrowserContext(title: title, bundleId: bundleId)

            if SiteCatalog.domainChanged(from: oldContext, to: newContext) {
                await captureAndClassify(app: app, title: currentTitle, reason: .tabChange)
                currentTitle = title
                await openSession(for: app, title: title, context: newContext)
            } else {
                currentTitle = title
                let siteLabel = newContext.siteLabel ?? oldContext.siteLabel
                try? await recorder.updateCurrentSessionContext(
                    windowTitle: title,
                    siteLabel: siteLabel
                )
                await classifyCurrentSession(app: app, title: title)
            }
        } else {
            currentTitle = title
            if await recorder.hasActiveSession(for: bundleId) {
                try? await recorder.updateCurrentSessionContext(windowTitle: title, siteLabel: nil)
            } else {
                await openSession(for: app, title: title)
            }
        }

        try? await recorder.tickDuration()
        refreshMenuBarScore()
        NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
    }

    private func maybePeriodicScreenshot() async {
        guard Permissions.isScreenRecordingGranted() else { return }
        guard let app = currentApp, BrowserDetector.isBrowser(app.bundleIdentifier ?? "") else { return }
        if let last = lastScreenshotDate, Date().timeIntervalSince(last) < screenshotInterval { return }
        await captureAndClassify(app: app, title: currentTitle, reason: .periodic)
    }

    private enum CaptureReason { case tabChange, periodic, leaveBrowser }

    private func captureAndClassify(app: NSRunningApplication, title: String?, reason: CaptureReason) async {
        guard Permissions.isScreenRecordingGranted() else { return }
        guard let bundleId = app.bundleIdentifier else { return }
        let settings = AppSettings.shared
        if settings.blocklistedBundleIds.contains(bundleId) { return }

        guard let raw = await DesktopScreenshotCapture.captureFullDesktop() else { return }

        let windows = WindowTitleReader.allVisibleWindowFrames()
        let focusedFrame = WindowTitleReader.focusedWindowFrame(for: app)
        let redacted = ScreenshotPreprocessor.redact(
            image: raw,
            context: .init(
                focusedBundleId: bundleId,
                focusedWindowFrame: focusedFrame,
                blocklistedBundleIds: settings.blocklistedBundleIds,
                aggressive: settings.aggressiveRedaction,
                allWindows: windows
            )
        ) ?? raw

        guard let jpeg = ScreenshotPreprocessor.jpegData(from: redacted) else { return }
        guard let screenshotId = try? ScreenshotStore.shared.save(jpegData: jpeg) else { return }
        lastScreenshotDate = Date()

        let request = ClassificationRequest(
            bundleId: bundleId,
            appName: app.localizedName ?? bundleId,
            windowTitle: title,
            imageData: jpeg
        )
        let result = await Classifier.shared.classify(request, force: reason == .tabChange)
        try? await recorder.updateCurrentSession(
            category: result.category,
            source: result.source,
            siteLabel: result.siteLabel,
            screenshotId: screenshotId
        )
    }

    private func openSession(for app: NSRunningApplication, title: String?, context: ParsedBrowserContext? = nil) async {
        guard let bundleId = app.bundleIdentifier else { return }
        guard AppCatalog.shouldTrack(bundleId: bundleId) else {
            try? await recorder.closeCurrentSession()
            return
        }

        let appName = AppCatalog.friendlyName(bundleId: bundleId, fallback: app.localizedName ?? bundleId)
        let isBrowser = BrowserDetector.isBrowser(bundleId)
        let browserContext = isBrowser ? (context ?? resolvedBrowserContext(title: title, bundleId: bundleId)) : .empty

        if isBrowser, !SiteCatalog.shouldTrack(domain: browserContext.domain, pageTitle: browserContext.pageTitle, windowTitle: title) {
            if await recorder.hasActiveSession(for: bundleId) {
                try? await recorder.updateCurrentSessionContext(
                    windowTitle: title,
                    siteLabel: browserContext.siteLabel ?? lastBrowserContext.siteLabel
                )
                return
            }
            try? await recorder.closeCurrentSession()
            return
        }

        let match = RulesEngine.shared.match(
            bundleId: bundleId,
            windowTitle: title,
            siteLabel: browserContext.siteLabel
        )

        let siteLabel = match?.siteLabel ?? browserContext.siteLabel ?? lastBrowserContext.siteLabel
        let sessionIdentity = isBrowser
            ? SiteCatalog.sessionIdentity(bundleId: bundleId, context: browserContext)
            : bundleId

        try? await recorder.openSession(
            bundleId: bundleId,
            appName: appName,
            windowTitle: title,
            category: match?.category ?? .uncategorized,
            categorySource: match?.source,
            siteLabel: siteLabel,
            sessionIdentity: sessionIdentity
        )

        if match == nil, AppSettings.shared.aiClassificationEnabled {
            await classifyCurrentSession(app: app, title: title, force: isBrowser)
        }
    }

    private func classifyCurrentSession(
        app: NSRunningApplication,
        title: String?,
        force: Bool = false
    ) async {
        guard AppSettings.shared.aiClassificationEnabled else { return }
        guard let bundleId = app.bundleIdentifier else { return }

        let appName = AppCatalog.friendlyName(bundleId: bundleId, fallback: app.localizedName ?? bundleId)
        let request = ClassificationRequest(
            bundleId: bundleId,
            appName: appName,
            windowTitle: title,
            imageData: nil
        )
        let result = await Classifier.shared.classify(request, force: force)
        try? await recorder.updateCurrentSession(
            category: result.category,
            source: result.source,
            siteLabel: result.siteLabel
        )
    }

    private func resolvedBrowserContext(title: String?, bundleId: String) -> ParsedBrowserContext {
        let parsed = SiteCatalog.parse(windowTitle: title)
        if parsed.domain != nil {
            lastBrowserContext = parsed
            return parsed
        }
        if let siteLabel = parsed.siteLabel, !siteLabel.isEmpty {
            let merged = ParsedBrowserContext(
                domain: lastBrowserContext.domain,
                siteLabel: siteLabel,
                pageTitle: parsed.pageTitle ?? lastBrowserContext.pageTitle
            )
            if merged.domain != nil || merged.siteLabel != nil {
                lastBrowserContext = merged
            }
            return merged
        }
        if lastBrowserContext.domain != nil || lastBrowserContext.siteLabel != nil {
            return ParsedBrowserContext(
                domain: lastBrowserContext.domain,
                siteLabel: lastBrowserContext.siteLabel,
                pageTitle: parsed.pageTitle ?? lastBrowserContext.pageTitle
            )
        }
        return parsed
    }

    private func generateHourlyWorkLogIfNeeded() async {
        let hour = Calendar.current.component(.hour, from: Date())
        let start = AppSettings.shared.workHoursStart
        let end = AppSettings.shared.workHoursEnd
        guard hour >= start, hour < end else { return }
        let periodEnd = Date()
        let periodStart = periodEnd.addingTimeInterval(-3600)
        _ = try? await WorkLogGenerator.shared.generate(for: periodStart, periodEnd: periodEnd)
    }

    func refreshMenuBarScore() {
        guard let totals = try? DatabaseManager.shared.categoryTotalsToday() else {
            menuBarScorePercent = nil
            return
        }
        let productive = totals[ActivityCategory.productive.rawValue] ?? 0
        let neutral = totals[ActivityCategory.neutral.rawValue] ?? 0
        let distracting = totals[ActivityCategory.distracting.rawValue] ?? 0
        let total = productive + neutral + distracting
        guard total > 0 else {
            menuBarScorePercent = nil
            return
        }
        menuBarScorePercent = Int((productive / total) * 100)
    }
}
