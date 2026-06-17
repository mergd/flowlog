import AppKit
import ScreenCaptureKit

enum DesktopScreenshotCapture {
    static func captureFullDesktop() async -> NSImage? {
        guard Permissions.isScreenRecordingGranted() else { return nil }

        let union = await MainActor.run { desktopUnionRect() }
        guard let union, union.width > 0, union.height > 0 else { return nil }

        do {
            let cgImage = try await SCScreenshotManager.captureImage(in: union)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return await captureDisplaysComposite(fallbackUnion: union)
        }
    }

    @MainActor
    private static func desktopUnionRect() -> CGRect? {
        let screens = NSScreen.screens
        guard let first = screens.first else { return nil }
        return screens.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    private static func captureDisplaysComposite(fallbackUnion: CGRect) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard !content.displays.isEmpty else { return nil }

            var images: [(CGRect, CGImage)] = []
            for display in content.displays {
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = false
                configuration.captureResolution = .best
                let scale = CGFloat(filter.pointPixelScale)
                configuration.width = Int(filter.contentRect.width * scale)
                configuration.height = Int(filter.contentRect.height * scale)

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                images.append((filter.contentRect, image))
            }

            return await MainActor.run {
                composite(images: images, union: fallbackUnion)
            }
        } catch {
            return nil
        }
    }

    @MainActor
    private static func composite(images: [(CGRect, CGImage)], union: CGRect) -> NSImage? {
        let width = Int(union.width)
        let height = Int(union.height)
        guard width > 0, height > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        for (rect, image) in images {
            let x = Int(rect.origin.x - union.origin.x)
            let y = Int(rect.origin.y - union.origin.y)
            ctx.draw(image, in: CGRect(x: x, y: y, width: Int(rect.width), height: Int(rect.height)))
        }

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
