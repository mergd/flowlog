import SwiftUI

struct CategoryColors {
    static func color(for category: ActivityCategory) -> Color {
        switch category {
        case .productive: Color(red: 0.28, green: 0.78, blue: 0.58)
        case .neutral: Color.secondary.opacity(0.55)
        case .distracting: Color(red: 0.92, green: 0.38, blue: 0.42)
        case .uncategorized: Color.secondary.opacity(0.35)
        }
    }
}

struct TodayView: View {
    @State private var totals: [String: TimeInterval] = [:]
    @State private var score: Int?

    private var trackedSeconds: TimeInterval {
        totals.values.reduce(0, +)
    }

    private var hasData: Bool {
        trackedSeconds > 0
    }

    var body: some View {
        Group {
            if hasData {
                trackedContent
            } else {
                DashboardEmptyState(
                    symbol: "chart.line.uptrend.xyaxis",
                    title: "Nothing tracked yet",
                    message: "Switch between apps and Flowlog will start building your focus score here."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardSurface()
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .productivityDataDidChange)) { _ in reload() }
    }

    private var trackedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DashboardDetailHeader("Today", subtitle: "How focused you've been")

                VStack(alignment: .leading, spacing: 6) {
                    if let score {
                        Text("\(score)%")
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("productive")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                        Text("Score updates after 5 min of tracking")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                categoryBar

                VStack(spacing: 0) {
                    ForEach(ActivityCategory.allCases, id: \.self) { cat in
                        let seconds = totals[cat.rawValue] ?? 0
                        HStack(spacing: 12) {
                            Circle()
                                .fill(CategoryColors.color(for: cat))
                                .frame(width: 7, height: 7)
                            Text(cat.displayName)
                                .font(.subheadline)
                            Spacer()
                            Text(format(seconds))
                                .font(.subheadline)
                                .foregroundStyle(seconds > 0 ? .primary : .tertiary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 11)

                        if cat != ActivityCategory.allCases.last {
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var categoryBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(ActivityCategory.allCases, id: \.self) { cat in
                    let seconds = totals[cat.rawValue] ?? 0
                    let width = trackedSeconds > 0 ? seconds / trackedSeconds * geo.size.width : 0
                    if width > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(CategoryColors.color(for: cat))
                            .frame(width: max(width, 4))
                    }
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func reload() {
        totals = (try? DatabaseManager.shared.categoryTotalsToday()) ?? [:]
        score = FocusScore.percent(from: totals)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let h = m / 60
        if h > 0 { return "\(h)h \(m % 60)m" }
        if m > 0 { return "\(m)m" }
        return "0m"
    }
}

extension Notification.Name {
    static let productivityDataDidChange = Notification.Name("productivityDataDidChange")
}
