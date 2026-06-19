import SwiftUI

struct SessionRowView: View {
    let session: Session
    var showsTimeRange = true
    var onScreenshotTap: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CategoryColors.color(for: session.activityCategory))
                .frame(width: 3, height: 34)

            sessionIcon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(SiteCatalog.displayTitle(for: session))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if showsTimeRange {
                        Text(timeRange)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }

                    if session.duration >= 60 {
                        DurationLabel(seconds: session.duration)
                    }

                    if let screenshotId = session.screenshotId, onScreenshotTap != nil {
                        SessionScreenshotThumb(screenshotId: screenshotId) {
                            onScreenshotTap?(screenshotId)
                        }
                    }
                }

                if let subtitle = SiteCatalog.displaySubtitle(for: session) {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var sessionIcon: some View {
        if BrowserDetector.isBrowser(session.bundleId), let siteLabel = session.siteLabel {
            SiteIconView(
                siteLabel: siteLabel,
                domain: SiteCatalog.parse(windowTitle: session.windowTitle).domain,
                size: 24,
                browserBundleId: session.bundleId
            )
        } else {
            AppIconView(bundleId: session.bundleId, size: 24)
        }
    }

    private var timeRange: String {
        ClockRange.label(session.start, session.end ?? Date())
    }
}
