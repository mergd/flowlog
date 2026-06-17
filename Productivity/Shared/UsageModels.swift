import Foundation

struct SiteUsageRow: Identifiable, Sendable {
    let id: String
    let siteLabel: String
    let domain: String?
    let duration: TimeInterval
    let category: String
}

struct AppUsageGroup: Identifiable, Sendable {
    let id: String
    let appName: String
    let bundleId: String
    let duration: TimeInterval
    let category: String
    let sites: [SiteUsageRow]

    var isBrowser: Bool { !sites.isEmpty }
}
