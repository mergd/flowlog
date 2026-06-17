import SwiftUI

struct WorkLogView: View {
    @State private var logs: [WorkLogEntry] = []
    @State private var isGenerating = false

    var body: some View {
        Group {
            if logs.isEmpty && !isGenerating {
                DashboardEmptyState(
                    symbol: "text.book.closed",
                    title: "No work logs yet",
                    message: "Generate a summary for the last hour to get a short narrative of what you worked on and where focus slipped."
                )
            } else {
                List(logs) { log in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(log.headline)
                            .font(.headline)
                        Text(log.narrative)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let focus = log.primaryFocus {
                            Label(focus, systemImage: "target")
                                .font(.caption)
                        }
                        ForEach(log.distractions, id: \.self) { d in
                            Label(d, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(CategoryColors.color(for: .distracting))
                        }
                        Text("\(log.productiveMinutes)m productive · \(log.distractingMinutes)m distracting")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .dashboardPlainList()
                .safeAreaInset(edge: .top) {
                    DashboardDetailHeader("Work Log", subtitle: "AI summaries of your focus")
                }
            }
        }
        .dashboardSurface()
        .overlay {
            if isGenerating && logs.isEmpty {
                ProgressView("Generating…")
                    .controlSize(.regular)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await generateLastHour() }
                } label: {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Generate Last Hour", systemImage: "sparkles")
                    }
                }
                .disabled(isGenerating)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        logs = (try? DatabaseManager.shared.workLogs()) ?? []
    }

    private func generateLastHour() async {
        isGenerating = true
        defer { isGenerating = false }
        let end = Date()
        let start = end.addingTimeInterval(-3600)
        _ = try? await WorkLogGenerator.shared.generate(for: start, periodEnd: end)
        reload()
    }
}
