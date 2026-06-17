import Foundation

enum EditorContext {
    static let cursorBundleId = "com.todesktop.230313mzl4w4u92"

    private static let editorSuffixes = [
        " — Cursor",
        " - Cursor",
        " — Visual Studio Code",
        " - Visual Studio Code",
        " — Code",
        " - Code",
    ]

    private static let fileExtensions = [
        ".swift", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs",
        ".py", ".rb", ".go", ".rs", ".md", ".mdx", ".json", ".yaml", ".yml",
        ".html", ".htm", ".css", ".scss", ".sass", ".less", ".vue", ".svelte",
        ".kt", ".kts", ".java", ".c", ".cpp", ".cc", ".h", ".hpp", ".m", ".mm",
        ".sql", ".sh", ".zsh", ".bash", ".toml", ".xml", ".plist", ".gradle",
        ".lock", ".env", ".gitignore", ".dockerfile",
    ]

    static func isEditor(bundleId: String) -> Bool {
        bundleId == cursorBundleId || bundleId.hasPrefix("com.microsoft.VSCode")
    }

    static func parseProject(bundleId: String, windowTitle: String?) -> String? {
        guard isEditor(bundleId: bundleId) else { return nil }
        let segments = strippedSegments(from: windowTitle)
        guard !segments.isEmpty else { return nil }

        if segments.count == 1 {
            let segment = segments[0]
            return looksLikeFilename(segment) ? nil : segment
        }

        if looksLikeFilename(segments[0]) {
            return bestProjectName(from: Array(segments.dropFirst()))
        }

        if let last = segments.last, looksLikeFilename(last) {
            return segments.dropLast().last
        }

        return segments.last
    }

    static func parseFileName(windowTitle: String?) -> String? {
        let segments = strippedSegments(from: windowTitle)
        guard let first = segments.first, looksLikeFilename(first) else { return nil }
        return first
    }

    private static func strippedSegments(from windowTitle: String?) -> [String] {
        guard var title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return []
        }

        for suffix in editorSuffixes where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
            break
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return [] }

        for separator in [" — ", " – ", " - "] where title.contains(separator) {
            return title
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return [title]
    }

    private static func bestProjectName(from segments: [String]) -> String? {
        segments.last { !looksLikeFilename($0) }
    }

    private static func looksLikeFilename(_ value: String) -> Bool {
        let lower = value.lowercased()
        if fileExtensions.contains(where: { lower.hasSuffix($0) }) { return true }
        if lower.contains("/") || lower.contains("\\") { return true }
        return false
    }
}
