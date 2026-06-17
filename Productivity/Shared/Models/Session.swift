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

    var activityCategory: ActivityCategory {
        ActivityCategory(rawValue: category) ?? .uncategorized
    }

    var isOpen: Bool { end == nil }

    enum Columns: String, ColumnExpression {
        case id, bundleId, appName, windowTitle, start, end, duration
        case idleExcluded, category, categorySource, siteLabel, screenshotId
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
        }
        try db.create(index: "sessions_start", on: databaseTableName, columns: ["start"], ifNotExists: true)
        try db.create(index: "sessions_category", on: databaseTableName, columns: ["category"], ifNotExists: true)
    }
}
