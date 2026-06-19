import SwiftUI
import AgentTag

struct DashboardWindow: View {
    @Bindable var appState: AppState
    @ObservedObject private var coordinator = TrackingCoordinator.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var screenRecordingGranted = Permissions.isScreenRecordingGranted()

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(DashboardTab.allCases, selection: $appState.selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(DashboardTheme.surface)
            .navigationSplitViewColumnWidth(168)
            .agentTag("sidebarList")
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .agentTag("dashboardDetail")
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: DashboardTheme.minWidth, minHeight: DashboardTheme.minHeight)
        .safeAreaInset(edge: .top, spacing: 0) {
            if coordinator.isSnoozed { snoozeBanner }
        }
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .dashboardSurface()
        .agentTagOverlay()
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
