import SwiftUI

enum DashboardTheme {
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let defaultWidth: CGFloat = 680
    static let defaultHeight: CGFloat = 420
    static let minWidth: CGFloat = 560
    static let minHeight: CGFloat = 320

    /// Standard horizontal content inset (macOS HIG ~20pt).
    static let hInset: CGFloat = 20
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

/// A simple flow layout: lays subviews left-to-right, wrapping to a new line when
/// the next item would overflow the available width. Used for legends/chips that
/// must wrap rather than truncate or overflow at narrow widths.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxLineWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                maxLineWidth = max(maxLineWidth, x - spacing)
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxLineWidth = max(maxLineWidth, x - spacing)
        let width = maxWidth == .infinity ? maxLineWidth : maxWidth
        return CGSize(width: max(0, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Wraps a row icon with a category-colored ring, replacing the old colored bar.
/// The ring sits just outside the icon with a small gap so the icon stays legible.
struct CategoryRingIcon<Content: View>: View {
    let category: ActivityCategory
    let size: CGFloat
    var lineWidth: CGFloat = 1.5
    var gap: CGFloat = 2.5
    @ViewBuilder var icon: () -> Content

    var body: some View {
        let outer = size + (gap + lineWidth) * 2
        ZStack {
            RoundedRectangle(cornerRadius: outer * 0.26, style: .continuous)
                .strokeBorder(CategoryColors.color(for: category), lineWidth: lineWidth)
                .frame(width: outer, height: outer)

            icon()
                .frame(width: size, height: size)
        }
        .frame(width: outer, height: outer)
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

enum ClockRange {
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    /// "4:18–4:52", collapsed to just "4:18" when start and end fall in the same minute.
    static func label(_ start: Date, _ end: Date) -> String {
        let s = formatter.string(from: start)
        let e = formatter.string(from: end)
        return s == e ? s : "\(s)–\(e)"
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

extension Notification.Name {
    static let productivityDataDidChange = Notification.Name("productivityDataDidChange")
}

struct CategoryPill: View {
    let category: ActivityCategory

    var body: some View {
        Label {
            Text(category.displayName)
        } icon: {
            Image(systemName: category.iconName)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption2.weight(.medium))
        .foregroundStyle(CategoryColors.color(for: category))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(CategoryColors.color(for: category).opacity(0.14))
        .clipShape(Capsule())
    }
}

/// Small category glyph in its category color — for compact rows/legends.
struct CategoryIcon: View {
    let category: ActivityCategory
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: category.iconName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(CategoryColors.color(for: category))
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
