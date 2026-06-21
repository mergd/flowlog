import SwiftUI

struct SessionRowView: View {
    let session: Session
    var showsTimeRange = true
    var onScreenshotTap: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CategoryRingIcon(category: session.activityCategory, size: 24) {
                sessionIcon
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(SiteCatalog.displayTitle(for: session))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Camera sits before the time in a fixed-width slot so the
                    // time/duration columns stay aligned across rows whether or
                    // not a row has a capture.
                    if onScreenshotTap != nil {
                        cameraButton.frame(width: 18)
                    }

                    if showsTimeRange {
                        Text(timeRange)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }

                    if session.duration >= 60 {
                        DurationLabel(seconds: session.duration)
                    }
                }

                if let subtitle = detailLine {
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
    private var cameraButton: some View {
        if let screenshotId = session.screenshotId {
            Button {
                onScreenshotTap?(screenshotId)
            } label: {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("View capture")
        }
    }

    private var detailLine: String? {
        var parts: [String] = []
        if session.screenshotId != nil {
            parts.append("Screen capture")
        }
        if let subtitle = SiteCatalog.displaySubtitle(for: session) {
            parts.append(subtitle)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
