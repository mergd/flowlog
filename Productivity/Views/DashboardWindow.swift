import SwiftUI

struct DashboardWindow: View {
    @Bindable var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, selection: Bindable(appState).selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 160, ideal: 168, max: 220)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.coordinator.refreshMenuBarScore()
                    NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .dashboardWindowFrame()
        .dashboardSurface()
        .background(WindowChromeSync(windowID: "dashboard"))
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch appState.selectedTab {
            case .today: TodayView()
            case .workLog: WorkLogView()
            case .timeline: TimelineView()
            case .apps: AppsView()
            case .rules: RulesView()
            case .settings: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WindowChromeSync: NSViewRepresentable {
    let windowID: String

    func makeNSView(context: Context) -> WindowChromeSyncView {
        WindowChromeSyncView(windowID: windowID)
    }

    func updateNSView(_ nsView: WindowChromeSyncView, context: Context) {
        nsView.windowID = windowID
        nsView.syncChrome()
    }
}

private final class WindowChromeSyncView: NSView {
    var windowID: String

    init(windowID: String) {
        self.windowID = windowID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncChrome()
    }

    func syncChrome() {
        guard let window else { return }
        WindowChrome.apply(to: window, id: windowID)
    }
}
