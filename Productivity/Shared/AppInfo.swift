import Foundation

enum AppInfo {
    static let name = "Flowlog"
    private static let legacySupportDirectoryName = "Productivity"

    static func applicationSupportDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let newDir = appSupport.appendingPathComponent(name, isDirectory: true)
        let legacyDir = appSupport.appendingPathComponent(legacySupportDirectoryName, isDirectory: true)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: newDir.path), fileManager.fileExists(atPath: legacyDir.path) {
            try fileManager.moveItem(at: legacyDir, to: newDir)
        }

        try fileManager.createDirectory(at: newDir, withIntermediateDirectories: true)
        return newDir
    }

    static func screenshotsDirectory() throws -> URL {
        let dir = try applicationSupportDirectory().appendingPathComponent("screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func faviconsDirectory() throws -> URL {
        let dir = try applicationSupportDirectory().appendingPathComponent("favicons", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
