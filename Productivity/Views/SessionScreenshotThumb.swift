import SwiftUI
import AppKit

struct SessionScreenshotThumb: View {
    let screenshotId: String
    var width: CGFloat = 56
    var height: CGFloat = 36
    var onTap: () -> Void

    @State private var image: NSImage?
    @State private var checkedDisk = false

    private var isUnavailable: Bool { checkedDisk && image == nil }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: isUnavailable ? "photo.badge.exclamationmark" : "camera.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isUnavailable {
                            Text("Gone")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if image != nil {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(Color.accentColor))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isUnavailable ? "Capture expired or deleted" : "View capture")
        .onAppear(perform: load)
        .onChange(of: screenshotId) { _, _ in load() }
    }

    private func load() {
        image = ScreenshotStore.shared.loadImage(id: screenshotId)
        checkedDisk = true
    }
}
