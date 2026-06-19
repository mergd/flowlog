import Foundation
import AppKit

enum AppCatalog {
    static let minimumSessionDuration: TimeInterval = 5

    private static let ignoredBundleIds: Set<String> = [
        "com.productivity.app",
        "com.apple.accessibility.universalAccessAuthWarn",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.coreservices.uiagent",
        "com.apple.WindowManager",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.Spotlight",
        "com.apple.systempreferences",
        "com.apple.systempreferences.GeneralSettings",
        "com.apple.preference.security",
        "com.apple.ScreenSaver.Engine",
        "com.apple.dock",
        "com.apple.finder.Open-With-Prologue", // transient
    ]

    private static let ignoredPrefixes = [
        "com.apple.accessibility.",
        "com.apple.preference.",
    ]

    private static let knownApps: [String: (name: String, category: ActivityCategory)] = [
        // Dev tools
        "com.todesktop.230313mzl4w4u92": ("Cursor", .productive),
        "com.apple.dt.Xcode": ("Xcode", .productive),
        "com.microsoft.VSCode": ("VS Code", .productive),
        "com.apple.Terminal": ("Terminal", .productive),
        "com.googlecode.iterm2": ("iTerm", .productive),
        "com.github.GitHubClient": ("GitHub", .productive),
        "com.sublimetext.4": ("Sublime Text", .productive),
        "com.jetbrains.intellij": ("IntelliJ", .productive),
        "com.jetbrains.AppCode": ("AppCode", .productive),
        "com.jetbrains.pycharm": ("PyCharm", .productive),
        "com.docker.docker": ("Docker", .productive),

        // Work
        "notion.id": ("Notion", .productive),
        "com.linear": ("Linear", .productive),
        "com.figma.Desktop": ("Figma", .productive),
        "com.obsidian.md": ("Obsidian", .productive),
        "com.apple.Notes": ("Notes", .productive),
        "com.apple.iWork.Pages": ("Pages", .productive),
        "com.apple.iWork.Numbers": ("Numbers", .neutral),
        "com.apple.iWork.Keynote": ("Keynote", .productive),
        "com.tinyspeck.slackmacgap": ("Slack", .neutral),
        "com.microsoft.teams2": ("Teams", .neutral),
        "com.microsoft.Word": ("Word", .productive),
        "com.microsoft.Excel": ("Excel", .productive),
        "com.microsoft.Powerpoint": ("PowerPoint", .productive),
        "com.google.GoogleDrive": ("Google Drive", .neutral),
        "com.adobe.Photoshop": ("Photoshop", .productive),
        "com.adobe.illustrator": ("Illustrator", .productive),

        // Browsers
        "com.apple.Safari": ("Safari", .neutral),
        "com.google.Chrome": ("Chrome", .neutral),
        "com.brave.Browser": ("Brave", .neutral),
        "com.microsoft.edgemac": ("Edge", .neutral),
        "org.mozilla.firefox": ("Firefox", .neutral),
        "company.thebrowser.Browser": ("Arc", .neutral),
        "com.arc.browser": ("Arc", .neutral),

        // Communication
        "com.apple.MobileSMS": ("Messages", .neutral),
        "com.apple.mail": ("Mail", .neutral),
        "com.hnc.Discord": ("Discord", .distracting),
        "com.apple.FaceTime": ("FaceTime", .neutral),

        // System (if ever shown)
        "com.apple.finder": ("Finder", .neutral),

        // Entertainment
        "com.spotify.client": ("Spotify", .distracting),
        "com.apple.Music": ("Music", .distracting),
        "com.valvesoftware.steam": ("Steam", .distracting),
        "tv.twitch.studio": ("Twitch", .distracting),
        "com.netflix.Netflix": ("Netflix", .distracting),
    ]

    private static let appStoreCategoryMap: [String: ActivityCategory] = [
        "public.app-category.developer-tools": .productive,
        "public.app-category.productivity": .productive,
        "public.app-category.business": .productive,
        "public.app-category.education": .productive,
        "public.app-category.graphics-design": .productive,
        "public.app-category.medical": .productive,
        "public.app-category.social-networking": .distracting,
        "public.app-category.games": .distracting,
        "public.app-category.entertainment": .distracting,
        "public.app-category.music": .distracting,
        "public.app-category.sports": .distracting,
        "public.app-category.video": .neutral,
        "public.app-category.photography": .neutral,
        "public.app-category.news": .neutral,
        "public.app-category.utilities": .neutral,
        "public.app-category.finance": .neutral,
        "public.app-category.healthcare-fitness": .neutral,
        "public.app-category.lifestyle": .neutral,
        "public.app-category.travel": .neutral,
        "public.app-category.weather": .neutral,
        "public.app-category.reference": .neutral,
        "public.app-category.shopping": .neutral,
        "public.app-category.food-and-drink": .neutral,
    ]

    static func shouldTrack(bundleId: String) -> Bool {
        if ignoredBundleIds.contains(bundleId) { return false }
        if ignoredPrefixes.contains(where: { bundleId.hasPrefix($0) }) { return false }
        return true
    }

    static func shouldIncludeInStats(bundleId: String, appName: String) -> Bool {
        guard shouldTrack(bundleId: bundleId) else { return false }
        if appName.count < 2, knownApps[bundleId] == nil { return false }
        return true
    }

    static func shouldDisplay(bundleId: String, duration: TimeInterval, appName: String) -> Bool {
        guard shouldIncludeInStats(bundleId: bundleId, appName: appName) else { return false }
        return duration >= minimumSessionDuration
    }

    static func knownCategory(for bundleId: String) -> ActivityCategory? {
        if let exact = knownApps[bundleId]?.category { return exact }
        if bundleId.hasPrefix("com.apple.iWork.") { return .productive }
        if bundleId.hasPrefix("com.jetbrains.") { return .productive }
        if bundleId.hasPrefix("com.adobe.") { return .productive }
        if bundleId.hasPrefix("com.microsoft.VSCode") { return .productive }
        return appStoreCategory(for: bundleId)
    }

    static func appStoreCategory(for bundleId: String) -> ActivityCategory? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              let bundle = Bundle(url: url),
              let raw = bundle.infoDictionary?["LSApplicationCategoryType"] as? String
        else { return nil }
        return appStoreCategoryMap[raw] ?? .neutral
    }

    static func friendlyName(bundleId: String, fallback: String) -> String {
        if let name = knownApps[bundleId]?.name { return name }
        if bundleId.hasPrefix("com.apple.iWork.") {
            return fallback.isEmpty ? "iWork" : fallback
        }
        return fallback
    }

    static func classification(for bundleId: String) -> (category: ActivityCategory, source: ClassificationSource)? {
        guard let category = knownCategory(for: bundleId) else { return nil }
        return (category, .appCatalog)
    }
}
