import SwiftUI

struct CalendarView: View {
    @State private var sessions: [Session] = []

    private let startHour = 6
    private let endHour = 23
    private let hourHeight: CGFloat = 44
    private let labelWidth: CGFloat = 48

    private var visibleHours: Int { endHour - startHour + 1 }
    private var gridHeight: CGFloat { CGFloat(visibleHours) * hourHeight }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()

    var body: some View {
        Group {
            if sessions.isEmpty {
                DashboardEmptyState(
                    symbol: "calendar",
                    title: "No activity yet",
                    message: "Your day fills in here as Flowlog tracks your sessions."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        DashboardDetailHeader("Calendar", subtitle: daySubtitle)

                        HStack(alignment: .top, spacing: 0) {
                            hourLabels
                            calendarGrid
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardSurface()
        .dashboardAutoReload(reload)
    }

    private var daySubtitle: String {
        Self.dayFormatter.string(from: Date())
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(startHour...endHour, id: \.self) { hour in
                Text(Self.hourFormatter.string(from: hourDate(hour)).lowercased())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(width: labelWidth, height: hourHeight, alignment: .topTrailing)
                    .padding(.trailing, 8)
            }
        }
    }

    private var calendarGrid: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                hourGridLines(width: geo.size.width)

                ForEach(sessions) { session in
                    sessionBlock(session, width: geo.size.width)
                }
            }
        }
        .frame(height: gridHeight)
        .frame(maxWidth: .infinity)
    }

    private func hourGridLines(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(startHour...endHour, id: \.self) { hour in
                Rectangle()
                    .fill(Color.primary.opacity(hour == startHour ? 0.08 : 0.04))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .frame(height: hourHeight, alignment: .top)
            }
        }
        .frame(width: width)
    }

    private func sessionBlock(_ session: Session, width: CGFloat) -> some View {
        let range = clippedRange(for: session)
        let y = offsetY(for: range.start)
        let height = max(blockHeight(from: range.start, to: range.end), 18)
        let title = SiteCatalog.displayTitle(for: session)

        return HStack(spacing: 5) {
            AppIconView(bundleId: session.bundleId, size: 12)
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: width - 4, height: height, alignment: .leading)
        .background(CategoryColors.color(for: session.activityCategory).opacity(0.22))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CategoryColors.color(for: session.activityCategory))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .offset(x: 2, y: y)
    }

    private struct TimeRange {
        let start: Date
        let end: Date
    }

    private func clippedRange(for session: Session) -> TimeRange {
        let dayStart = hourDate(startHour)
        let dayEnd = hourDate(endHour).addingTimeInterval(3600)
        let sessionEnd = session.end ?? Date()
        let start = max(session.start, dayStart)
        let end = min(sessionEnd, dayEnd)
        return TimeRange(start: start, end: max(end, start.addingTimeInterval(60)))
    }

    private func offsetY(for date: Date) -> CGFloat {
        let dayStart = hourDate(startHour)
        let hours = date.timeIntervalSince(dayStart) / 3600
        return CGFloat(hours) * hourHeight
    }

    private func blockHeight(from start: Date, to end: Date) -> CGFloat {
        CGFloat(end.timeIntervalSince(start) / 3600) * hourHeight
    }

    private func hourDate(_ hour: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func reload() {
        sessions = DashboardData.sessionsToday()
            .sorted { $0.start < $1.start }
    }
}
