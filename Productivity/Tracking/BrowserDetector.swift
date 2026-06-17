import Foundation

enum BrowserDetector {
    static let browserBundleIds: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "com.arc.browser",
    ]

    static func isBrowser(_ bundleId: String) -> Bool {
        browserBundleIds.contains(bundleId)
    }
}
