import SwiftUI

struct MenuBarSessionHeader: View {
    let info: MenuBarSessionInfo
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                AppIconView(bundleId: info.bundleId, size: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.isIdle ? "Away" : info.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if info.isIdle {
                            Text("Idle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let startedAt = info.startedAt {
                            DurationLabel(seconds: now.timeIntervalSince(startedAt))
                        }

                        if let category = info.category, category != .uncategorized {
                            CategoryPill(category: category)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if let subtitle = info.subtitle, !info.isIdle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MenuBarTodaySection: View {
    @State private var totalSeconds: TimeInterval = 0
    @State private var focusPercent: Int?
    @State private var topApps: [(name: String, bundleId: String, duration: TimeInterval)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                DurationLabel(seconds: totalSeconds)
                Text("tracked")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if let focusPercent {
                    Text("\(focusPercent)% focus")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if !topApps.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(topApps.prefix(3), id: \.bundleId) { app in
                        HStack(spacing: 6) {
                            AppIconView(bundleId: app.bundleId, size: 14)
                            Text(app.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            DurationLabel(seconds: app.duration)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .productivityDataDidChange)) { _ in reload() }
    }

    private func reload() {
        let totals = (try? DatabaseManager.shared.categoryTotalsToday()) ?? [:]
        totalSeconds = totals.values.reduce(0, +)
        focusPercent = FocusScore.percent(from: totals)

        topApps = ((try? DatabaseManager.shared.appTotalsToday()) ?? [])
            .prefix(3)
            .map { (name: $0.appName, bundleId: $0.bundleId, duration: $0.duration) }
    }
}
