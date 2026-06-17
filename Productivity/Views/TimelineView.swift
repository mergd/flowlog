import SwiftUI
import AppKit

struct TimelineView: View {
    @State private var sessions: [Session] = []
    @State private var selectedScreenshot: String?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Group {
            if sessions.isEmpty {
                DashboardEmptyState(
                    symbol: "clock",
                    title: "No sessions yet",
                    message: "Your timeline fills in as you move between apps."
                )
            } else {
                List(sessions) { session in
                    timelineRow(session)
                        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                }
                .dashboardPlainList()
                .safeAreaInset(edge: .top) {
                    DashboardDetailHeader("Timeline", subtitle: "\(sessions.count) sessions today")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardSurface()
        .sheet(item: Binding(
            get: { selectedScreenshot.map { ScreenshotItem(id: $0) } },
            set: { selectedScreenshot = $0?.id }
        )) { item in
            if let image = ScreenshotStore.shared.loadImage(id: item.id) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 400, minHeight: 300)
                    .padding()
            }
        }
        .dashboardAutoReload(reload)
    }

    private func timelineRow(_ session: Session) -> some View {
        let title = SiteCatalog.displayTitle(for: session)
        let subtitle = SiteCatalog.displaySubtitle(for: session)

        return HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CategoryColors.color(for: session.activityCategory))
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if session.activityCategory != .uncategorized {
                        CategoryPill(category: session.activityCategory)
                    }
                    Spacer(minLength: 4)
                    Text(timelineTimeRange(session))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    DurationLabel(seconds: session.duration)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            categoryButtons(for: session)
            if session.screenshotId != nil {
                Button("View capture") { selectedScreenshot = session.screenshotId }
            }
        }
    }

    @ViewBuilder
    private func categoryButtons(for session: Session) -> some View {
        ForEach(ActivityCategory.allCases, id: \.self) { cat in
            Button(cat.displayName) {
                Task {
                    try? await Classifier.shared.applyManualCorrection(
                        session: session,
                        category: cat,
                        siteLabel: session.siteLabel
                    )
                    reload()
                }
            }
        }
    }

    private func timelineTimeRange(_ session: Session) -> String {
        let end = session.end ?? Date()
        return "\(Self.timeFormatter.string(from: session.start)) to \(Self.timeFormatter.string(from: end))"
    }

    private func reload() {
        sessions = DashboardData.sessionsToday()
    }
}

private struct ScreenshotItem: Identifiable {
    let id: String
}
