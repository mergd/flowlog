import Foundation

struct ParsedBrowserContext: Sendable {
    var domain: String?
    var siteLabel: String?
    var pageTitle: String?

    static let empty = ParsedBrowserContext()
}

enum SiteCatalog {
    private static let browserSuffixes = [
        " - Google Chrome",
        " - Chrome",
        " - Safari",
        " - Arc",
        " - Firefox",
        " - Microsoft Edge",
        " - Brave",
        " - Opera",
        " - Vivaldi",
    ]

    private static let ignoredTitles: Set<String> = [
        "new tab",
        "start page",
        "about:blank",
        "untitled",
        "favorites",
        "top sites",
        "private browsing",
    ]

    private static let titleDomainHints: [String: String] = [
        "github": "github.com",
        "gitlab": "gitlab.com",
        "youtube": "youtube.com",
        "gmail": "gmail.com",
        "google docs": "docs.google.com",
        "google drive": "drive.google.com",
        "notion": "notion.so",
        "figma": "figma.com",
        "linear": "linear.app",
        "slack": "slack.com",
        "reddit": "reddit.com",
        "twitter": "twitter.com",
        "x /": "x.com",
        "stackoverflow": "stackoverflow.com",
        "wikipedia": "wikipedia.org",
        "netflix": "netflix.com",
        "twitch": "twitch.tv",
        "linkedin": "linkedin.com",
        "chatgpt": "chatgpt.com",
        "claude": "claude.ai",
    ]

    private static let knownSites: [String: (label: String, category: ActivityCategory)] = [
        // Dev
        "github.com": ("GitHub", .productive),
        "gitlab.com": ("GitLab", .productive),
        "bitbucket.org": ("Bitbucket", .productive),
        "stackoverflow.com": ("Stack Overflow", .productive),
        "developer.apple.com": ("Apple Developer", .productive),
        "localhost": ("Localhost", .productive),
        "vercel.com": ("Vercel", .productive),
        "railway.app": ("Railway", .productive),
        "supabase.com": ("Supabase", .productive),

        // Work
        "notion.so": ("Notion", .productive),
        "notion.site": ("Notion", .productive),
        "linear.app": ("Linear", .productive),
        "figma.com": ("Figma", .productive),
        "docs.google.com": ("Google Docs", .productive),
        "drive.google.com": ("Google Drive", .neutral),
        "sheets.google.com": ("Google Sheets", .productive),
        "calendar.google.com": ("Google Calendar", .productive),
        "mail.google.com": ("Gmail", .neutral),
        "gmail.com": ("Gmail", .neutral),
        "slack.com": ("Slack", .neutral),
        "app.slack.com": ("Slack", .neutral),

        // AI
        "chatgpt.com": ("ChatGPT", .productive),
        "claude.ai": ("Claude", .productive),
        "perplexity.ai": ("Perplexity", .productive),

        // Search / reference
        "google.com": ("Google", .neutral),
        "duckduckgo.com": ("DuckDuckGo", .neutral),
        "wikipedia.org": ("Wikipedia", .neutral),

        // Social / entertainment
        "youtube.com": ("YouTube", .distracting),
        "youtu.be": ("YouTube", .distracting),
        "reddit.com": ("Reddit", .distracting),
        "old.reddit.com": ("Reddit", .distracting),
        "twitter.com": ("Twitter", .distracting),
        "x.com": ("X", .distracting),
        "instagram.com": ("Instagram", .distracting),
        "facebook.com": ("Facebook", .distracting),
        "tiktok.com": ("TikTok", .distracting),
        "netflix.com": ("Netflix", .distracting),
        "twitch.tv": ("Twitch", .distracting),
        "news.ycombinator.com": ("Hacker News", .neutral),
        "linkedin.com": ("LinkedIn", .neutral),
    ]

    static func siteKey(domain: String?, siteLabel: String?) -> String {
        if let domain { return normalizeDomain(domain) }
        if let siteLabel, !siteLabel.isEmpty { return siteLabel.lowercased() }
        return "_unknown"
    }

    static func sessionIdentity(bundleId: String, context: ParsedBrowserContext) -> String {
        if let domain = context.domain {
            return "\(bundleId)|\(normalizeDomain(domain))"
        }
        return "\(bundleId)|_browser"
    }

    static func domainChanged(from old: ParsedBrowserContext, to new: ParsedBrowserContext) -> Bool {
        let oldDomain = old.domain.map(normalizeDomain)
        let newDomain = new.domain.map(normalizeDomain)
        if oldDomain == nil, newDomain == nil { return false }
        return oldDomain != newDomain
    }

    static func displayTitle(for session: Session) -> String {
        if EditorContext.isEditor(bundleId: session.bundleId),
           let file = EditorContext.parseFileName(windowTitle: session.windowTitle) {
            return file
        }

        if let siteLabel = session.siteLabel,
           !siteLabel.isEmpty,
           siteLabel.lowercased() != session.appName.lowercased() {
            return siteLabel
        }

        let context = parse(windowTitle: session.windowTitle)
        if let label = context.siteLabel, !isBrowserOnlyTitle(label) {
            return label
        }
        if let pageTitle = context.pageTitle {
            return pageTitle
        }
        if let domain = context.domain {
            return knownSites[normalizeDomain(domain)]?.label ?? domain
        }
        if EditorContext.isEditor(bundleId: session.bundleId),
           let project = EditorContext.parseProject(bundleId: session.bundleId, windowTitle: session.windowTitle) {
            return project
        }
        return session.appName
    }

    static func displaySubtitle(for session: Session) -> String? {
        if EditorContext.isEditor(bundleId: session.bundleId) {
            if let project = EditorContext.parseProject(bundleId: session.bundleId, windowTitle: session.windowTitle) {
                let title = displayTitle(for: session)
                if title.lowercased() != project.lowercased() {
                    return project
                }
            }
            if displayTitle(for: session).lowercased() != session.appName.lowercased() {
                return session.appName
            }
            return nil
        }

        let context = parse(windowTitle: session.windowTitle)
        let title = displayTitle(for: session)

        if BrowserDetector.isBrowser(session.bundleId) {
            if session.appName.lowercased() != title.lowercased() {
                return session.appName
            }
            if let pageTitle = context.pageTitle,
               pageTitle.lowercased() != title.lowercased() {
                return pageTitle
            }
            if let domain = context.domain,
               title.lowercased() != domain.lowercased(),
               knownSites[normalizeDomain(domain)]?.label.lowercased() != title.lowercased() {
                return domain
            }
            return nil
        }

        if let windowTitle = session.windowTitle,
           !windowTitle.isEmpty,
           windowTitle != title,
           windowTitle != session.appName {
            return windowTitle
        }
        return nil
    }

    static func parse(windowTitle: String?) -> ParsedBrowserContext {
        guard let raw = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .empty
        }
        if ignoredTitles.contains(raw.lowercased()) { return .empty }

        let domain = domain(from: raw)
        let pageTitle = strippedPageTitle(from: raw)
        let siteLabel = friendlySiteLabel(domain: domain, pageTitle: pageTitle, windowTitle: raw)
        return ParsedBrowserContext(domain: domain, siteLabel: siteLabel, pageTitle: pageTitle)
    }

    static func shouldTrack(domain: String?, pageTitle: String?, windowTitle: String?) -> Bool {
        let title = (windowTitle ?? pageTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return false }
        if ignoredTitles.contains(title.lowercased()) { return false }
        if title.lowercased().hasPrefix("chrome://") || title.lowercased().hasPrefix("about:") { return false }
        if domain == nil, isBrowserOnlyTitle(title) { return false }
        return true
    }

    static func domain(from text: String) -> String? {
        if let urlDomain = OCRPreprocessor.extractDomain(from: text) {
            return normalizeDomain(urlDomain)
        }

        let pattern = #/(?:^|[\s(])([a-z0-9][-a-z0-9]*(?:\.[a-z0-9][-a-z0-9]*)+\.[a-z]{2,})(?:[/\s)|]|$)/#
        if let match = text.lowercased().firstMatch(of: pattern) {
            return normalizeDomain(String(match.1))
        }

        let lower = text.lowercased()
        for (hint, domain) in titleDomainHints where lower.contains(hint) {
            return domain
        }
        return nil
    }

    static func knownCategory(for domain: String) -> ActivityCategory? {
        let normalized = normalizeDomain(domain)
        if let exact = knownSites[normalized]?.category { return exact }
        if let parent = parentDomain(for: normalized), let category = knownSites[parent]?.category {
            return category
        }
        return nil
    }

    static func friendlySiteLabel(domain: String?, pageTitle: String?, windowTitle: String) -> String? {
        if let domain {
            let normalized = normalizeDomain(domain)
            if let label = knownSites[normalized]?.label { return label }
            if let parent = parentDomain(for: normalized), let label = knownSites[parent]?.label { return label }
            return normalized
        }
        if let pageTitle, !pageTitle.isEmpty, !isBrowserOnlyTitle(pageTitle) {
            return pageTitle
        }
        let parsed = strippedPageTitle(from: windowTitle)
        return parsed?.isEmpty == false ? parsed : nil
    }

    static func classification(for domain: String) -> (category: ActivityCategory, label: String, source: ClassificationSource)? {
        let normalized = normalizeDomain(domain)
        if let entry = knownSites[normalized] {
            return (entry.category, entry.label, .cache)
        }
        if let parent = parentDomain(for: normalized), let entry = knownSites[parent] {
            return (entry.category, entry.label, .cache)
        }
        return nil
    }

    private static func strippedPageTitle(from windowTitle: String) -> String? {
        var title = windowTitle
        for suffix in browserSuffixes {
            if title.hasSuffix(suffix) {
                title = String(title.dropLast(suffix.count))
                break
            }
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || isBrowserOnlyTitle(title) { return nil }
        return title
    }

    private static func isBrowserOnlyTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return ["google chrome", "chrome", "safari", "arc", "firefox", "microsoft edge", "brave", "opera", "vivaldi"].contains(lower)
    }

    private static func normalizeDomain(_ domain: String) -> String {
        var value = domain.lowercased()
        if value.hasPrefix("www.") { value = String(value.dropFirst(4)) }
        return value
    }

    private static func parentDomain(for domain: String) -> String? {
        let parts = domain.split(separator: ".")
        guard parts.count > 2 else { return nil }
        return parts.suffix(2).joined(separator: ".")
    }
}
