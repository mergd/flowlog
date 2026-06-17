import Foundation
import GRDB

struct Rule: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "rules"

    var id: Int64?
    var patternType: String
    var pattern: String
    var category: String
    var siteLabel: String?
    var createdAt: Date

    var activityCategory: ActivityCategory {
        ActivityCategory(rawValue: category) ?? .uncategorized
    }

    enum Columns: String, ColumnExpression {
        case id, patternType, pattern, category, siteLabel, createdAt
    }
}

extension Rule {
    enum PatternType: String, CaseIterable {
        case bundleId
        case windowTitle
        case siteLabel
        case domain

        var displayName: String {
            switch self {
            case .bundleId: "App"
            case .windowTitle: "Window title"
            case .siteLabel: "Site"
            case .domain: "Domain"
            }
        }

        var placeholder: String {
            switch self {
            case .bundleId: "com.example.app"
            case .windowTitle: "Contains text in window title"
            case .siteLabel: "YouTube"
            case .domain: "youtube.com"
            }
        }

        var icon: String {
            switch self {
            case .bundleId: "app.fill"
            case .windowTitle: "macwindow"
            case .siteLabel: "globe"
            case .domain: "link"
            }
        }
    }

    var patternTypeEnum: PatternType? {
        PatternType(rawValue: patternType)
    }

    var displayTitle: String {
        switch patternTypeEnum {
        case .bundleId:
            return AppCatalog.friendlyName(bundleId: pattern, fallback: pattern)
        case .siteLabel:
            return siteLabel ?? pattern
        case .domain:
            return SiteCatalog.classification(for: pattern)?.label ?? pattern
        default:
            return pattern
        }
    }

    var displaySubtitle: String? {
        switch patternTypeEnum {
        case .bundleId where AppCatalog.knownCategory(for: pattern) != nil:
            return nil
        case .bundleId:
            return pattern
        case .siteLabel:
            return pattern != displayTitle ? pattern : nil
        case .domain:
            return pattern != displayTitle ? pattern : nil
        case .windowTitle:
            return "Matches window titles containing this text"
        case .none:
            return patternType
        }
    }

    static func createTable(_ db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("patternType", .text).notNull()
            t.column("pattern", .text).notNull()
            t.column("category", .text).notNull()
            t.column("siteLabel", .text)
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(index: "rules_pattern", on: databaseTableName, columns: ["patternType", "pattern"], ifNotExists: true)
    }
}
