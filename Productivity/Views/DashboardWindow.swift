import SwiftUI

struct DashboardWindow: View {
    @Bindable var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: DashboardTheme.minWidth, minHeight: DashboardTheme.minHeight)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.coordinator.refreshMenuBarSession()
                    NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .dashboardSurface()
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch appState.selectedTab {
            case .today: TodayView()
            case .calendar: CalendarView()
            case .timeline: TimelineView()
            case .apps: AppsView()
            case .rules: RulesView()
            case .settings: SettingsView()
            }
        }
    }
}
