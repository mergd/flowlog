import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct WorkLogSummary {
    var headline: String
    var narrative: String
    var primaryFocus: String?
    var distractions: [String]
    var productiveMinutes: Int
    var distractingMinutes: Int
}
#endif

final class WorkLogGenerator: @unchecked Sendable {
    static let shared = WorkLogGenerator()

    func generate(for periodStart: Date, periodEnd: Date) async throws -> WorkLogEntry {
        let sessions = try DatabaseManager.shared.sessions(in: periodStart..<periodEnd)
        let summary = sessions.map { s in
            "- \(s.appName) | \(s.siteLabel ?? s.windowTitle ?? "") | \(s.activityCategory.rawValue) | \(Int(s.duration / 60))m"
        }.joined(separator: "\n")

        let productive = Int(sessions.filter { $0.activityCategory == .productive }.reduce(0) { $0 + $1.duration } / 60)
        let distracting = Int(sessions.filter { $0.activityCategory == .distracting }.reduce(0) { $0 + $1.duration } / 60)

        var headline = "\(productive + distracting)m tracked"
        var narrative = "Activity from \(format(periodStart)) to \(format(periodEnd))."
        var primaryFocus: String?
        var distractions: [String] = []

        #if canImport(FoundationModels)
        let openRouterOnly = await MainActor.run { AppSettings.shared.openRouterOnly }
        if #available(macOS 26.0, *), AppleClassifier.shared.isSupported, !openRouterOnly {
            do {
                let session = LanguageModelSession {
                    "Summarize productivity sessions as a short work log. Be direct and specific."
                }
                let prompt = """
                Sessions:
                \(summary)

                Productive minutes: \(productive)
                Distracting minutes: \(distracting)
                Write a 2-4 sentence narrative about focus and distractions.
                """
                let response = try await session.respond(to: prompt, generating: WorkLogSummary.self)
                let s = response.content
                headline = s.headline
                narrative = s.narrative
                primaryFocus = s.primaryFocus
                distractions = s.distractions
            } catch {
                narrative = fallbackNarrative(sessions: sessions, productive: productive, distracting: distracting)
            }
        } else {
            narrative = fallbackNarrative(sessions: sessions, productive: productive, distracting: distracting)
        }
        #else
        narrative = fallbackNarrative(sessions: sessions, productive: productive, distracting: distracting)
        #endif

        let distractionsJSON = try? String(data: JSONEncoder().encode(distractions), encoding: .utf8)
        let finalHeadline = headline
        let finalNarrative = narrative
        let finalPrimaryFocus = primaryFocus
        return try await DatabaseManager.shared.queue.write { db -> WorkLogEntry in
            var entry = WorkLogEntry(
                id: nil,
                periodStart: periodStart,
                periodEnd: periodEnd,
                headline: finalHeadline,
                narrative: finalNarrative,
                primaryFocus: finalPrimaryFocus,
                distractionsJSON: distractionsJSON,
                productiveMinutes: productive,
                distractingMinutes: distracting,
                createdAt: Date()
            )
            try entry.insert(db)
            return entry
        }
    }

    private func fallbackNarrative(sessions: [Session], productive: Int, distracting: Int) -> String {
        let top = sessions.max(by: { $0.duration < $1.duration })
        var parts = ["Spent \(productive)m on productive work"]
        if let top { parts.append("mostly in \(top.appName)") }
        if distracting > 0 { parts.append("with \(distracting)m on distracting apps") }
        return parts.joined(separator: ", ") + "."
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private func format(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
