import Foundation
import UserNotifications

/// Posts end-of-day and end-of-week screen-time summaries.
///
/// Runs on its own minute timer (independent of tracking snooze/idle) so it can
/// catch up if the scheduled hour passed while the Mac was asleep or the app was
/// busy. Each summary fires at most once per day/week, tracked in UserDefaults so
/// a relaunch doesn't re-fire one that already went out.
@MainActor
final class SummaryNotifier {
    static let shared = SummaryNotifier()

    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private let calendar = Calendar.current

    private static let lastDailyKey = "summaryNotifier.lastDailyDay"
    private static let lastWeeklyKey = "summaryNotifier.lastWeeklyWeek"

    func start() {
        requestPermissionIfNeeded()
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
        guard settings.dailySummaryEnabled || settings.weeklySummaryEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate() async {
        let settings = AppSettings.shared
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        if settings.dailySummaryEnabled, hour >= settings.dailySummaryHour {
            let dayStamp = dayStamp(now)
            if defaults.string(forKey: Self.lastDailyKey) != dayStamp {
                if await postDailySummary() {
                    defaults.set(dayStamp, forKey: Self.lastDailyKey)
                }
            }
        }

        if settings.weeklySummaryEnabled,
           calendar.component(.weekday, from: now) == settings.weeklySummaryWeekday,
           hour >= settings.weeklySummaryHour {
            let weekStamp = weekStamp(now)
            if defaults.string(forKey: Self.lastWeeklyKey) != weekStamp {
                if await postWeeklySummary() {
                    defaults.set(weekStamp, forKey: Self.lastWeeklyKey)
                }
            }
        }
    }

    /// Returns true if a notification was posted (false when there's nothing to report).
    private func postDailySummary() async -> Bool {
        let totals = DashboardData.categoryTotalsToday()
        let tracked = totals.values.reduce(0, +)
        guard tracked > 0 else { return false }
        await post(title: "Today's summary", body: summaryBody(totals: totals, prefix: nil))
        return true
    }

    private func postWeeklySummary() async -> Bool {
        let now = Date()
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return false }
        let totals = DashboardData.categoryTotals(in: weekAgo ..< now)
        let tracked = totals.values.reduce(0, +)
        guard tracked > 0 else { return false }
        await post(title: "Weekly summary", body: summaryBody(totals: totals, prefix: "Past 7 days: "))
        return true
    }

    private func summaryBody(totals: [String: TimeInterval], prefix: String?) -> String {
        let tracked = totals.values.reduce(0, +)
        var body = (prefix ?? "") + "\(DurationFormatting.short(tracked, zeroLabel: "0m")) tracked"
        if let focus = FocusScore.percent(from: totals) {
            body += " · \(focus)% productive"
        }
        return body
    }

    private func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func dayStamp(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func weekStamp(_ date: Date) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }
}
