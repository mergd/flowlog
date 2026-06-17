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
        if EditorContext.isEditor(bundleId: bundleId),
           let file = EditorContext.parseFileName(windowTitle: windowTitle) {
            return file
        }
        if let siteLabel,
           !siteLabel.isEmpty,
           siteLabel.lowercased() != appName.lowercased() {
            return siteLabel
        }
        if EditorContext.isEditor(bundleId: bundleId),
           let project = EditorContext.parseProject(bundleId: bundleId, windowTitle: windowTitle) {
            return project
        }
        return appName
    }

    var subtitle: String? {
        if EditorContext.isEditor(bundleId: bundleId) {
            if let project = EditorContext.parseProject(bundleId: bundleId, windowTitle: windowTitle),
               title.lowercased() != project.lowercased() {
                return project
            }
            if title.lowercased() != appName.lowercased() {
                return appName
            }
            return nil
        }
        guard BrowserDetector.isBrowser(bundleId) else { return nil }
        if title.lowercased() != appName.lowercased() {
            return appName
        }
        return nil
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
