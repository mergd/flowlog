import SwiftUI

enum DashboardTheme {
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let defaultWidth: CGFloat = 720
    static let defaultHeight: CGFloat = 400
    static let minWidth: CGFloat = 640
    static let minHeight: CGFloat = 320
}

extension View {
    func dashboardSurface() -> some View {
        background(DashboardTheme.surface)
    }

    func dashboardPlainList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
    }

    func dashboardWindowFrame() -> some View {
        frame(
            minWidth: DashboardTheme.minWidth,
            maxWidth: .infinity,
            minHeight: DashboardTheme.minHeight,
            maxHeight: .infinity
        )
    }
}

struct CategoryPill: View {
    let category: ActivityCategory

    var body: some View {
        Text(category.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(CategoryColors.color(for: category))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(CategoryColors.color(for: category).opacity(0.14))
            .clipShape(Capsule())
    }
}

struct DurationLabel: View {
    let seconds: TimeInterval

    var body: some View {
        Text(format(seconds))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private func format(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let h = m / 60
        if h > 0 { return "\(h)h \(m % 60)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}
