import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @Bindable var appState: AppState
    @ObservedObject private var coordinator = TrackingCoordinator.shared
    @Environment(\.openSettings) private var openSettings
    @State private var now = Date()
    @State private var totals: [String: TimeInterval] = [:]
    @State private var showSnoozeOptions = false

    private let orderedCategories: [ActivityCategory] = [.productive, .neutral, .distracting, .uncategorized]

    private var totalSeconds: TimeInterval {
        totals.values.reduce(0, +)
    }

    private let pad: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if totalSeconds > 0 {
                breakdown
                    .padding(.horizontal, pad)
                    .padding(.bottom, 12)
            }

            if let session = coordinator.menuBarSession {
                sessionCard(session)
                    .padding(.horizontal, pad)
                    .padding(.vertical, 8)
            }

            footer
        }
        .frame(width: 248)
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
            openMainWindow()
            appState.showDashboard = false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(DurationFormatting.short(totalSeconds, zeroLabel: "0m"))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            if let focus = FocusScore.percent(from: totals) {
                focusBadge(focus)
            }
        }
        .padding(.horizontal, pad)
        .padding(.top, 11)
        .padding(.bottom, 10)
    }

    private func focusBadge(_ percent: Int) -> some View {
        Text("\(percent)%")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(CategoryColors.color(for: .productive))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                CategoryColors.color(for: .productive).opacity(0.14),
                in: Capsule()
            )
    }

    // MARK: - Breakdown

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(orderedCategories, id: \.self) { category in
                        let fraction = (totals[category.rawValue] ?? 0) / max(totalSeconds, 1)
                        if fraction > 0 {
                            CategoryColors.color(for: category)
                                .frame(width: geo.size.width * fraction)
                        }
                    }
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())

            HStack(spacing: 12) {
                ForEach(orderedCategories, id: \.self) { category in
                    let seconds = totals[category.rawValue] ?? 0
                    if seconds > 0 {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(CategoryColors.color(for: category))
                                .frame(width: 7, height: 7)
                            Text(DurationFormatting.short(seconds))
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Current session

    private func sessionCard(_ session: MenuBarSessionInfo) -> some View {
        HStack(spacing: 10) {
            sessionIcon(session)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let secondary = sessionSecondary(session) {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let startedAt = session.startedAt {
                Text(DurationFormatting.short(now.timeIntervalSince(startedAt), zeroLabel: "0m"))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Secondary line for the current-session row: the app name (so a browser shows
    /// its site *and* "Google Chrome"), falling back to the page context.
    private func sessionSecondary(_ session: MenuBarSessionInfo) -> String? {
        if session.appName.lowercased() != session.title.lowercased() {
            return session.appName
        }
        return session.subtitle
    }

    @ViewBuilder
    private func sessionIcon(_ session: MenuBarSessionInfo) -> some View {
        if BrowserDetector.isBrowser(session.bundleId), let siteLabel = session.siteLabel {
            SiteIconView(
                siteLabel: siteLabel,
                domain: SiteCatalog.parse(windowTitle: session.windowTitle).domain,
                size: 26,
                browserBundleId: session.bundleId
            )
        } else {
            AppIconView(bundleId: session.bundleId, size: 26)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if appState.showOnboarding {
                MenuBarRow(title: "Continue Setup", systemImage: "arrow.right.circle") {
                    WindowPresenter.openOnboarding()
                }
            }
            MenuBarRow(title: "Open Flowlog", systemImage: "chart.bar.xaxis") {
                openMainWindow()
            }
            MenuBarRow(title: "Settings…", systemImage: "gearshape") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }

            if let until = coordinator.snoozedUntil {
                MenuBarRow(title: "Resume tracking", systemImage: "play.fill") {
                    coordinator.endSnooze()
                    showSnoozeOptions = false
                }
                Text("Paused until \(Self.clockFormatter.string(from: until))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 4)
            } else {
                MenuBarRow(title: "Pause tracking", systemImage: "moon.zzz") {
                    withAnimation(.snappy(duration: 0.15)) { showSnoozeOptions.toggle() }
                }
                if showSnoozeOptions {
                    ForEach(snoozeOptions, id: \.label) { option in
                        MenuBarRow(title: option.label, systemImage: nil, indent: true) {
                            coordinator.snooze(for: option.seconds)
                            showSnoozeOptions = false
                        }
                    }
                }
            }

            Divider()
                .padding(.vertical, 3)

            MenuBarRow(title: "Quit Flowlog", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(5)
    }

    private var snoozeOptions: [(label: String, seconds: TimeInterval)] {
        [
            ("For 15 minutes", 15 * 60),
            ("For 30 minutes", 30 * 60),
            ("For 1 hour", 60 * 60),
        ]
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    // MARK: - Actions

    private func openMainWindow() {
        if appState.showOnboarding {
            WindowPresenter.openOnboarding()
        } else {
            WindowPresenter.openDashboard()
        }
    }

    private func reload() {
        totals = DashboardData.categoryTotalsToday()
    }
}

private struct MenuBarRow: View {
    let title: String
    var systemImage: String?
    var indent: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .frame(width: 15)
                        .foregroundStyle(hovering ? .primary : .secondary)
                } else if indent {
                    Spacer().frame(width: 15)
                }
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(indent ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                hovering ? Color.primary.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
