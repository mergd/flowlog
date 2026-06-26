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

    private var currentApp: NSRunningApplication?
    private var currentTitle: String?
    /// An app switch only commits to a session after the app has held focus for this
    /// long. Bouncing through apps faster than this (alt-tab flicker) never opens a
    /// session, which is what produced the storm of sub-2s micro-sessions.
    private let appSwitchDwellInterval: TimeInterval = 2
    private var pendingApp: NSRunningApplication?
    private var pendingSwitchTask: Task<Void, Never>?
    private var lastBrowserContext: ParsedBrowserContext = .empty
    private var lastScreenshotDate: Date?
    private let screenshotInterval: TimeInterval = 60
    /// Captures triggered by tab/app switches (not the periodic timer) are throttled
    /// to this floor so rapid switching can't fire the capture+encode pipeline
    /// back-to-back. Shorter than `screenshotInterval` to still capture most context.
    private let switchScreenshotInterval: TimeInterval = 8

    @Published var isTracking = false
    @Published private(set) var menuBarSession: MenuBarSessionInfo?
    @Published private(set) var snoozedUntil: Date?
    private var snoozeTimer: Timer?
    private var activePauseId: Int64?

    var isSnoozed: Bool { snoozedUntil != nil }

    /// False when window titles can't be read — either Accessibility trust was lost
    /// at runtime, or tracked apps keep returning no title. Drives a degraded-state hint.
    @Published private(set) var accessibilityHealthy = true
    private var consecutiveTitleMisses = 0
    private let titleMissThreshold = 15  // ~30s of polls with no readable title

    func start() {
        guard !isTracking else { return }
        do {
            try DatabaseManager.shared.setup()
            try DatabaseManager.shared.closeDanglingOpenSessions()
            try DatabaseManager.shared.normalizeLegacySessionExclusions()
        } catch {
            FlowlogLog.tracking("Database setup failed: \(error.localizedDescription)")
        }
        RulesEngine.shared.reloadCache()
        do {
            try RulesEngine.shared.reapplyRulesToStoredSessions()
        } catch {
            FlowlogLog.tracking("Rule backfill failed: \(error.localizedDescription)")
        }
        Task { await Classifier.shared.refreshAppleAvailability() }

        workspace.onActivate = { [weak self] app in
            self?.requestAppSwitch(app)
        }
        workspace.onSleep = { [weak self] in
            guard let self else { return }
            self.cancelPendingSwitch()
            Task {
                await self.track("close session on sleep") { try await self.recorder.closeCurrentSession() }
            }
        }
        workspace.start()
        startPolling()

        ScreenshotStore.shared.purgeOlderThan()
        NudgeEngine.shared.start()
        isTracking = true
        refreshMenuBarSession()
    }

    func stop() {
        workspace.stop()
        cancelPendingSwitch()
        invalidateTimers()
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        snoozedUntil = nil
        if let id = activePauseId {
            try? DatabaseManager.shared.endPause(id: id, end: Date())
            activePauseId = nil
        }
        NudgeEngine.shared.stop()
        Task {
            await track("close session on stop") { try await recorder.closeCurrentSession() }
        }
        isTracking = false
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
        screenshotTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.maybePeriodicScreenshot() }
        }
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            ScreenshotStore.shared.purgeOlderThan()
        }
    }

    private func invalidateTimers() {
        pollTimer?.invalidate(); pollTimer = nil
        screenshotTimer?.invalidate(); screenshotTimer = nil
        purgeTimer?.invalidate(); purgeTimer = nil
    }

    /// Pause tracking for a duration (closes the current session and stops polling).
    func snooze(for duration: TimeInterval) {
        guard isTracking else { return }
        snoozedUntil = Date().addingTimeInterval(duration)
        cancelPendingSwitch()
        invalidateTimers()
        NudgeEngine.shared.stop()
        Task { await track("close on snooze") { try await recorder.closeCurrentSession() } }

        // Record the pause so it reads as a deliberate "paused" stretch, not untracked.
        // Seed it with the planned end so it's bounded even if the app quits while paused.
        activePauseId = try? DatabaseManager.shared.beginPause(start: Date(), plannedEnd: snoozedUntil)

        snoozeTimer?.invalidate()
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.endSnooze() }
        }
        refreshMenuBarSession()
    }

    /// Resume tracking immediately (or automatically when the snooze elapses).
    func endSnooze() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        guard snoozedUntil != nil else { return }
        snoozedUntil = nil
        if let id = activePauseId {
            try? DatabaseManager.shared.endPause(id: id, end: Date())
            activePauseId = nil
        }
        guard isTracking else { return }
        startPolling()
        NudgeEngine.shared.start()
        refreshMenuBarSession()
    }

    /// Schedule a switch to `app`, committing only after it holds focus for the dwell
    /// interval. Rapid switching repeatedly reschedules, so transient apps never commit.
    private func requestAppSwitch(_ app: NSRunningApplication) {
        if app == currentApp {
            cancelPendingSwitch()
            return
        }
        if app == pendingApp { return }  // already scheduled — let the timer ride

        cancelPendingSwitch()
        pendingApp = app
        pendingSwitchTask = Task { [weak self] in
            guard let self else { return }
            let dwell = await MainActor.run { self.appSwitchDwellInterval }
            try? await Task.sleep(nanoseconds: UInt64(dwell * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.commitAppSwitch(app)
        }
    }

    private func commitAppSwitch(_ app: NSRunningApplication) async {
        guard pendingApp == app else { return }
        pendingApp = nil
        pendingSwitchTask = nil
        await handleAppSwitch(app)
        refreshMenuBarSession()
    }

    private func cancelPendingSwitch() {
        pendingSwitchTask?.cancel()
        pendingSwitchTask = nil
        pendingApp = nil
    }

    private func handleAppSwitch(_ app: NSRunningApplication) async {
        if let prev = currentApp, BrowserDetector.isBrowser(prev.bundleIdentifier ?? "") {
            await captureAndClassify(app: prev, title: currentTitle, reason: .leaveBrowser)
        }
        if !BrowserDetector.isBrowser(app.bundleIdentifier ?? "") {
            lastBrowserContext = .empty
        }
        currentApp = app
        currentTitle = readTitle(for: app)
        await openSession(for: app, title: currentTitle)
        refreshMenuBarSession()
    }

    private func poll() async {
        guard let app = WorkspaceMonitor.frontmostApplication else { return }
        let bundleId = app.bundleIdentifier ?? ""

        if app != currentApp {
            requestAppSwitch(app)
            return
        }
        // Frontmost is the committed app again — if a switch to something else was
        // pending (we briefly tabbed away and came back), drop it so the glance
        // never becomes its own session.
        if pendingApp != nil { cancelPendingSwitch() }

        let title = readTitle(for: app)

        if title == nil, currentTitle != nil {
            let hasSession = await recorder.hasActiveSession(for: bundleId)
            if !hasSession {
                await openSession(for: app, title: currentTitle)
            }
            await track("tick duration") { try await recorder.tickDuration() }
            refreshMenuBarSession()
            return
        }

        guard title != currentTitle else {
            let hasSession = await recorder.hasActiveSession(for: bundleId)
            if !hasSession {
                await openSession(for: app, title: title)
            }
            await track("tick duration") { try await recorder.tickDuration() }
            refreshMenuBarSession()
            return
        }

        if BrowserDetector.isBrowser(bundleId) {
            let previousContext = lastBrowserContext
            // resolvedBrowserContext reads the live URL and updates lastBrowserContext,
            // so compare the new context against the previous poll's stored value.
            let newContext = await resolvedBrowserContext(app: app, title: title, bundleId: bundleId)

            if SiteCatalog.domainChanged(from: previousContext, to: newContext) {
                await captureAndClassify(app: app, title: currentTitle, reason: .tabChange)
                currentTitle = title
                await openSession(for: app, title: title, context: newContext)
            } else {
                currentTitle = title
                let siteLabel = newContext.siteLabel ?? previousContext.siteLabel
                await track("update session context") {
                    try await recorder.updateCurrentSessionContext(
                        windowTitle: title,
                        siteLabel: siteLabel
                    )
                }
            }
        } else {
            if EditorContext.isEditor(bundleId: bundleId),
               editorSessionIdentity(bundleId: bundleId, title: title) != editorSessionIdentity(bundleId: bundleId, title: currentTitle) {
                currentTitle = title
                await openSession(for: app, title: title)
                await track("tick duration") { try await recorder.tickDuration() }
                refreshMenuBarSession()
                NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
                return
            }

            currentTitle = title
            if await recorder.hasActiveSession(for: bundleId) {
                await track("update session title") {
                    try await recorder.updateCurrentSessionContext(windowTitle: title, siteLabel: nil)
                }
            } else {
                await openSession(for: app, title: title)
            }
        }

        await track("tick duration") { try await recorder.tickDuration() }
        refreshMenuBarSession()
        NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
    }

    private func maybePeriodicScreenshot() async {
        guard Permissions.isScreenRecordingGranted() else { return }
        guard let app = currentApp, let bundleId = app.bundleIdentifier else { return }
        guard AppCatalog.shouldTrack(bundleId: bundleId) else { return }
        if let last = lastScreenshotDate, Date().timeIntervalSince(last) < screenshotInterval { return }
        await captureAndClassify(app: app, title: currentTitle, reason: .periodic)
    }

    private enum CaptureReason { case tabChange, periodic, leaveBrowser }

    private func captureAndClassify(app: NSRunningApplication, title: String?, reason: CaptureReason) async {
        guard Permissions.isScreenRecordingGranted() else { return }
        guard let bundleId = app.bundleIdentifier else { return }
        let settings = AppSettings.shared
        if settings.blocklistedBundleIds.contains(bundleId) { return }

        // Throttle switch-driven captures. The periodic timer already enforces its
        // own interval, but the tab/browser-switch paths had no floor, so rapid
        // switching could fire the capture+encode pipeline several times a second.
        if reason != .periodic, let last = lastScreenshotDate,
           Date().timeIntervalSince(last) < switchScreenshotInterval {
            return
        }

        guard let raw = await DesktopScreenshotCapture.captureFullDesktop() else { return }
        guard let cgImage = raw.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let imageSize = raw.size

        let redactionContext = ScreenshotPreprocessor.RedactionContext(
            focusedBundleId: bundleId,
            focusedWindowFrame: WindowTitleReader.focusedWindowFrame(for: app),
            blocklistedBundleIds: settings.blocklistedBundleIds,
            aggressive: settings.aggressiveRedaction,
            allWindows: WindowTitleReader.allVisibleWindowFrames()
        )

        // Redaction, downscaling, JPEG encoding and the disk write are all heavy
        // CPU/IO. Run them off the main actor so capturing a screenshot never
        // stalls the UI. Only Sendable values cross the boundary.
        let encoded: (jpeg: Data, id: String)? = await Task.detached(priority: .utility) {
            guard let jpeg = ScreenshotPreprocessor.redactedJPEG(
                cgImage: cgImage,
                imageSize: imageSize,
                context: redactionContext
            ) else { return nil }
            guard let id = try? ScreenshotStore.shared.save(jpegData: jpeg) else { return nil }
            return (jpeg, id)
        }.value
        guard let (jpeg, screenshotId) = encoded else { return }
        lastScreenshotDate = Date()

        let request = ClassificationRequest(
            bundleId: bundleId,
            appName: app.localizedName ?? bundleId,
            windowTitle: title,
            imageData: jpeg
        )
        let result = await Classifier.shared.classify(request, force: reason == .tabChange)
        await track("update classified session") {
            try await recorder.updateCurrentSession(
                category: result.category,
                source: result.source,
                siteLabel: result.siteLabel,
                screenshotId: screenshotId
            )
        }
    }

    private func openSession(for app: NSRunningApplication, title: String?, context: ParsedBrowserContext? = nil) async {
        guard let bundleId = app.bundleIdentifier else { return }
        guard AppCatalog.shouldTrack(bundleId: bundleId) else {
            await track("close untracked session") { try await recorder.closeCurrentSession() }
            return
        }

        let appName = AppCatalog.friendlyName(bundleId: bundleId, fallback: app.localizedName ?? bundleId)
        let isBrowser = BrowserDetector.isBrowser(bundleId)
        let browserContext: ParsedBrowserContext
        if !isBrowser {
            browserContext = .empty
        } else if let context {
            browserContext = context
        } else {
            browserContext = await resolvedBrowserContext(app: app, title: title, bundleId: bundleId)
        }

        if isBrowser, !SiteCatalog.shouldTrack(domain: browserContext.domain, pageTitle: browserContext.pageTitle, windowTitle: title) {
            if await recorder.hasActiveSession(for: bundleId) {
                await track("update browser context") {
                    try await recorder.updateCurrentSessionContext(
                        windowTitle: title,
                        siteLabel: browserContext.siteLabel ?? lastBrowserContext.siteLabel
                    )
                }
                return
            }
            await track("close untracked browser session") { try await recorder.closeCurrentSession() }
            return
        }

        // Resolve the deterministic authority ladder (user rule → app catalog →
        // site catalog → cached AI). A hit is authoritative: it sets the category
        // and suppresses live AI, so known apps like editors are never re-judged.
        let request = ClassificationRequest(
            bundleId: bundleId,
            appName: appName,
            windowTitle: title,
            imageData: nil
        )
        let deterministic = Classifier.shared.deterministicMatch(
            request: request,
            browserContext: browserContext
        )

        let siteLabel = deterministic?.siteLabel ?? browserContext.siteLabel ?? lastBrowserContext.siteLabel

        // Known-site default. When the live URL wasn't readable, the domain is nil
        // (so tier 3 above is skipped) yet the site label still carried forward as
        // e.g. "YouTube". Rather than leave a recognized site Uncategorized, fall
        // back to the catalog's default category for that label. Authoritative like
        // any catalog hit, so it also suppresses the live-AI pass below.
        var resolvedCategory = deterministic?.category ?? .uncategorized
        var resolvedSource = deterministic?.source
        if deterministic == nil,
           let labelHit = SiteCatalog.classification(forLabel: siteLabel) {
            resolvedCategory = labelHit.category
            resolvedSource = labelHit.source
        }
        let didResolve = deterministic != nil || resolvedCategory != .uncategorized

        // Topic (Screen Time genre) is orthogonal to category — resolved from the
        // app/site identity, not the productive verdict.
        let topic = ActivityTopic.resolve(
            bundleId: bundleId,
            domain: browserContext.domain ?? lastBrowserContext.domain,
            siteLabel: siteLabel
        )

        let sessionIdentity: String
        if isBrowser {
            sessionIdentity = SiteCatalog.sessionIdentity(bundleId: bundleId, context: browserContext)
        } else if let editorIdentity = editorSessionIdentity(bundleId: bundleId, title: title) {
            sessionIdentity = editorIdentity
        } else {
            sessionIdentity = bundleId
        }

        await track("open session") {
            try await recorder.openSession(
                bundleId: bundleId,
                appName: appName,
                windowTitle: title,
                category: resolvedCategory,
                categorySource: resolvedSource,
                siteLabel: siteLabel,
                topic: topic,
                sessionIdentity: sessionIdentity
            )
        }

        if !didResolve, AppSettings.shared.aiClassificationEnabled {
            await classifyCurrentSession(app: app, title: title, force: isBrowser || EditorContext.isEditor(bundleId: bundleId))
        }
    }

    private func editorSessionIdentity(bundleId: String, title: String?) -> String? {
        guard EditorContext.isEditor(bundleId: bundleId) else { return nil }
        if let project = EditorContext.parseProject(bundleId: bundleId, windowTitle: title) {
            return "editor:\(bundleId):project:\(project.lowercased())"
        }
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return "editor:\(bundleId):title:\(title.lowercased())"
        }
        return nil
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
        await track("update session category") {
            try await recorder.updateCurrentSession(
                category: result.category,
                source: result.source,
                siteLabel: result.siteLabel
            )
        }
    }

    private func normalizedTitle(_ title: String?) -> String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Reads the focused window title and folds the result into AX-health tracking.
    private func readTitle(for app: NSRunningApplication) -> String? {
        let title = normalizedTitle(WindowTitleReader.focusedWindowTitle(for: app))
        updateAccessibilityHealth(title: title, app: app)
        return title
    }

    private func updateAccessibilityHealth(title: String?, app: NSRunningApplication) {
        // Hard signal: trust revoked at runtime.
        guard WindowTitleReader.hasAccessibilityAccess() else {
            setAccessibilityHealthy(false)
            return
        }
        // Soft signal: a tracked app yielding no title for an extended run usually
        // means the AX tree isn't reachable even though trust is nominally granted.
        let bundleId = app.bundleIdentifier ?? ""
        if title == nil, AppCatalog.shouldTrack(bundleId: bundleId) {
            consecutiveTitleMisses += 1
        } else {
            consecutiveTitleMisses = 0
        }
        setAccessibilityHealthy(consecutiveTitleMisses < titleMissThreshold)
    }

    private func setAccessibilityHealthy(_ healthy: Bool) {
        guard healthy != accessibilityHealthy else { return }
        accessibilityHealthy = healthy
        FlowlogLog.tracking("Accessibility health changed: \(healthy ? "healthy" : "degraded")")
    }

    private func resolvedBrowserContext(app: NSRunningApplication, title: String?, bundleId: String) async -> ParsedBrowserContext {
        // Read the canonical URL off the main actor: the AX subtree walk is a
        // bounded breadth-first scan of up to 2500 nodes, each a synchronous
        // cross-process IPC call, and used to run inline on every tab change.
        let pid = app.processIdentifier
        let liveURL = await Task.detached(priority: .userInitiated) {
            WindowTitleReader.focusedURL(forPID: pid)
        }.value

        // Prefer the canonical URL read straight from the AX web area; fall back to
        // guessing the site from the window title only when the URL is unavailable.
        if let url = liveURL {
            let fromURL = SiteCatalog.parse(urlString: url)
            if fromURL.domain != nil {
                let pageTitle = SiteCatalog.parse(windowTitle: title).pageTitle
                let merged = ParsedBrowserContext(
                    domain: fromURL.domain,
                    siteLabel: fromURL.siteLabel,
                    pageTitle: pageTitle ?? fromURL.pageTitle
                )
                lastBrowserContext = merged
                return merged
            }
        }

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
        // Carry the previous site forward ONLY through a transient blank title
        // (mid-navigation, no identity yet). A distinct page title means we've moved
        // to a new page whose site we can't resolve — inheriting the old site here is
        // what mislabeled unrelated pages (e.g. "Substack" stamped on "Track Package").
        let hasOwnPageIdentity = !(parsed.pageTitle ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        if !hasOwnPageIdentity, lastBrowserContext.domain != nil || lastBrowserContext.siteLabel != nil {
            return ParsedBrowserContext(
                domain: lastBrowserContext.domain,
                siteLabel: lastBrowserContext.siteLabel,
                pageTitle: lastBrowserContext.pageTitle
            )
        }
        return parsed
    }

    func refreshMenuBarSession() {
        Task {
            do {
                if let snapshot = try await recorder.currentSnapshot() {
                    menuBarSession = MenuBarSessionInfo(
                        bundleId: snapshot.bundleId,
                        appName: snapshot.appName,
                        siteLabel: snapshot.siteLabel,
                        windowTitle: snapshot.windowTitle,
                        category: snapshot.category,
                        startedAt: snapshot.startedAt
                    )
                    return
                }
            } catch {
                FlowlogLog.tracking("Menu bar snapshot failed: \(error.localizedDescription)")
            }

            menuBarSession = frontmostSessionInfo(category: nil, startedAt: nil)
        }
    }

    private func track(_ label: String, operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            FlowlogLog.tracking("\(label): \(error.localizedDescription)")
        }
    }

    private func frontmostSessionInfo(
        category: ActivityCategory?,
        startedAt: Date?
    ) -> MenuBarSessionInfo? {
        let app = currentApp ?? WorkspaceMonitor.frontmostApplication
        guard let app, let bundleId = app.bundleIdentifier else { return nil }
        let appName = AppCatalog.friendlyName(
            bundleId: bundleId,
            fallback: app.localizedName ?? bundleId
        )
        return MenuBarSessionInfo(
            bundleId: bundleId,
            appName: appName,
            siteLabel: nil,
            windowTitle: currentTitle,
            category: category,
            startedAt: startedAt
        )
    }
}
