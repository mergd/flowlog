import SwiftUI

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var showDashboard = false
    var showOnboarding = !AppSettings.shared.hasCompletedOnboarding
    var selectedTab: DashboardTab = .today

    let coordinator = TrackingCoordinator.shared

    func bootstrap() {
        syncOnboardingState()
        LoginItemManager.syncWithPreference()

        if AppSettings.shared.hasCompletedOnboarding {
            coordinator.start()
        } else {
            showDashboard = true
        }
    }

    func syncOnboardingState() {
        showOnboarding = !AppSettings.shared.hasCompletedOnboarding
    }

    func presentOnboarding() {
        syncOnboardingState()
        guard showOnboarding else { return }
        showDashboard = true
        WindowPresenter.openOnboarding()
    }

    func completeOnboarding() {
        AppSettings.shared.hasCompletedOnboarding = true
        AppSettings.shared.onboardingResumeStep = nil
        AppSettings.shared.loginItemEnabled = true
        LoginItemManager.setEnabled(true)
        showOnboarding = false
        coordinator.start()
        WindowPresenter.openDashboard()
    }
}

enum DashboardTab: String, CaseIterable, Identifiable {
    case today, calendar, timeline, apps, rules, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .timeline: "Timeline"
        case .apps: "Apps"
        case .rules: "Rules"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .today: "chart.pie.fill"
        case .calendar: "calendar"
        case .timeline: "clock.fill"
        case .apps: "square.grid.2x2.fill"
        case .rules: "list.bullet.rectangle"
        case .settings: "gearshape.fill"
        }
    }
}
