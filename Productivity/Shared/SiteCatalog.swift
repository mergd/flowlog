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
        "the new york times": "nytimes.com",
        "the washington post": "washingtonpost.com",
        "the verge": "theverge.com",
        "bloomberg": "bloomberg.com",
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

        // News
        "nytimes.com": ("The New York Times", .neutral),
        "washingtonpost.com": ("The Washington Post", .neutral),
        "theverge.com": ("The Verge", .neutral),
        "bloomberg.com": ("Bloomberg", .neutral),
        "wsj.com": ("The Wall Street Journal", .neutral),
        "substack.com": ("Substack", .neutral),
        "medium.com": ("Medium", .neutral),
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
        guard let oldDomain, let newDomain else { return false }
        return oldDomain != newDomain
    }

    private static let junkSiteLabels: Set<String> = [
        "unknown", "n/a", "na", "none", "uncategorized", "untitled", "null", "undefined",
    ]

    static func sanitizedSiteLabel(_ label: String?, bundleId: String, appName: String) -> String? {
        guard let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let lower = trimmed.lowercased()
        if junkSiteLabels.contains(lower) { return nil }
        if lower == appName.lowercased() { return nil }
        if EditorContext.isEditor(bundleId: bundleId) { return nil }
        if !BrowserDetector.isBrowser(bundleId), !EditorContext.isEditor(bundleId: bundleId) {
            if trimmed.count < 3 { return nil }
        }
        return trimmed
    }

    static func displayTitle(for session: Session) -> String {
        displayTitle(
            bundleId: session.bundleId,
            appName: session.appName,
            siteLabel: session.siteLabel,
            windowTitle: session.windowTitle
        )
    }

    static func displayTitle(
        bundleId: String,
        appName: String,
        siteLabel: String?,
        windowTitle: String?
    ) -> String {
        if EditorContext.isEditor(bundleId: bundleId) {
            if let file = EditorContext.parseFileName(windowTitle: windowTitle) {
                return file
            }
            if let project = EditorContext.parseProject(bundleId: bundleId, windowTitle: windowTitle) {
                return project
            }
            return appName
        }

        let cleanedLabel = sanitizedSiteLabel(siteLabel, bundleId: bundleId, appName: appName)
        if let cleanedLabel {
            return cleanedLabel
        }

        let context = parse(windowTitle: windowTitle)

        if BrowserDetector.isBrowser(bundleId) {
            // Round to the site. Prefer the domain (and its friendly catalog name)
            // over the page title so we never show a full article headline as the label.
            if let domain = context.domain {
                return knownSites[normalizeDomain(domain)]?.label ?? domain
            }
            if let label = context.siteLabel, !isBrowserOnlyTitle(label) {
                return label
            }
            return appName  // unknown site → the browser name, not the article
        }

        if let label = context.siteLabel, !isBrowserOnlyTitle(label) {
            return label
        }
        if let pageTitle = context.pageTitle {
            return pageTitle
        }
        return appName
    }

    static func displaySubtitle(for session: Session) -> String? {
        displaySubtitle(
            bundleId: session.bundleId,
            appName: session.appName,
            siteLabel: session.siteLabel,
            windowTitle: session.windowTitle
        )
    }

    static func displaySubtitle(
        bundleId: String,
        appName: String,
        siteLabel: String?,
        windowTitle: String?
    ) -> String? {
        let title = displayTitle(
            bundleId: bundleId,
            appName: appName,
            siteLabel: siteLabel,
            windowTitle: windowTitle
        )

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

        let context = parse(windowTitle: windowTitle)

        if BrowserDetector.isBrowser(bundleId) {
            // The title is the rounded site; the page/article headline is the detail.
            if let pageTitle = context.pageTitle,
               pageTitle.lowercased() != title.lowercased(),
               !isBrowserOnlyTitle(pageTitle) {
                return pageTitle
            }
            return nil
        }

        if let windowTitle,
           !windowTitle.isEmpty,
           windowTitle != title,
           windowTitle != appName {
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

    /// Build browser context from a canonical URL read off the AX web area.
    /// Only the host is retained — full URLs, paths, and query strings are never
    /// persisted. Accepts bare hosts ("github.com") from the omnibox fallback.
    static func parse(urlString: String) -> ParsedBrowserContext {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let comps = URLComponents(string: candidate),
              let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = comps.host, !host.isEmpty else { return .empty }
        let domain = normalizeDomain(host)
        let siteLabel = friendlySiteLabel(domain: domain, pageTitle: nil, windowTitle: trimmed)
        return ParsedBrowserContext(domain: domain, siteLabel: siteLabel, pageTitle: nil)
    }

    static func shouldTrack(domain: String?, pageTitle: String?, windowTitle: String?) -> Bool {
        let title = (windowTitle ?? pageTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return false }
        let lower = title.lowercased()
        // The window title carries the browser suffix + profile ("New Tab - Google
        // Chrome - William"), so match ignored titles by segment, not whole-string.
        let segments = Set(lower
            .components(separatedBy: CharacterSet(charactersIn: "-–—|·"))
            .map { $0.trimmingCharacters(in: .whitespaces) })
        if ignoredTitles.contains(lower) || !ignoredTitles.isDisjoint(with: segments) { return false }
        if lower.contains("incognito") || lower.contains("private browsing") { return false }
        if lower.hasPrefix("chrome://") || lower.hasPrefix("about:") { return false }
        if domain == nil, isBrowserOnlyTitle(title) { return false }
        return true
    }

    static func domain(from text: String) -> String? {
        // If this is a real URL, take the host directly — never scrape a domain
        // out of a query string (e.g. ?utm_source=substack.com on a bodyspec URL).
        if text.contains("://"),
           let host = URLComponents(string: text.trimmingCharacters(in: .whitespaces))?.host, !host.isEmpty {
            return normalizeDomain(host)
        }
        if let urlDomain = OCRPreprocessor.extractDomain(from: text) {
            return normalizeDomain(urlDomain)
        }

        let pattern = #/(?:^|[\s(])([a-z0-9][-a-z0-9]*(?:\.[a-z0-9][-a-z0-9]*)+\.[a-z]{2,})(?:[/\s)|]|$)/#
        if let match = text.lowercased().firstMatch(of: pattern) {
            return normalizeDomain(String(match.1))
        }

        // Title hints are a last resort (we prefer the real URL). Match a hint only
        // when it's a *delimited segment* of the title — i.e. the title's site marker
        // ("Subscriptions — YouTube") — never an arbitrary content mention. A Reddit
        // thread titled "…Same Cursor. Same Claude…" must NOT resolve to claude.ai.
        let segments = text.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "-–—|·:"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
        for (hint, domain) in titleDomainHints where segments.contains(hint) {
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
        // A site label must identify a *site*, not a page. Without a domain we
        // can't name the site, so return nil rather than promoting the article
        // headline to a site label (the page title still shows as a subtitle).
        guard let domain else { return nil }
        let normalized = normalizeDomain(domain)
        if let label = knownSites[normalized]?.label { return label }
        if let parent = parentDomain(for: normalized), let label = knownSites[parent]?.label { return label }
        return normalized
    }

    static func classification(for domain: String) -> (category: ActivityCategory, label: String, source: ClassificationSource)? {
        let normalized = normalizeDomain(domain)
        if let entry = knownSites[normalized] {
            return (entry.category, entry.label, .siteCatalog)
        }
        if let parent = parentDomain(for: normalized), let entry = knownSites[parent] {
            return (entry.category, entry.label, .siteCatalog)
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

    /// Domains that are really the same site under different hostnames.
    private static let domainAliases: [String: String] = [
        "twitter.com": "x.com",
        "mobile.twitter.com": "x.com",
        "m.youtube.com": "youtube.com",
        "old.reddit.com": "reddit.com",
    ]

    private static func normalizeDomain(_ domain: String) -> String {
        var value = domain.lowercased()
        if value.hasPrefix("www.") { value = String(value.dropFirst(4)) }
        return domainAliases[value] ?? value
    }

    /// Public canonical form of a domain: lowercased, `www.` stripped, and aliases
    /// applied (so `twitter.com` → `x.com`). Use for favicon lookups and display.
    static func canonicalDomain(_ domain: String?) -> String? {
        guard let domain else { return nil }
        let trimmed = domain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return normalizeDomain(trimmed)
    }

    /// Best-effort domain for a site *label* (e.g. "Google" → "google.com"), used
    /// when the live URL wasn't readable but we still recognize the site by name.
    /// Lets favicons resolve from a label alone.
    static func inferredDomain(forLabel label: String?) -> String? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }
        let lower = label.lowercased()
        if let hit = knownSites.first(where: { $0.value.label.lowercased() == lower })?.key {
            return hit
        }
        if let hint = titleDomainHints[lower] { return hint }
        return nil
    }

    private static func parentDomain(for domain: String) -> String? {
        let parts = domain.split(separator: ".")
        guard parts.count > 2 else { return nil }
        return parts.suffix(2).joined(separator: ".")
    }
}
