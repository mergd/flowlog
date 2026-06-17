import Foundation

struct MenuBarSessionInfo: Equatable, Sendable {
    let bundleId: String
    let appName: String
    let siteLabel: String?
    let windowTitle: String?
    let category: ActivityCategory?
    let startedAt: Date?
    let isIdle: Bool

    var title: String {
        SiteCatalog.displayTitle(
            bundleId: bundleId,
            appName: appName,
            siteLabel: siteLabel,
            windowTitle: windowTitle
        )
    }

    var subtitle: String? {
        SiteCatalog.displaySubtitle(
            bundleId: bundleId,
            appName: appName,
            siteLabel: siteLabel,
            windowTitle: windowTitle
        )
    }
}

struct CurrentSessionSnapshot: Sendable {
    let bundleId: String
    let appName: String
    let siteLabel: String?
    let windowTitle: String?
    let category: ActivityCategory
    let startedAt: Date
}
