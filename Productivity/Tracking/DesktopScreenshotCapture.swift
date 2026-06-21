import AppKit
import ScreenCaptureKit

enum DesktopScreenshotCapture {
    static func captureFullDesktop() async -> NSImage? {
        guard Permissions.isScreenRecordingGranted() else { return nil }

        let union = await MainActor.run { desktopUnionRect() }
        guard let union, union.width > 0, union.height > 0 else { return nil }

        if let cgImage = await captureImage(in: union) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return await captureDisplaysComposite(fallbackUnion: union)
    }

    /// Capture a screen rect, tolerating ScreenCaptureKit's transient
    /// `(nil image, nil error)` callback.
    ///
    /// We deliberately use the completion-handler API instead of the bridged
    /// `async` form. The `async` form installs a compiler-generated *checked*
    /// completion thunk that promises a non-nil `CGImage` or a thrown error; when
    /// ScreenCaptureKit fires the callback with BOTH nil (which happens
    /// transiently — screen locked, display asleep/reconfiguring, screensaver,
    /// fast user-switching) that thunk satisfies neither contract and traps
    /// (EXC_BREAKPOINT / SIGTRAP), crashing the app. Handling the callback
    /// ourselves lets us treat that case as a plain failure.
    private static func captureImage(in rect: CGRect) async -> CGImage? {
        await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(in: rect) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async -> CGImage? {
        await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                continuation.resume(returning: image)
            }
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

                guard let image = await captureImage(filter: filter, configuration: configuration) else {
                    continue
                }
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
