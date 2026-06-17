import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @Bindable var appState: AppState
    @ObservedObject private var coordinator = TrackingCoordinator.shared
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = coordinator.menuBarSession {
                MenuBarSessionHeader(info: session, now: now)
                Divider()
            }

            MenuBarTodaySection()

            Divider()

            if appState.showOnboarding {
                Button("Continue Setup") {
                    WindowPresenter.openOnboarding()
                }
            }

            Button("Open") {
                WindowPresenter.openDashboard()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
        .frame(width: 236)
        .background(WindowRegistration())
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
        .onReceive(NotificationCenter.default.publisher(for: .productivityDataDidChange)) { _ in
            coordinator.refreshMenuBarSession()
        }
        .onChange(of: appState.showDashboard) { _, show in
            guard show else { return }
            if appState.showOnboarding {
                WindowPresenter.openOnboarding()
            } else {
                WindowPresenter.openDashboard()
            }
            appState.showDashboard = false
        }
    }
}

struct MenuBarSessionHeader: View {
    let info: MenuBarSessionInfo
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AppIconView(bundleId: info.bundleId, size: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(info.isIdle ? "Away" : info.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if info.isIdle {
                    Text("Idle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        if let startedAt = info.startedAt {
                            DurationLabel(seconds: now.timeIntervalSince(startedAt))
                        }

                        if let category = info.category, category != .uncategorized {
                            CategoryPill(category: category)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }

        if let subtitle = info.subtitle, !info.isIdle {
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.leading, 28)
        }
    }
}

struct MenuBarTodaySection: View {
    @State private var totalSeconds: TimeInterval = 0
    @State private var focusPercent: Int?
    @State private var topApps: [(name: String, bundleId: String, duration: TimeInterval)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text("\(DurationFormatting.short(totalSeconds, zeroLabel: "0m")) tracked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer(minLength: 0)

                if let focusPercent {
                    Text("\(focusPercent)% focus")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if !topApps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(topApps.prefix(3), id: \.bundleId) { app in
                        HStack(spacing: 6) {
                            AppIconView(bundleId: app.bundleId, size: 14)
                            Text(app.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            DurationLabel(seconds: app.duration)
                        }
                    }
                }
            }
        }
        .dashboardAutoReload(reload)
    }

    private func reload() {
        let totals = DashboardData.categoryTotalsToday()
        totalSeconds = totals.values.reduce(0, +)
        focusPercent = FocusScore.percent(from: totals)

        topApps = DashboardData.appTotalsToday()
            .prefix(3)
            .map { (name: $0.appName, bundleId: $0.bundleId, duration: $0.duration) }
    }
}
