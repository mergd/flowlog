import Foundation
import MetricKit

/// Captures crash (and hang) reports via MetricKit and persists them next to the
/// database in Application Support, so they survive the OS DiagnosticReports
/// rotation and can be read with `flowlog crashes`.
///
/// On-device only — nothing is uploaded. MetricKit hands us diagnostics on a
/// launch *after* the crash (the system batches them), so a report appears the
/// next time Flowlog runs, not instantly when it dies.
final class CrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReporter()

    func start() {
        MXMetricManager.shared.add(self)
    }

    /// Diagnostic payloads (crashes, hangs, CPU exceptions, disk writes) arrive here.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads where !(payload.crashDiagnostics ?? []).isEmpty {
            persist(payload)
        }
    }

    /// Metric payloads (performance aggregates) — unused; we only keep crashes.
    func didReceive(_ payloads: [MXMetricPayload]) {}

    private func persist(_ payload: MXDiagnosticPayload) {
        do {
            let dir = try AppInfo.crashReportsDirectory()
            let stamp = Self.fileStampFormatter.string(from: payload.timeStampEnd)
            try payload.jsonRepresentation().write(to: uniqueURL(in: dir, stamp: stamp), options: .atomic)
        } catch {
            FlowlogLog.tracking("Failed to persist crash report: \(error.localizedDescription)")
        }
    }

    /// `crash-<stamp>.json`, suffixing `-2`, `-3`… if multiple payloads share a stamp.
    private func uniqueURL(in dir: URL, stamp: String) -> URL {
        let base = dir.appendingPathComponent("crash-\(stamp).json")
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        var index = 2
        while true {
            let candidate = dir.appendingPathComponent("crash-\(stamp)-\(index).json")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
