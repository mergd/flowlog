import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue!

    private init() {}

    func setup() throws {
        if dbQueue != nil { return }
        let url = try Self.databaseURL()
        dbQueue = try DatabaseQueue(path: url.path)
        try migrator.migrate(dbQueue)
    }

    var queue: DatabaseQueue {
        guard let dbQueue else { fatalError("Database not setup") }
        return dbQueue
    }

    private static func databaseURL() throws -> URL {
        let dir = try AppInfo.applicationSupportDirectory()
        return dir.appendingPathComponent("productivity.sqlite")
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try Session.createTable(db)
            try Rule.createTable(db)
        }
        return migrator
    }

    func sessionsToday() throws -> [Session] {
        try includedSessionsToday()
            .filter { AppCatalog.shouldDisplay(bundleId: $0.bundleId, duration: $0.duration, appName: $0.appName) }
    }

    private func includedSessionsToday() throws -> [Session] {
        let start = Calendar.current.startOfDay(for: Date())
        return try queue.read { db in
            try Session
                .filter(Session.Columns.start >= start)
                .order(Session.Columns.start.desc)
                .fetchAll(db)
                .filter(isIncludedInStats)
        }
    }

    private func isIncludedInStats(_ session: Session) -> Bool {
        guard AppCatalog.shouldIncludeInStats(bundleId: session.bundleId, appName: session.appName) else {
            return false
        }
        if !session.idleExcluded { return true }
        // Older builds marked sub-minimum sessions idleExcluded on close; keep those in totals.
        return session.duration < AppCatalog.minimumSessionDuration
    }

    func sessions(in range: Range<Date>) throws -> [Session] {
        try queue.read { db in
            try Session
                .filter(Session.Columns.start >= range.lowerBound)
                .filter(Session.Columns.start < range.upperBound)
                .filter(Session.Columns.idleExcluded == false)
                .order(Session.Columns.start.asc)
                .fetchAll(db)
        }
    }

    func categoryTotalsToday() throws -> [String: TimeInterval] {
        let sessions = try includedSessionsToday()
        var totals: [String: TimeInterval] = [:]
        for s in sessions {
            totals[s.category, default: 0] += s.duration
        }
        return totals
    }

    func distractingDuration(since: Date) throws -> TimeInterval {
        try queue.read { db in
            let rows = try Session
                .filter(Session.Columns.start >= since)
                .filter(Session.Columns.category == ActivityCategory.distracting.rawValue)
                .filter(Session.Columns.idleExcluded == false)
                .fetchAll(db)
            return rows.reduce(0) { $0 + $1.duration }
        }
    }

    func usageBreakdownToday() throws -> [AppUsageGroup] {
        let sessions = try includedSessionsToday()
        var appMap: [String: (appName: String, duration: TimeInterval, category: String)] = [:]
        var siteMap: [String: [String: (siteLabel: String, domain: String?, duration: TimeInterval, category: String)]] = [:]

        for session in sessions {
            let bundleId = session.bundleId
            let appName = AppCatalog.friendlyName(bundleId: bundleId, fallback: session.appName)
            let category = Self.resolvedCategory(for: session)

            if BrowserDetector.isBrowser(bundleId) {
                let context = SiteCatalog.parse(windowTitle: session.windowTitle)
                let domain = context.domain
                let siteLabel = session.siteLabel ?? context.siteLabel ?? domain ?? "Unknown site"
                let siteKey = SiteCatalog.siteKey(domain: domain, siteLabel: siteLabel)

                var appEntry = appMap[bundleId] ?? (appName, 0, category)
                appEntry.duration += session.duration
                appEntry.category = Self.mergeCategory(appEntry.category, with: category)
                appMap[bundleId] = appEntry

                var sites = siteMap[bundleId] ?? [:]
                var siteEntry = sites[siteKey] ?? (siteLabel, domain, 0, category)
                siteEntry.duration += session.duration
                siteEntry.siteLabel = siteLabel
                siteEntry.category = Self.mergeCategory(siteEntry.category, with: category)
                sites[siteKey] = siteEntry
                siteMap[bundleId] = sites
            } else {
                var entry = appMap[bundleId] ?? (appName, 0, category)
                entry.duration += session.duration
                entry.category = Self.mergeCategory(entry.category, with: category)
                appMap[bundleId] = entry
            }
        }

        return appMap.compactMap { bundleId, app in
            guard app.duration >= AppCatalog.minimumSessionDuration else { return nil }

            let sites = (siteMap[bundleId] ?? [:])
                .compactMap { key, site -> SiteUsageRow? in
                    guard site.duration >= AppCatalog.minimumSessionDuration else { return nil }
                    return SiteUsageRow(
                        id: "\(bundleId)|\(key)",
                        siteLabel: site.siteLabel,
                        domain: site.domain,
                        duration: site.duration,
                        category: site.category
                    )
                }
                .sorted { $0.duration > $1.duration }

            return AppUsageGroup(
                id: bundleId,
                appName: app.appName,
                bundleId: bundleId,
                duration: app.duration,
                category: app.category,
                sites: sites
            )
        }
        .sorted { $0.duration > $1.duration }
    }

    func appTotalsToday() throws -> [(appName: String, bundleId: String, duration: TimeInterval, category: String)] {
        try usageBreakdownToday().map { ($0.appName, $0.bundleId, $0.duration, $0.category) }
    }

    private static func resolvedCategory(for session: Session) -> String {
        if session.activityCategory != .uncategorized { return session.category }
        if !BrowserDetector.isBrowser(session.bundleId),
           let known = AppCatalog.knownCategory(for: session.bundleId) {
            return known.rawValue
        }
        return session.category
    }

    private static func mergeCategory(_ existing: String, with incoming: String) -> String {
        if existing == ActivityCategory.uncategorized.rawValue { return incoming }
        if incoming == ActivityCategory.uncategorized.rawValue { return existing }
        return incoming
    }

    func allRules() throws -> [Rule] {
        try queue.read { db in
            try Rule.order(Rule.Columns.createdAt.desc).fetchAll(db)
        }
    }
}
