import SwiftUI

enum DashboardTheme {
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let defaultWidth: CGFloat = 720
    static let defaultHeight: CGFloat = 400
    static let minWidth: CGFloat = 640
    static let minHeight: CGFloat = 320
}

enum CategoryColors {
    static func color(for category: ActivityCategory) -> Color {
        switch category {
        case .productive: Color(red: 0.28, green: 0.78, blue: 0.58)
        case .neutral: Color.secondary.opacity(0.55)
        case .distracting: Color(red: 0.92, green: 0.38, blue: 0.42)
        case .uncategorized: Color.secondary.opacity(0.35)
        }
    }
}

enum DurationFormatting {
    static func short(_ seconds: TimeInterval, zeroLabel: String = "<1m") -> String {
        let m = Int(seconds) / 60
        let h = m / 60
        if h > 0 { return "\(h)h \(m % 60)m" }
        if m > 0 { return "\(m)m" }
        return zeroLabel
    }
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

    func dashboardAutoReload(_ action: @escaping () -> Void) -> some View {
        onAppear(perform: action)
            .onReceive(NotificationCenter.default.publisher(for: .productivityDataDidChange)) { _ in action() }
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
        Text(DurationFormatting.short(seconds))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}
