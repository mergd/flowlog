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
