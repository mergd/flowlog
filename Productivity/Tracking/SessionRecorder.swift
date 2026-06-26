import Foundation
import GRDB

actor SessionRecorder {
    private var currentSessionId: Int64?
    private var currentKey: String?
    private var currentBundleId: String?

    func openSession(
        bundleId: String,
        appName: String,
        windowTitle: String?,
        category: ActivityCategory = .uncategorized,
        categorySource: ClassificationSource? = nil,
        siteLabel: String? = nil,
        screenshotId: String? = nil,
        topic: ActivityTopic? = nil,
        sessionIdentity: String? = nil
    ) async throws {
        let key = sessionIdentity ?? sessionKey(bundleId: bundleId, windowTitle: windowTitle)
        if currentKey == key, currentSessionId != nil { return }

        try await closeCurrentSession()

        let session = Session(
            id: nil,
            bundleId: bundleId,
            appName: appName,
            windowTitle: windowTitle,
            start: Date(),
            end: nil,
            duration: 0,
            idleExcluded: false,
            category: category.rawValue,
            categorySource: categorySource?.rawValue,
            siteLabel: SiteCatalog.sanitizedSiteLabel(siteLabel, bundleId: bundleId, appName: appName),
            screenshotId: screenshotId,
            topic: (topic ?? .uncategorized).rawValue,
            userDeleted: false
        )

        let insertedId = try await DatabaseManager.shared.queue.write { db -> Int64 in
            var inserted = session
            try inserted.insert(db)
            return db.lastInsertedRowID
        }
        currentSessionId = insertedId
        currentKey = key
        currentBundleId = bundleId
    }

    func updateCurrentSession(
        category: ActivityCategory,
        source: ClassificationSource,
        siteLabel: String?,
        screenshotId: String? = nil
    ) async throws {
        guard let id = currentSessionId else { return }
        try await DatabaseManager.shared.queue.write { db in
            if var session = try Session.fetchOne(db, key: id) {
                var category = category
                var source = source
                // Authority guard: an AI verdict (live or cached) must never override a
                // hardcoded non-browser app. For editors/IDEs/terminals the app *is* the
                // intent, so pin to the catalog regardless of what the AI guessed. This
                // closes a race where a stale bundleId routed a known dev app to the AI.
                if source.isAIDerived,
                   !BrowserDetector.isBrowser(session.bundleId),
                   let pinned = AppCatalog.classification(for: session.bundleId) {
                    category = pinned.category
                    source = pinned.source
                }
                // Never let a later abstention (AI/screenshot returning
                // uncategorized) erase a category we already resolved — e.g. a
                // known-site default. Abstaining is not a verdict.
                let isAbstention = category == .uncategorized
                let alreadyClassified = session.category != ActivityCategory.uncategorized.rawValue
                if !(isAbstention && alreadyClassified) {
                    session.category = category.rawValue
                    session.categorySource = source.rawValue
                }
                if let cleaned = SiteCatalog.sanitizedSiteLabel(
                    siteLabel,
                    bundleId: session.bundleId,
                    appName: session.appName
                ) {
                    session.siteLabel = cleaned
                }
                if let screenshotId { session.screenshotId = screenshotId }
                try session.update(db)
            }
        }
    }

    func updateCurrentSessionContext(
        windowTitle: String?,
        siteLabel: String?,
        category: ActivityCategory? = nil,
        categorySource: ClassificationSource? = nil
    ) async throws {
        guard let id = currentSessionId else { return }
        try await DatabaseManager.shared.queue.write { db in
            if var session = try Session.fetchOne(db, key: id) {
                if let windowTitle { session.windowTitle = windowTitle }
                if let cleaned = SiteCatalog.sanitizedSiteLabel(
                    siteLabel,
                    bundleId: session.bundleId,
                    appName: session.appName
                ) {
                    session.siteLabel = cleaned
                }
                if let category { session.category = category.rawValue }
                if let categorySource { session.categorySource = categorySource.rawValue }
                try session.update(db)
            }
        }
    }

    func tickDuration() async throws {
        guard let id = currentSessionId else { return }
        try await DatabaseManager.shared.queue.write { db in
            if var session = try Session.fetchOne(db, key: id) {
                session.duration = Date().timeIntervalSince(session.start)
                try session.update(db)
            }
        }
    }

    func closeCurrentSession(markIdleExcluded: Bool = false) async throws {
        guard let id = currentSessionId else { return }
        try await DatabaseManager.shared.queue.write { db in
            if var session = try Session.fetchOne(db, key: id) {
                let end = Date()
                session.end = end
                session.duration = end.timeIntervalSince(session.start)
                // Brief slices are no longer excluded as "noise" — bouncing between
                // apps is the normal texture of attention and folds into blocks.
                // Only genuinely untracked apps (and explicit idle) are excluded.
                if markIdleExcluded || !AppCatalog.shouldTrack(bundleId: session.bundleId) {
                    session.idleExcluded = true
                }
                try session.update(db)
            }
        }
        currentSessionId = nil
        currentKey = nil
        currentBundleId = nil
    }

    func hasActiveSession(for bundleId: String) -> Bool {
        currentSessionId != nil && currentBundleId == bundleId
    }

    var activeSessionId: Int64? { currentSessionId }

    func currentSnapshot() async throws -> CurrentSessionSnapshot? {
        guard let id = currentSessionId else { return nil }
        return try await DatabaseManager.shared.queue.read { db in
            guard let session = try Session.fetchOne(db, key: id) else { return nil }
            return CurrentSessionSnapshot(
                bundleId: session.bundleId,
                appName: session.appName,
                siteLabel: session.siteLabel,
                windowTitle: session.windowTitle,
                category: session.activityCategory,
                startedAt: session.start
            )
        }
    }

    private func sessionKey(bundleId: String, windowTitle: String?) -> String {
        "\(bundleId)|\(windowTitle ?? "")"
    }
}
