import SwiftUI
import AppKit

struct SessionScreenshotThumb: View {
    let screenshotId: String
    var width: CGFloat = 56
    var height: CGFloat = 36
    var onTap: () -> Void

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Button(action: onTap) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("View capture")
            }
        }
        .frame(width: width, height: height)
        .onAppear(perform: load)
        .onChange(of: screenshotId) { _, _ in load() }
    }

    private func load() {
        image = ScreenshotStore.shared.loadImage(id: screenshotId)
    }
}
