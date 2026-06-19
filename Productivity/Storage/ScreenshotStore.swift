import Foundation
import AppKit

struct StoredScreenshot: Sendable {
    let id: String
    let path: URL
    let capturedAt: Date
}

final class ScreenshotStore: Sendable {
    static let shared = ScreenshotStore()
    static let retentionInterval: TimeInterval = 24 * 60 * 60

    private let directory: URL

    init() {
        directory = (try? AppInfo.screenshotsDirectory()) ?? FileManager.default.temporaryDirectory
    }

    func save(jpegData: Data) throws -> String {
        let id = UUID().uuidString
        let path = directory.appendingPathComponent("\(id).jpg")
        try jpegData.write(to: path)
        return id
    }

    func loadImage(id: String) -> NSImage? {
        let path = directory.appendingPathComponent("\(id).jpg")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return NSImage(contentsOf: path)
    }

    func path(for id: String) -> URL {
        directory.appendingPathComponent("\(id).jpg")
    }

    func purgeOlderThan(_ interval: TimeInterval = retentionInterval) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        for file in files {
            guard let date = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate, date < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
        purgeOrphanedReferences(cutoff: cutoff)
    }

    private func purgeOrphanedReferences(cutoff: Date) {
        try? DatabaseManager.shared.queue.write { db in
            try db.execute(sql: """
                UPDATE sessions SET screenshotId = NULL
                WHERE screenshotId IS NOT NULL
                AND id IN (
                    SELECT s.id FROM sessions s
                    LEFT JOIN (SELECT 1) x ON 1=0
                    WHERE s.start < ?
                )
                """, arguments: [cutoff])
        }
    }

    func deleteAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
        try? DatabaseManager.shared.queue.write { db in
            try db.execute(sql: "UPDATE sessions SET screenshotId = NULL")
        }
    }
}

/// Fetches and caches website favicons by domain. Returns raw image `Data`
/// (Sendable) so callers build the platform image on their own actor.
///
/// Uses DuckDuckGo's favicon endpoint — more privacy-aligned than Google's, and
/// it only ever sees the bare domain (which we already classify), never a full URL.
actor FaviconStore {
    static let shared = FaviconStore()

    private var memory: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private let cacheDir = try? AppInfo.faviconsDirectory()

    /// Domains we've tried with no usable favicon, so we don't refetch every render.
    private var negativeCache: Set<String> = []

    func favicon(for domain: String?) async -> Data? {
        guard let key = normalize(domain) else { return nil }

        if let data = memory[key] { return data }
        if negativeCache.contains(key) { return nil }

        if let fileURL = cacheDir?.appendingPathComponent("\(key).png"),
           let data = try? Data(contentsOf: fileURL), !data.isEmpty {
            memory[key] = data
            return data
        }

        if let existing = inFlight[key] { return await existing.value }

        let task = Task<Data?, Never> { [key] in
            await Self.download(domain: key)
        }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil

        if let data {
            memory[key] = data
            if let fileURL = cacheDir?.appendingPathComponent("\(key).png") {
                try? data.write(to: fileURL)
            }
        } else {
            negativeCache.insert(key)
        }
        return data
    }

    private static func download(domain: String) async -> Data? {
        guard let url = URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(AppInfo.name, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              !data.isEmpty else { return nil }
        return data
    }

    private func normalize(_ domain: String?) -> String? {
        guard var value = domain?.lowercased().trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("www.") { value = String(value.dropFirst(4)) }
        // Must look like a hostname, not a free-text label.
        guard value.contains("."), !value.contains(" ") else { return nil }
        return value
    }
}
