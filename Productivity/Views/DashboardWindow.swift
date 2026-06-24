import SwiftUI

struct DashboardWindow: View {
    @Bindable var appState: AppState
    @ObservedObject private var coordinator = TrackingCoordinator.shared
    @State private var screenRecordingGranted = Permissions.isScreenRecordingGranted()

    private static let sidebarWidth: CGFloat = 168

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        if coordinator.isSnoozed { snoozeBanner }
                        if !screenRecordingGranted { screenRecordingBanner }
                    }
                }
        }
        .frame(minWidth: DashboardTheme.minWidth, minHeight: DashboardTheme.minHeight)
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(removing: .title)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .dashboardSurface()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenRecordingGranted = Permissions.isScreenRecordingGranted()
        }
    }

    private var sidebar: some View {
        List(DashboardTab.allCases, selection: $appState.selectedTab) { tab in
            Label(tab.title, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(width: Self.sidebarWidth)
        .background(DashboardTheme.surface.ignoresSafeArea(.container, edges: .top))
        .sidebarTitleBarInset()
    }

    private var screenRecordingBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("Screen Recording is off — captures paused")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Enable…") {
                // Try the OS prompt first; if it won't show (already decided), jump to Settings.
                if !Permissions.requestScreenRecordingAccess() {
                    SystemSettings.open(.screenCapture)
                }
            }
            .buttonStyle(.link)
            .controlSize(.small)
        }
        .padding(.horizontal, DashboardTheme.hInset)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var snoozeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.secondary)
            Text(coordinator.snoozedUntil.map { "Tracking paused until \(Self.clock.string(from: $0))" } ?? "Tracking paused")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Resume") { coordinator.endSnooze() }
                .controlSize(.small)
        }
        .padding(.horizontal, DashboardTheme.hInset)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch appState.selectedTab {
            case .day: DayView()
            case .apps: AppsView()
            case .rules: RulesView()
            }
        }
    }
}
