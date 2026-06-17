import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @Bindable var appState: AppState
    @ObservedObject private var coordinator = TrackingCoordinator.shared
    @State private var now = Date()
    @State private var totalSeconds: TimeInterval = 0

    var body: some View {
        Group {
            if let session = coordinator.menuBarSession {
                Text(activeSessionLine(for: session))

                if let subtitle = session.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(todayLine)
                .font(.caption)
                .foregroundStyle(.secondary)

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
        .onAppear(perform: reload)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            now = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .productivityDataDidChange)) { _ in
            coordinator.refreshMenuBarSession()
            reload()
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

    private var todayLine: String {
        let tracked = DurationFormatting.short(totalSeconds, zeroLabel: "0m")
        return "Today · \(tracked) tracked"
    }

    private func activeSessionLine(for session: MenuBarSessionInfo) -> String {
        var parts = [session.title]
        if let startedAt = session.startedAt {
            parts.append(DurationFormatting.short(now.timeIntervalSince(startedAt)))
        }
        return parts.joined(separator: " · ")
    }

    private func reload() {
        let totals = DashboardData.categoryTotalsToday()
        totalSeconds = totals.values.reduce(0, +)
    }
}
