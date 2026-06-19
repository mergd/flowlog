import Foundation

enum DashboardData {
    static func categoryTotalsToday() -> [String: TimeInterval] {
        (try? DatabaseManager.shared.categoryTotalsToday()) ?? [:]
    }

    static func sessionsToday() -> [Session] {
        (try? DatabaseManager.shared.sessionsToday()) ?? []
    }

    static func blocksToday() -> [ActivityBlock] {
        (try? DatabaseManager.shared.blocksToday()) ?? []
    }

    static func blocks(in range: Range<Date>) -> [ActivityBlock] {
        (try? DatabaseManager.shared.blocks(in: range)) ?? []
    }

    static func pauses(in range: Range<Date>) -> [Pause] {
        (try? DatabaseManager.shared.pauses(in: range)) ?? []
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

    static func sessions(in range: Range<Date>) -> [Session] {
        (try? DatabaseManager.shared.sessionsForDisplay(in: range)) ?? []
    }

    static func categoryTotals(in range: Range<Date>) -> [String: TimeInterval] {
        (try? DatabaseManager.shared.categoryTotals(in: range)) ?? [:]
    }

    static func topicTotalsToday() -> [String: TimeInterval] {
        (try? DatabaseManager.shared.topicTotalsToday()) ?? [:]
    }

    static func topicTotals(in range: Range<Date>) -> [String: TimeInterval] {
        (try? DatabaseManager.shared.topicTotals(in: range)) ?? [:]
    }
}
