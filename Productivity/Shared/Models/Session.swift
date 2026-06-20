import Foundation
import GRDB

struct Session: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "sessions"

    var id: Int64?
    var bundleId: String
    var appName: String
    var windowTitle: String?
    var start: Date
    var end: Date?
    var duration: TimeInterval
    var idleExcluded: Bool
    var category: String
    var categorySource: String?
    var siteLabel: String?
    var screenshotId: String?
    /// Screen Time–style topic (genre), independent of `category`. Nil for rows
    /// written before the topic axis existed; resolved on read where possible.
    var topic: String?
    /// User removed this slice from the detail timeline and day stats.
    var userDeleted: Bool

    var activityCategory: ActivityCategory {
        ActivityCategory(rawValue: category) ?? .uncategorized
    }

    var activityTopic: ActivityTopic {
        topic.flatMap(ActivityTopic.init(rawValue:)) ?? .uncategorized
    }

    var isOpen: Bool { end == nil }

    enum Columns: String, ColumnExpression {
        case id, bundleId, appName, windowTitle, start, end, duration
        case idleExcluded, category, categorySource, siteLabel, screenshotId, topic, userDeleted
    }
}

/// A deliberate snooze interval — the user paused tracking on purpose. Stored
/// separately from activity so it reads as "paused", not "untracked".
struct Pause: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "pauses"

    var id: Int64?
    var start: Date
    var end: Date?

    enum Columns: String, ColumnExpression {
        case id, start, end
    }

    static func createTable(_ db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("start", .datetime).notNull()
            t.column("end", .datetime)
        }
        try db.create(index: "pauses_start", on: databaseTableName, columns: ["start"], ifNotExists: true)
    }
}

extension Session {
    static func createTable(_ db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("bundleId", .text).notNull()
            t.column("appName", .text).notNull()
            t.column("windowTitle", .text)
            t.column("start", .datetime).notNull()
            t.column("end", .datetime)
            t.column("duration", .double).notNull().defaults(to: 0)
            t.column("idleExcluded", .boolean).notNull().defaults(to: false)
            t.column("category", .text).notNull().defaults(to: ActivityCategory.uncategorized.rawValue)
            t.column("categorySource", .text)
            t.column("siteLabel", .text)
            t.column("screenshotId", .text)
            t.column("topic", .text)
            t.column("userDeleted", .boolean).notNull().defaults(to: false)
        }
        try db.create(index: "sessions_start", on: databaseTableName, columns: ["start"], ifNotExists: true)
        try db.create(index: "sessions_category", on: databaseTableName, columns: ["category"], ifNotExists: true)
    }
}
