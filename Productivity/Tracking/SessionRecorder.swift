import Foundation
import GRDB

actor SessionRecorder {
    private var currentSessionId: Int64?
    private var currentKey: String?
    private var currentBundleId: String?
    private var pausedForIdle = false

    func openSession(
        bundleId: String,
        appName: String,
        windowTitle: String?,
        category: ActivityCategory = .uncategorized,
        categorySource: ClassificationSource? = nil,
        siteLabel: String? = nil,
        screenshotId: String? = nil,
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
            siteLabel: siteLabel,
            screenshotId: screenshotId
        )

        let insertedId = try await DatabaseManager.shared.queue.write { db -> Int64 in
            var inserted = session
            try inserted.insert(db)
            return db.lastInsertedRowID
        }
        currentSessionId = insertedId
        currentKey = key
        currentBundleId = bundleId
        pausedForIdle = false
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
                session.category = category.rawValue
                session.categorySource = source.rawValue
                if let siteLabel, !siteLabel.isEmpty {
                    session.siteLabel = siteLabel
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
                if let siteLabel, !siteLabel.isEmpty { session.siteLabel = siteLabel }
                if let category { session.category = category.rawValue }
                if let categorySource { session.categorySource = categorySource.rawValue }
                try session.update(db)
            }
        }
    }

    func tickDuration() async throws {
        guard let id = currentSessionId, !pausedForIdle else { return }
        try await DatabaseManager.shared.queue.write { db in
            if var session = try Session.fetchOne(db, key: id) {
                session.duration = Date().timeIntervalSince(session.start)
                try session.update(db)
            }
        }
    }

    func setIdlePaused(_ paused: Bool) async throws {
        if paused && !pausedForIdle {
            try await closeCurrentSession(markIdleExcluded: true)
            pausedForIdle = true
        } else if !paused {
            pausedForIdle = false
        }
    }

    func closeCurrentSession(markIdleExcluded: Bool = false) async throws {
        guard let id = currentSessionId else { return }
        try await DatabaseManager.shared.queue.write { db in
            if var session = try Session.fetchOne(db, key: id) {
                let end = Date()
                session.end = end
                session.duration = end.timeIntervalSince(session.start)
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
