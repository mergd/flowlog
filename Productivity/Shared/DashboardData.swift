import Foundation

enum DashboardData {
    static func categoryTotalsToday() -> [String: TimeInterval] {
        (try? DatabaseManager.shared.categoryTotalsToday()) ?? [:]
    }

    static func sessionsToday() -> [Session] {
        (try? DatabaseManager.shared.sessionsToday()) ?? []
    }

    static func usageBreakdownToday() -> [AppUsageGroup] {
        (try? DatabaseManager.shared.usageBreakdownToday()) ?? []
    }

    static func appTotalsToday() -> [(appName: String, bundleId: String, duration: TimeInterval, category: String)] {
        (try? DatabaseManager.shared.appTotalsToday()) ?? []
    }

    static func allRules() -> [Rule] {
        (try? DatabaseManager.shared.allRules()) ?? []
    }

    static func workLogs() -> [WorkLogEntry] {
        (try? DatabaseManager.shared.workLogs()) ?? []
    }
}
