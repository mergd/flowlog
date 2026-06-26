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

    func closeDanglingOpenSessions() throws {
        try queue.write { db in
            let now = Date()
            let sessions = try Session
                .filter(Session.Columns.end == nil)
                .fetchAll(db)

            for var session in sessions {
                let storedDuration = max(0, session.duration)
                let inferredEnd = min(session.start.addingTimeInterval(storedDuration), now)
                session.end = inferredEnd
                session.duration = max(0, inferredEnd.timeIntervalSince(session.start))
                if !AppCatalog.shouldTrack(bundleId: session.bundleId)
                    || session.duration < AppCatalog.minimumSessionDuration {
                    session.idleExcluded = true
                }
                try session.update(db)
            }
        }
    }

    func normalizeLegacySessionExclusions() throws {
        try queue.write { db in
            let sessions = try Session
                .filter(Session.Columns.idleExcluded == true)
                .fetchAll(db)

            for var session in sessions where AppCatalog.shouldTrack(bundleId: session.bundleId)
                && session.duration >= AppCatalog.minimumSessionDuration {
                session.idleExcluded = false
                try session.update(db)
            }
        }
    }

    var queue: DatabaseQueue {
        // Lazily set up if a reader (e.g. a restored dashboard window) touches the
        // DB before tracking has started. setup() is idempotent.
        if dbQueue == nil { try? setup() }
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
        migrator.registerMigration("v2") { db in
            try Pause.createTable(db)
        }
        migrator.registerMigration("v3") { db in
            // Screen Time–style topic axis, orthogonal to `category`.
            try db.alter(table: Session.databaseTableName) { t in
                t.add(column: "topic", .text)
            }
        }
        migrator.registerMigration("v4") { db in
            try db.alter(table: Session.databaseTableName) { t in
                t.add(column: "userDeleted", .boolean).notNull().defaults(to: false)
            }
        }
        return migrator
    }

    // MARK: - Pauses (deliberate snoozes)

    @discardableResult
    func beginPause(start: Date, plannedEnd: Date?) throws -> Int64 {
        try queue.write { db in
            var pause = Pause(id: nil, start: start, end: plannedEnd)
            try pause.insert(db)
            return db.lastInsertedRowID
        }
    }

    func endPause(id: Int64, end: Date) throws {
        try queue.write { db in
            if var pause = try Pause.fetchOne(db, key: id) {
                pause.end = end
                try pause.update(db)
            }
        }
    }

    func pauses(in range: Range<Date>) throws -> [Pause] {
        try queue.read { db in
            try Pause
                .filter(Pause.Columns.start < range.upperBound)
                .filter(Pause.Columns.end == nil || Pause.Columns.end > range.lowerBound)
                .order(Pause.Columns.start.asc)
                .fetchAll(db)
        }
    }

    func sessionsToday() throws -> [Session] {
        try includedSessionsToday()
            .filter { AppCatalog.shouldDisplay(bundleId: $0.bundleId, duration: $0.duration, appName: $0.appName) }
    }

    /// Today's activity grouped into intent-coherent blocks (the timeline view).
    /// Unlike the stats path, this counts *all* tracked activity — brief slices
    /// aren't excluded as noise; they fold into blocks as the texture of attention.
    func blocksToday() throws -> [ActivityBlock] {
        let start = Calendar.current.startOfDay(for: Date())
        let slices = try queue.read { db in
            try Session
                .filter(Session.Columns.start >= start)
                .order(Session.Columns.start.asc)
                .fetchAll(db)
        }
        .filter { AppCatalog.shouldIncludeInStats(bundleId: $0.bundleId, appName: $0.appName) }
        .filter { !$0.userDeleted }
        return BlockBuilder.build(from: slices)
    }

    func blocks(in range: Range<Date>) throws -> [ActivityBlock] {
        let slices = try queue.read { db in
            try Session
                .filter(Session.Columns.start >= range.lowerBound)
                .filter(Session.Columns.start < range.upperBound)
                .order(Session.Columns.start.asc)
                .fetchAll(db)
        }
        .filter { AppCatalog.shouldIncludeInStats(bundleId: $0.bundleId, appName: $0.appName) }
        .filter { !$0.userDeleted }
        return BlockBuilder.build(from: slices)
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
        return !session.idleExcluded && !session.userDeleted
    }

    func markSessionsDeleted(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try queue.write { db in
            for id in ids {
                guard var session = try Session.fetchOne(db, key: id) else { continue }
                session.userDeleted = true
                try session.update(db)
            }
        }
    }

    func sessions(in range: Range<Date>) throws -> [Session] {
        try queue.read { db in
            try Session
                .filter(Session.Columns.start >= range.lowerBound)
                .filter(Session.Columns.start < range.upperBound)
                .filter(Session.Columns.idleExcluded == false)
                .filter(Session.Columns.userDeleted == false)
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

    /// Stats-included sessions for an arbitrary range (same filtering as the "today" path).
    func includedSessions(in range: Range<Date>) throws -> [Session] {
        try queue.read { db in
            try Session
                .filter(Session.Columns.start >= range.lowerBound)
                .filter(Session.Columns.start < range.upperBound)
                .order(Session.Columns.start.asc)
                .fetchAll(db)
                .filter(isIncludedInStats)
        }
    }

    /// Display-worthy sessions for an arbitrary range.
    func sessionsForDisplay(in range: Range<Date>) throws -> [Session] {
        try includedSessions(in: range)
            .filter { AppCatalog.shouldDisplay(bundleId: $0.bundleId, duration: $0.duration, appName: $0.appName) }
    }

    func categoryTotals(in range: Range<Date>) throws -> [String: TimeInterval] {
        let sessions = try includedSessions(in: range)
        var totals: [String: TimeInterval] = [:]
        for s in sessions {
            totals[s.category, default: 0] += s.duration
        }
        return totals
    }

    func topicTotalsToday() throws -> [String: TimeInterval] {
        try includedSessionsToday().reduce(into: [:]) { totals, s in
            totals[Self.resolvedTopic(for: s).rawValue, default: 0] += s.duration
        }
    }

    func topicTotals(in range: Range<Date>) throws -> [String: TimeInterval] {
        try includedSessions(in: range).reduce(into: [:]) { totals, s in
            totals[Self.resolvedTopic(for: s).rawValue, default: 0] += s.duration
        }
    }

    /// Topic for a session, deriving it on read for rows written before the topic
    /// axis existed (or that were stored as uncategorized).
    private static func resolvedTopic(for session: Session) -> ActivityTopic {
        if session.activityTopic != .uncategorized { return session.activityTopic }
        let context = BrowserDetector.isBrowser(session.bundleId)
            ? SiteCatalog.parse(windowTitle: session.windowTitle)
            : ParsedBrowserContext.empty
        return ActivityTopic.resolve(
            bundleId: session.bundleId,
            domain: context.domain,
            siteLabel: session.siteLabel ?? context.siteLabel
        )
    }

    func distractingDuration(since: Date) throws -> TimeInterval {
        try queue.read { db in
            let rows = try Session
                .filter(Session.Columns.start >= since)
                .filter(Session.Columns.category == ActivityCategory.distracting.rawValue)
                .filter(Session.Columns.idleExcluded == false)
                .filter(Session.Columns.userDeleted == false)
                .fetchAll(db)
            return rows.reduce(0) { $0 + $1.duration }
        }
    }

    /// Productive vs distracting non-idle seconds since `since`. Used to detect whether the
    /// user is currently focused, independent of the longer rolling nudge window.
    func recentFocusBalance(since: Date) throws -> (productive: TimeInterval, distracting: TimeInterval) {
        try queue.read { db in
            let rows = try Session
                .filter(Session.Columns.start >= since)
                .filter(Session.Columns.idleExcluded == false)
                .filter(Session.Columns.userDeleted == false)
                .fetchAll(db)
            var productive: TimeInterval = 0
            var distracting: TimeInterval = 0
            for row in rows {
                switch row.activityCategory {
                case .productive: productive += row.duration
                case .distracting: distracting += row.duration
                default: break
                }
            }
            return (productive, distracting)
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
                let siteLabel = SiteCatalog.sanitizedSiteLabel(
                    session.siteLabel ?? context.siteLabel,
                    bundleId: bundleId,
                    appName: appName
                ) ?? context.siteLabel ?? domain ?? appName
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
