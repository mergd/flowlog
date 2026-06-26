import SwiftUI
import AppKit

enum ActivityScope: String, CaseIterable, Identifiable {
    case day, week
    var id: String { rawValue }
    var title: String { self == .day ? "Day" : "Week" }
}

enum DayMode: String, CaseIterable, Identifiable {
    case blocks, detail
    var id: String { rawValue }
    var title: String { self == .blocks ? "Blocks" : "Detail" }
}

struct DayView: View {
    @State private var scope: ActivityScope = .day
    @State private var dayMode: DayMode = .blocks
    @State private var anchor = Date()
    @State private var sessions: [Session] = []
    @State private var blocks: [ActivityBlock] = []
    @State private var pauses: [Pause] = []
    @State private var totals: [String: TimeInterval] = [:]
    @State private var topicTotals: [String: TimeInterval] = [:]
    // Derived data is memoized here and rebuilt only in `reload()`. It used to be
    // recomputed inside `body` (bins 3x per render, the timeline sort chain once),
    // which made every 2-second data notification re-run all of it on the main thread.
    @State private var cachedBins: [UsageBin] = []
    @State private var cachedTimeline: [TimelineItem] = []
    @State private var selectedScreenshot: String?
    @State private var reclassifyTarget: ReclassifyTarget?
    @State private var selectedBinId: Int?

    private let calendar = Calendar.current
    private let categoryOrder: [ActivityCategory] = [.productive, .neutral, .distracting, .uncategorized]

    private var trackedSeconds: TimeInterval { totals.values.reduce(0, +) }
    private var focusScore: Int? { FocusScore.percent(from: totals) }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            if trackedSeconds == 0 {
                DashboardEmptyState(
                    symbol: "chart.bar.xaxis",
                    title: "Nothing tracked \(scope == .day ? "this day" : "this week")",
                    message: "Activity shows up here as you move between apps. Try another \(scope.title.lowercased()) or jump back to today."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        statsRow
                        UsageBarChart(
                            bins: cachedBins,
                            order: categoryOrder,
                            inProgressBinId: inProgressBinId,
                            inProgressFraction: inProgressFraction,
                            selectedBinId: selectedBinId,
                            onTapBin: tapBin
                        )
                        .padding(.horizontal, DashboardTheme.hInset)
                        legend
                            .padding(.horizontal, DashboardTheme.hInset)
                        topicBreakdown
                        Divider().padding(.horizontal, DashboardTheme.hInset)
                        contentList
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardSurface()
        .sheet(item: $reclassifyTarget) { target in
            SessionReclassifySheet(session: target.session) { reload() }
        }
        .sheet(item: Binding(
            get: { selectedScreenshot.map { ScreenshotItem(id: $0) } },
            set: { selectedScreenshot = $0?.id }
        )) { item in
            ScreenshotPreview(screenshotId: item.id) { selectedScreenshot = nil }
        }
        .dashboardAutoReload(reload)
        .onChange(of: scope) { _, _ in selectedBinId = nil; reload() }
    }

    // MARK: - Navigation

    private var navBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Activity")
                    .font(.title2.weight(.semibold))
                Text(rangeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $scope) {
                ForEach(ActivityScope.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            HStack(spacing: 2) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous \(scope.title.lowercased())")
                Button { selectedBinId = nil; anchor = Date(); reload() } label: { Text("Today") }
                    .disabled(isCurrentPeriod)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next \(scope.title.lowercased())")
                    .disabled(isCurrentPeriod)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, DashboardTheme.hInset)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func step(_ direction: Int) {
        let component: Calendar.Component = scope == .day ? .day : .weekOfYear
        if let next = calendar.date(byAdding: component, value: direction, to: anchor) {
            selectedBinId = nil
            anchor = next
            reload()
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 20) {
            statItem(value: DurationFormatting.short(trackedSeconds, zeroLabel: "0m"), label: "tracked")
            if let focusScore {
                statItem(value: "\(focusScore)%", label: "productive")
            }
            statItem(value: "\(sessions.count)", label: sessions.count == 1 ? "session" : "sessions")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DashboardTheme.hInset)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var legend: some View {
        FlowLayout(spacing: 16, lineSpacing: 6) {
            ForEach(categoryOrder, id: \.self) { cat in
                let secs = totals[cat.rawValue] ?? 0
                if secs > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(CategoryColors.color(for: cat)).frame(width: 7, height: 7)
                        Text(cat.displayName).font(.caption).foregroundStyle(.secondary)
                        Text(DurationFormatting.short(secs))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var topicBreakdown: some View {
        let rows = topicRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("By topic")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(rows, id: \.topic) { row in
                    let fraction = trackedSeconds > 0 ? row.seconds / trackedSeconds : 0
                    HStack(spacing: 8) {
                        Image(systemName: row.topic.iconName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(row.topic.displayName)
                            .font(.caption)
                        Spacer(minLength: 8)
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Text(DurationFormatting.short(row.seconds))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, DashboardTheme.hInset)
        }
    }

    // MARK: - Content list

    @ViewBuilder
    private var contentList: some View {
        switch scope {
        case .day:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(dayMode == .blocks ? "Blocks" : "Sessions")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    if let range = selectedHourRange {
                        Button {
                            selectedBinId = nil
                        } label: {
                            HStack(spacing: 3) {
                                Text(hourChipLabel(range))
                                Image(systemName: "xmark.circle.fill")
                            }
                            .font(.caption2.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Picker("", selection: $dayMode) {
                        ForEach(DayMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                }
                .padding(.horizontal, DashboardTheme.hInset)

                if dayMode == .blocks {
                    blockList
                } else {
                    sessionList
                }
            }
        case .week:
            weekDayList
        }
    }

    private var blockList: some View {
        LazyVStack(spacing: 0) {
            let ordered = filteredBlocks
            ForEach(ordered) { block in
                BlockRowView(block: block)
                    .padding(.horizontal, DashboardTheme.hInset)
                    .padding(.vertical, 3)
                if block.id != ordered.last?.id {
                    Divider().padding(.leading, DashboardTheme.hInset + 32)
                }
            }
        }
    }

    private var filteredBlocks: [ActivityBlock] {
        let ordered = blocks.sorted { $0.start > $1.start }
        guard let range = selectedHourRange else { return ordered }
        return ordered.filter { overlaps(range, start: $0.start, end: $0.end) }
    }

    private func hourChipLabel(_ range: Range<Date>) -> String {
        "\(Self.clockFormatter.string(from: range.lowerBound))–\(Self.clockFormatter.string(from: range.upperBound))"
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            let items = displayedTimelineItems
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    switch item {
                    case let .session(item):
                        HStack(spacing: 2) {
                            SessionRowView(session: item.session) { selectedScreenshot = $0 }
                            Menu {
                                sessionMenu(for: item)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("Actions")
                        }
                        .padding(.horizontal, DashboardTheme.hInset)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .contextMenu { sessionMenu(for: item) }
                        .onTapGesture(count: 2) { reclassifyTarget = ReclassifyTarget(session: item.session) }
                    case let .gap(start, end):
                        gapRow(start: start, end: end)
                    case let .pause(start, end):
                        pauseRow(start: start, end: end)
                    }

                    if item.id != items.last?.id {
                        Divider().padding(.leading, DashboardTheme.hInset + 32)
                    }
                }
            }
        }
    }

    private func pauseRow(start: Date, end: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text("Paused")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Self.clockFormatter.string(from: start))–\(Self.clockFormatter.string(from: end))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer(minLength: 8)
            Text(DurationFormatting.short(end.timeIntervalSince(start)))
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, DashboardTheme.hInset)
        .padding(.vertical, 5)
    }

    private func gapRow(start: Date, end: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 24)
            Text("Untracked")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Self.clockFormatter.string(from: start))–\(Self.clockFormatter.string(from: end))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer(minLength: 8)
            Text(DurationFormatting.short(end.timeIntervalSince(start)))
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, DashboardTheme.hInset)
        .padding(.vertical, 5)
    }

    private var weekDayList: some View {
        let days = cachedBins.filter { $0.total > 0 }.reversed().map { $0 }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Days")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DashboardTheme.hInset)

            VStack(spacing: 0) {
                ForEach(days) { bin in
                    Button {
                        scope = .day
                        anchor = bin.date
                        reload()
                    } label: {
                        daySummaryRow(bin)
                    }
                    .buttonStyle(.plain)

                    if bin.id != days.last?.id {
                        Divider().padding(.leading, DashboardTheme.hInset)
                    }
                }
            }
        }
    }

    private func daySummaryRow(_ bin: UsageBin) -> some View {
        let total = bin.total
        let productive = bin.totals[.productive] ?? 0
        let pct = total > 0 ? Int((productive / total) * 100) : 0
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.weekdayFormatter.string(from: bin.date))
                    .font(.subheadline.weight(.medium))
                Text(Self.dayMonthFormatter.string(from: bin.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 80, alignment: .leading)

            CategoryStackBar(totals: bin.totals, order: categoryOrder, total: total)
                .frame(height: 8)
                .clipShape(Capsule())

            Text("\(pct)%")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(CategoryColors.color(for: .productive))
                .frame(width: 36, alignment: .trailing)

            Text(DurationFormatting.short(total, zeroLabel: "0m"))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DashboardTheme.hInset)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sessionMenu(for item: TimelineSession) -> some View {
        let session = item.session
        Button("Reclassify…") { reclassifyTarget = ReclassifyTarget(session: session) }
        if session.screenshotId != nil {
            Button("View capture") { selectedScreenshot = session.screenshotId }
        }
        Divider()
        Button("Remove from timeline", role: .destructive) {
            removeFromTimeline(item)
        }
    }

    private func removeFromTimeline(_ item: TimelineSession) {
        guard !item.sourceIds.isEmpty else { return }
        try? DatabaseManager.shared.markSessionsDeleted(ids: item.sourceIds)
        NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
        reload()
    }

    // MARK: - Range + binning

    private var range: Range<Date> {
        switch scope {
        case .day:
            let start = calendar.startOfDay(for: anchor)
            return start ..< (calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? calendar.startOfDay(for: anchor)
            return start ..< (calendar.date(byAdding: .day, value: 7, to: start) ?? start)
        }
    }

    private var isCurrentPeriod: Bool {
        range.upperBound > Date()
    }

    private func makeBins() -> [UsageBin] {
        let (starts, size) = binLayout()
        let now = Date()
        // Keep the whole day/week on the axis; slots that haven't started yet are
        // flagged so the chart leaves them blank instead of drawing an empty slot.
        var result = starts.enumerated().map { idx, date in
            UsageBin(id: idx, label: binLabel(date, index: idx), date: date, totals: [:], isFuture: date > now)
        }
        for session in sessions {
            let sStart = session.start
            let sEnd = session.end ?? session.start.addingTimeInterval(session.duration)
            let cat = session.activityCategory
            for i in result.indices {
                let bStart = result[i].date
                let bEnd = bStart.addingTimeInterval(size)
                let overlap = min(sEnd, bEnd).timeIntervalSince(max(sStart, bStart))
                if overlap > 0 { result[i].totals[cat, default: 0] += overlap }
            }
        }
        for pause in pauses {
            let pStart = pause.start
            let pEnd = pause.end ?? now
            for i in result.indices {
                let bStart = result[i].date
                let bEnd = bStart.addingTimeInterval(size)
                let overlap = min(pEnd, bEnd).timeIntervalSince(max(pStart, bStart))
                if overlap > 0 { result[i].pausedSeconds += overlap }
            }
        }
        return result
    }

    /// The bin currently in progress (this hour today / today within the week).
    private var inProgressBinId: Int? {
        guard isCurrentPeriod else { return nil }
        let now = Date()
        let size: TimeInterval = scope == .day ? 3600 : 86400
        return cachedBins.first { $0.date <= now && now < $0.date.addingTimeInterval(size) }?.id
    }

    /// How far through the in-progress slot (hour/day) we currently are, 0…1.
    private var inProgressFraction: Double {
        guard isCurrentPeriod else { return 0 }
        let now = Date()
        let size: TimeInterval = scope == .day ? 3600 : 86400
        guard let bin = cachedBins.first(where: { $0.date <= now && now < $0.date.addingTimeInterval(size) }) else { return 0 }
        return min(1, max(0, now.timeIntervalSince(bin.date) / size))
    }

    private func binLayout() -> ([Date], TimeInterval) {
        switch scope {
        case .day:
            let dayStart = range.lowerBound
            let starts = (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: dayStart) }
            return (starts, 3600)
        case .week:
            let weekStart = range.lowerBound
            let starts = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            return (starts, 86400)
        }
    }

    private func binLabel(_ date: Date, index: Int) -> String {
        switch scope {
        case .day:
            guard index % 6 == 0 else { return "" }
            let h = calendar.component(.hour, from: date)
            let hr = h % 12 == 0 ? 12 : h % 12
            return "\(hr)\(h < 12 ? "a" : "p")"
        case .week:
            return Self.weekdayNarrowFormatter.string(from: date)
        }
    }

    private func tapBin(_ bin: UsageBin) {
        switch scope {
        case .week:
            guard bin.total > 0 else { return }
            selectedBinId = nil
            scope = .day
            anchor = bin.date
            reload()
        case .day:
            // Drill into the hour: toggle a filter on the list below.
            guard bin.total > 0 else { return }
            selectedBinId = (selectedBinId == bin.id) ? nil : bin.id
        }
    }

    /// The hour range the user drilled into via the bar chart, if any.
    private var selectedHourRange: Range<Date>? {
        guard scope == .day, let id = selectedBinId,
              let bin = cachedBins.first(where: { $0.id == id }) else { return nil }
        return bin.date ..< bin.date.addingTimeInterval(3600)
    }

    private func overlaps(_ range: Range<Date>, start: Date, end: Date) -> Bool {
        start < range.upperBound && end > range.lowerBound
    }

    private var rangeLabel: String {
        switch scope {
        case .day:
            if calendar.isDateInToday(anchor) { return "Today" }
            if calendar.isDateInYesterday(anchor) { return "Yesterday" }
            return Self.fullDayFormatter.string(from: anchor)
        case .week:
            let start = range.lowerBound
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return "\(Self.rangeFormatter.string(from: start)) – \(Self.rangeFormatter.string(from: end))"
        }
    }

    // MARK: - Data

    /// Sessions interleaved (newest first) with "untracked" gaps longer than the threshold.
    private func makeTimeline() -> [TimelineItem] {
        let chrono = mergedSessions.sorted { $0.session.start < $1.session.start }
        var items: [TimelineItem] = []
        for (index, item) in chrono.enumerated() {
            items.append(.session(item))
            guard index < chrono.count - 1 else { continue }
            let session = item.session
            let gapStart = session.end ?? session.start
            let gapEnd = chrono[index + 1].session.start
            guard gapEnd.timeIntervalSince(gapStart) >= Self.untrackedGapThreshold else { continue }
            // A deliberate snooze covering this gap reads as "Paused", not "Untracked".
            if let pause = pauses.first(where: { $0.start < gapEnd && ($0.end ?? Date()) > gapStart }) {
                items.append(.pause(start: max(gapStart, pause.start), end: min(gapEnd, pause.end ?? Date())))
            } else {
                items.append(.gap(start: gapStart, end: gapEnd))
            }
        }
        return items.reversed()
    }

    /// Timeline items, filtered to the drilled-in hour when one is selected.
    private var displayedTimelineItems: [TimelineItem] {
        guard let range = selectedHourRange else { return cachedTimeline }
        return cachedTimeline.filter { item in
            switch item {
            case let .session(item):
                let session = item.session
                return overlaps(range, start: session.start, end: session.end ?? session.start.addingTimeInterval(session.duration))
            case let .gap(start, end):
                return overlaps(range, start: start, end: end)
            case let .pause(start, end):
                return overlaps(range, start: start, end: end)
            }
        }
    }

    private static let untrackedGapThreshold: TimeInterval = 10 * 60

    private var mergedSessions: [TimelineSession] {
        let sorted = sessions.sorted { $0.start < $1.start }
        var merged: [TimelineSession] = []
        for session in sorted {
            if var last = merged.last?.session,
               last.bundleId == session.bundleId,
               last.siteLabel == session.siteLabel,
               last.category == session.category,
               session.start.timeIntervalSince(last.end ?? last.start) < 300 {
                last.duration += session.duration
                last.end = session.end ?? session.start
                if last.screenshotId == nil { last.screenshotId = session.screenshotId }
                var sourceIds = merged[merged.count - 1].sourceIds
                if let id = session.id { sourceIds.append(id) }
                merged[merged.count - 1] = TimelineSession(session: last, sourceIds: sourceIds)
            } else {
                let sourceIds = session.id.map { [$0] } ?? []
                merged.append(TimelineSession(session: session, sourceIds: sourceIds))
            }
        }
        return merged.sorted { $0.session.start > $1.session.start }
    }

    private func reload() {
        let r = range
        let isDay = scope == .day
        // The five DB reads ran synchronously on the main thread on every appear
        // and on every ~2s data notification. Move them off-main and assign the
        // results back on the main actor.
        Task { @MainActor in
            let fetched = await Task.detached(priority: .userInitiated) { () -> Fetched in
                Fetched(
                    sessions: DashboardData.sessions(in: r),
                    blocks: isDay ? DashboardData.blocks(in: r) : [],
                    pauses: DashboardData.pauses(in: r),
                    totals: DashboardData.categoryTotals(in: r),
                    topicTotals: DashboardData.topicTotals(in: r)
                )
            }.value
            sessions = fetched.sessions
            blocks = fetched.blocks
            pauses = fetched.pauses
            totals = fetched.totals
            topicTotals = fetched.topicTotals
            cachedBins = makeBins()
            cachedTimeline = makeTimeline()
        }
    }

    private struct Fetched: Sendable {
        let sessions: [Session]
        let blocks: [ActivityBlock]
        let pauses: [Pause]
        let totals: [String: TimeInterval]
        let topicTotals: [String: TimeInterval]
    }

    /// Topics with tracked time, largest first. The orthogonal genre axis
    /// (Social, Developer, Video…) alongside the productive/distracting split.
    private var topicRows: [(topic: ActivityTopic, seconds: TimeInterval)] {
        topicTotals
            .compactMap { key, secs -> (ActivityTopic, TimeInterval)? in
                guard secs > 0, let topic = ActivityTopic(rawValue: key) else { return nil }
                return (topic, secs)
            }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Formatters

    private static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .full; return f
    }()
    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
    private static let weekdayNarrowFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f
    }()
    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()
}

/// One activity block in the day timeline: dominant site/app, the other apps it
/// spanned, category, switch count, time range, and active duration.
struct BlockRowView: View {
    let block: ActivityBlock
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                CategoryRingIcon(category: block.category, size: 24) {
                    icon
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(block.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(ClockRange.label(block.start, block.end))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        if block.activeDuration >= 60 {
                            DurationLabel(seconds: block.activeDuration)
                        }
                    }
                    secondaryLine
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(block.shares) { share in
                        HStack(spacing: 8) {
                            shareIcon(share, size: 16, showBadge: true)
                            Text(share.label)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            DurationLabel(seconds: share.duration)
                        }
                    }
                }
                .padding(.leading, 37)
                .padding(.top, 1)
                // Fade in place; the row height animates the rows below. A `.move(edge: .top)`
                // here slid the content up *over* the trigger on close, which looked wrong.
                .transition(.opacity)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var secondaryLine: some View {
        HStack(spacing: 5) {
            CategoryIcon(category: block.category, size: 10)

            if block.shares.count <= 1 {
                Text(block.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                // Overlapping avatar-style stack of every app/site in the block.
                // No browser badge here — it's illegible at this size with the overlap.
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: -7) {
                        ForEach(block.shares.prefix(7)) { share in
                            shareIcon(share, size: 18, showBadge: false)
                                // Opaque base so overlapping chips fully cover each other
                                // (the letter-glyph fallback is otherwise translucent).
                                .background(
                                    RoundedRectangle(cornerRadius: 18 * 0.24, style: .continuous)
                                        .fill(DashboardTheme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18 * 0.24, style: .continuous)
                                        .strokeBorder(DashboardTheme.surface, lineWidth: 1.5)
                                )
                        }
                        if block.shares.count > 7 {
                            Text("+\(block.shares.count - 7)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 9)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Show apps in this block")
            }

            if block.switchCount > 1 {
                Text("· \(block.switchCount) switches")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private var icon: some View { shareIcon(block.shares.first, size: 24, showBadge: true) }

    @ViewBuilder
    private func shareIcon(_ share: BlockShare?, size: CGFloat, showBadge: Bool) -> some View {
        if let share, BrowserDetector.isBrowser(share.bundleId) {
            SiteIconView(
                siteLabel: share.label,
                domain: share.domain,
                size: size,
                browserBundleId: showBadge ? share.bundleId : nil
            )
        } else {
            AppIconView(bundleId: share?.bundleId ?? "", size: size)
        }
    }
}

private struct TimelineSession: Identifiable {
    var session: Session
    let sourceIds: [Int64]

    var id: String {
        if let first = sourceIds.first {
            return "s-\(first)"
        }
        return "s-\(Int64(session.start.timeIntervalSince1970))"
    }
}

private enum TimelineItem: Identifiable {
    case session(TimelineSession)
    case gap(start: Date, end: Date)
    case pause(start: Date, end: Date)

    var id: String {
        switch self {
        case let .session(item):
            return item.id
        case let .gap(start, end):
            return "g-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
        case let .pause(start, end):
            return "p-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
        }
    }
}

// MARK: - Bar chart

struct UsageBin: Identifiable {
    let id: Int
    let label: String
    let date: Date
    var totals: [ActivityCategory: TimeInterval]
    var isFuture: Bool = false
    var pausedSeconds: TimeInterval = 0
    var total: TimeInterval { totals.values.reduce(0, +) }
}

/// A horizontal proportional bar split by category (used in day-summary rows).
struct CategoryStackBar: View {
    let totals: [ActivityCategory: TimeInterval]
    let order: [ActivityCategory]
    let total: TimeInterval

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(order, id: \.self) { cat in
                    let secs = totals[cat] ?? 0
                    if secs > 0, total > 0 {
                        CategoryColors.color(for: cat)
                            .frame(width: geo.size.width * CGFloat(secs / total))
                    }
                }
            }
        }
    }
}

/// Screen Time–style vertical stacked bar chart.
struct UsageBarChart: View {
    let bins: [UsageBin]
    let order: [ActivityCategory]
    var height: CGFloat = 120
    var inProgressBinId: Int? = nil
    var inProgressFraction: Double = 0
    var selectedBinId: Int? = nil
    var onTapBin: ((UsageBin) -> Void)? = nil

    private var maxTotal: TimeInterval { max(bins.map { $0.total + $0.pausedSeconds }.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: bins.count > 7 ? 2 : 8) {
            ForEach(bins) { bin in
                VStack(spacing: 5) {
                    column(bin)
                    Text(bin.label.isEmpty ? " " : bin.label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        // fixedSize so axis labels like "12p" overflow their narrow
                        // column instead of truncating to "1…".
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func column(_ bin: UsageBin) -> some View {
        let combined = bin.total + bin.pausedSeconds
        let barHeight = height * CGFloat(combined / maxTotal)
        let isCurrent = bin.id == inProgressBinId
        let isSelected = bin.id == selectedBinId
        return VStack {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                ForEach(order, id: \.self) { cat in
                    let secs = bin.totals[cat] ?? 0
                    if secs > 0, combined > 0 {
                        CategoryColors.color(for: cat)
                            .frame(height: max(barHeight * CGFloat(secs / combined), 1))
                    }
                }
                if bin.pausedSeconds > 0, combined > 0 {
                    // Snoozed time — muted band, distinct from both tracked and empty.
                    Color.secondary.opacity(0.28)
                        .frame(height: max(barHeight * CGFloat(bin.pausedSeconds / combined), 1))
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .opacity(isCurrent ? 0.55 : 1)  // in-progress hour is partial → dim it
        }
        .frame(height: height)
        // Faint full-height slot behind each bar so untracked/empty time reads honestly.
        // Future slots stay blank; the current hour shows a progress fill up to "now".
        .background {
            if bin.isFuture {
                Color.clear
            } else if isCurrent {
                // Progressing bar: accent tint fills from the bottom up to the
                // fraction of the hour that has elapsed.
                VStack(spacing: 0) {
                    Color.primary.opacity(0.04)
                    Color.accentColor.opacity(0.16)
                        .frame(height: height * CGFloat(inProgressFraction))
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        }
        .overlay {
            // Current-time line at the top of the progress fill.
            if isCurrent {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 1.5)
                    .offset(y: height * CGFloat(0.5 - inProgressFraction))
            }
            if isSelected {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTapBin?(bin) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bin.label.isEmpty ? "Time slot" : bin.label)
        .accessibilityValue(DurationFormatting.short(bin.total, zeroLabel: "nothing tracked"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct ScreenshotItem: Identifiable {
    let id: String
}

/// Captured-screenshot preview shown as a sheet, with an explicit Done control
/// so it can be dismissed without relying on the Escape key.
private struct ScreenshotPreview: View {
    let screenshotId: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Capture")
                    .font(.headline)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Group {
                if let image = ScreenshotStore.shared.loadImage(id: screenshotId) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    DashboardEmptyState(
                        symbol: "photo",
                        title: "Capture unavailable",
                        message: "This screenshot has been deleted or is no longer on disk."
                    )
                }
            }
            .frame(minWidth: 400, minHeight: 300)
            .padding(16)
        }
        .frame(maxWidth: 720, maxHeight: 560)
    }
}

private struct ReclassifyTarget: Identifiable {
    let id: Int64
    let session: Session

    init(session: Session) {
        self.id = session.id ?? Int64(session.start.timeIntervalSince1970)
        self.session = session
    }
}
