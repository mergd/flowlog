import Foundation
import UserNotifications

@MainActor
final class NudgeEngine {
    static let shared = NudgeEngine()

    private var timer: Timer?
    private var lastThresholdNudgeDate: Date?
    private var lastPeriodicNudgeDate: Date?
    private let defaults = UserDefaults.standard

    private static let lastPeriodicNudgeKey = "nudgeEngine.lastPeriodicNudge"
    private static let periodicIntervalMinutes = 30

    /// Recent window used to decide whether the user is currently focused. The rolling nudge
    /// windows look back far enough to include earlier distractions; this short window reflects
    /// what you're doing *now*.
    private static let recentFocusWindowMinutes = 5
    /// Minimum productive seconds in the recent window before we treat you as focused.
    private static let recentFocusMinProductiveSeconds: TimeInterval = 60

    func start() {
        requestPermissionIfNeeded()
        lastPeriodicNudgeDate = defaults.object(forKey: Self.lastPeriodicNudgeKey) as? Date
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.evaluate() }
        }
        Task { await evaluate() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func requestPermissionIfNeeded() {
        let settings = AppSettings.shared
        guard settings.nudgesEnabled || settings.nudgeEvery30MinutesEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate() async {
        let settings = AppSettings.shared
        guard settings.nudgesEnabled || settings.nudgeEvery30MinutesEnabled else { return }
        guard !isQuietHours() else { return }
        if settings.nudgeOnlyDuringWorkHours, !isWorkHours() { return }
        guard !isRecentlyFocused() else { return }

        if settings.nudgesEnabled {
            await evaluateThresholdNudge()
        }
        if settings.nudgeEvery30MinutesEnabled {
            await evaluatePeriodicNudge()
        }
    }

    /// Fires when distracting time in the rolling window crosses the threshold.
    private func evaluateThresholdNudge() async {
        let settings = AppSettings.shared
        let windowMinutes = settings.nudgeRollingWindowMinutes
        let distractingMinutes = distractingMinutes(inLast: windowMinutes)
        guard distractingMinutes >= Double(settings.nudgeThresholdMinutes) else { return }

        if let last = lastThresholdNudgeDate,
           Date().timeIntervalSince(last) < Double(settings.nudgeCooldownMinutes * 60) {
            return
        }

        await postNudge(
            distractingMinutes: distractingMinutes,
            windowMinutes: windowMinutes
        )
        lastThresholdNudgeDate = Date()
    }

    /// Fires on a fixed 30-minute cadence with distracting time from the last 30 minutes.
    private func evaluatePeriodicNudge() async {
        let interval = Self.periodicIntervalMinutes
        let distractingMinutes = distractingMinutes(inLast: interval)
        guard distractingMinutes >= 1 else { return }

        if let last = lastPeriodicNudgeDate,
           Date().timeIntervalSince(last) < Double(interval * 60) {
            return
        }

        await postNudge(
            distractingMinutes: distractingMinutes,
            windowMinutes: interval
        )
        let now = Date()
        lastPeriodicNudgeDate = now
        defaults.set(now, forKey: Self.lastPeriodicNudgeKey)
    }

    /// True when recent activity is dominated by productive time, meaning the user is heads-down
    /// right now even if the rolling window still contains earlier distractions. Suppresses nudges
    /// so we don't scold someone who has already gotten back on track.
    private func isRecentlyFocused() -> Bool {
        let windowStart = Date().addingTimeInterval(-Double(Self.recentFocusWindowMinutes * 60))
        guard let balance = try? DatabaseManager.shared.recentFocusBalance(since: windowStart) else {
            return false
        }
        return balance.productive >= Self.recentFocusMinProductiveSeconds
            && balance.productive > balance.distracting
    }

    private func distractingMinutes(inLast windowMinutes: Int) -> Double {
        let windowStart = Date().addingTimeInterval(-Double(windowMinutes * 60))
        guard let seconds = try? DatabaseManager.shared.distractingDuration(since: windowStart) else { return 0 }
        return seconds / 60
    }

    private func postNudge(distractingMinutes: Double, windowMinutes: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Off track?"
        content.body = "You've spent \(Int(distractingMinutes)) min on distracting apps in the last \(windowMinutes) minutes."
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func isQuietHours() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let start = AppSettings.shared.quietHoursStart
        let end = AppSettings.shared.quietHoursEnd
        if start > end {
            return hour >= start || hour < end
        }
        return hour >= start && hour < end
    }

    private func isWorkHours() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let start = AppSettings.shared.workHoursStart
        let end = AppSettings.shared.workHoursEnd
        if start > end {
            return hour >= start || hour < end
        }
        return hour >= start && hour < end
    }
}
