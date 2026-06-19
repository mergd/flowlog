import Foundation

enum SessionRememberScope: Hashable, Identifiable {
    case none
    case app
    case site
    case windowTitle(String)

    var id: String {
        switch self {
        case .none: "none"
        case .app: "app"
        case .site: "site"
        case .windowTitle(let keyword): "title:\(keyword)"
        }
    }

    var label: String {
        switch self {
        case .none: "This session only"
        case .app: "App"
        case .site: "Site"
        case .windowTitle: "Window title"
        }
    }

    static func options(for session: Session) -> [SessionRememberScope] {
        var options: [SessionRememberScope] = [.none, .app]

        if session.siteLabel != nil || browserDomain(for: session) != nil {
            options.append(.site)
        }

        if let keyword = windowTitleKeyword(for: session) {
            options.append(.windowTitle(keyword))
        }

        return options
    }

    static func detailLabel(for scope: SessionRememberScope, session: Session) -> String {
        switch scope {
        case .none:
            return "This session only"
        case .app:
            return session.appName
        case .site:
            if let siteLabel = session.siteLabel, !siteLabel.isEmpty {
                return siteLabel
            }
            if let domain = browserDomain(for: session) {
                return domain
            }
            return "Site"
        case .windowTitle(let keyword):
            return "Title contains \"\(keyword)\""
        }
    }

    private static func browserDomain(for session: Session) -> String? {
        SiteCatalog.parse(windowTitle: session.windowTitle).domain
            ?? SiteCatalog.domain(from: session.windowTitle ?? "")
    }

    private static func windowTitleKeyword(for session: Session) -> String? {
        let displayTitle = SiteCatalog.displayTitle(for: session)
        if displayTitle.lowercased() != session.appName.lowercased(),
           displayTitle.count >= 3,
           displayTitle.count <= 48 {
            return displayTitle
        }

        if let title = session.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           title.count >= 3 {
            let context = SiteCatalog.parse(windowTitle: title)
            if let pageTitle = context.pageTitle, pageTitle.count >= 3, pageTitle.count <= 48 {
                return pageTitle
            }
        }

        if EditorContext.isEditor(bundleId: session.bundleId),
           let project = EditorContext.parseProject(bundleId: session.bundleId, windowTitle: session.windowTitle),
           project.count >= 3 {
            return project
        }

        return nil
    }
}
