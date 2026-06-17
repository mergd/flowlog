import Foundation
import GRDB

struct WorkLogEntry: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "work_logs"

    var id: Int64?
    var periodStart: Date
    var periodEnd: Date
    var headline: String
    var narrative: String
    var primaryFocus: String?
    var distractionsJSON: String?
    var productiveMinutes: Int
    var distractingMinutes: Int
    var createdAt: Date

    var distractions: [String] {
        guard let data = distractionsJSON?.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    enum Columns: String, ColumnExpression {
        case id, periodStart, periodEnd, headline, narrative, primaryFocus
        case distractionsJSON, productiveMinutes, distractingMinutes, createdAt
    }
}

extension WorkLogEntry {
    static func createTable(_ db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("periodStart", .datetime).notNull()
            t.column("periodEnd", .datetime).notNull()
            t.column("headline", .text).notNull()
            t.column("narrative", .text).notNull()
            t.column("primaryFocus", .text)
            t.column("distractionsJSON", .text)
            t.column("productiveMinutes", .integer).notNull()
            t.column("distractingMinutes", .integer).notNull()
            t.column("createdAt", .datetime).notNull()
        }
    }
}

struct ClassificationResult: Sendable {
    let category: ActivityCategory
    let siteLabel: String?
    let confidence: Double
    let reason: String?
    let source: ClassificationSource
}

struct ClassificationRequest: Sendable {
    let bundleId: String
    let appName: String
    let windowTitle: String?
    let imageData: Data?
}
