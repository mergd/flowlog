import Foundation
import UserNotifications

@MainActor
final class NudgeEngine {
    static let shared = NudgeEngine()

    private var timer: Timer?
    private var lastNudgeDate: Date?
    private var nudgeCountToday = 0

    func start() {
        requestPermissionIfNeeded()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.evaluate() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func requestPermissionIfNeeded() {
        guard AppSettings.shared.nudgesEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate() async {
        let settings = AppSettings.shared
        guard settings.nudgesEnabled else { return }
        guard !isQuietHours() else { return }
        if settings.nudgeOnlyDuringWorkHours, !isWorkHours() { return }

        let windowStart = Date().addingTimeInterval(-Double(settings.nudgeRollingWindowMinutes * 60))
        guard let distractingSeconds = try? DatabaseManager.shared.distractingDuration(since: windowStart) else { return }
        let distractingMinutes = distractingSeconds / 60

        guard distractingMinutes >= Double(settings.nudgeThresholdMinutes) else { return }

        if let last = lastNudgeDate,
           Date().timeIntervalSince(last) < Double(settings.nudgeCooldownMinutes * 60) {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Off track?"
        content.body = "You've spent \(Int(distractingMinutes)) min on distracting apps in the last \(settings.nudgeRollingWindowMinutes) minutes."
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        lastNudgeDate = Date()
        nudgeCountToday += 1
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
