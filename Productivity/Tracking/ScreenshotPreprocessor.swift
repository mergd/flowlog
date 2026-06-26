import AppKit
import CoreGraphics

enum ScreenshotPreprocessor {
    struct RedactionContext: Sendable {
        let focusedBundleId: String?
        let focusedWindowFrame: CGRect?
        let blocklistedBundleIds: [String]
        let aggressive: Bool
        let allWindows: [(bundleId: String, frame: CGRect)]
    }

    /// Off-main-actor pipeline: redact → downscale → JPEG-encode. The heavy CPU
    /// work (drawing/encoding tens of megapixels) must never run on the main
    /// thread, so this is `nonisolated` and takes only Sendable inputs — the
    /// caller hands over a `CGImage` (Sendable) instead of an `NSImage`.
    nonisolated static func redactedJPEG(
        cgImage: CGImage,
        imageSize: NSSize,
        context: RedactionContext,
        maxDimension: CGFloat = 1024,
        quality: CGFloat = 0.75
    ) -> Data? {
        let base = NSImage(cgImage: cgImage, size: imageSize)
        let redacted = redact(image: base, context: context) ?? base
        return jpegData(from: redacted, maxDimension: maxDimension, quality: quality)
    }

    static func redact(image: NSImage, context: RedactionContext) -> NSImage? {
        guard let rep = image.representations.first as? NSBitmapImageRep,
              let cgImage = rep.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(NSColor.black.cgColor)

        let screenHeight = NSScreen.main?.frame.height ?? image.size.height
        let menuBarHeight = 28 * (image.size.height / screenHeight)
        fill(ctx: ctx, imageSize: image.size, cgSize: CGSize(width: width, height: height), rect: CGRect(x: 0, y: image.size.height - menuBarHeight, width: image.size.width, height: menuBarHeight))

        let dockHeight = 70 * (image.size.height / screenHeight)
        fill(ctx: ctx, imageSize: image.size, cgSize: CGSize(width: width, height: height), rect: CGRect(x: 0, y: 0, width: image.size.width, height: dockHeight))

        for window in context.allWindows {
            if context.blocklistedBundleIds.contains(window.bundleId) {
                fill(ctx: ctx, imageSize: image.size, cgSize: CGSize(width: width, height: height), rect: window.frame)
            }
        }

        if let focused = context.focusedWindowFrame, BrowserDetector.isBrowser(context.focusedBundleId ?? "") {
            let chromeHeight: CGFloat = 120
            var chromeRect = focused
            chromeRect.size.height = min(chromeHeight, focused.height)
            fill(ctx: ctx, imageSize: image.size, cgSize: CGSize(width: width, height: height), rect: chromeRect)
        }

        if context.aggressive, let focusedFrame = context.focusedWindowFrame {
            for window in context.allWindows where window.frame != focusedFrame {
                fill(ctx: ctx, imageSize: image.size, cgSize: CGSize(width: width, height: height), rect: window.frame)
            }
        }

        guard let output = ctx.makeImage() else { return image }
        return NSImage(cgImage: output, size: image.size)
    }

    static func jpegData(from image: NSImage, maxDimension: CGFloat = 1024, quality: CGFloat = 0.75) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return jpegData(fromCGImage: cgImage, maxDimension: maxDimension, quality: quality)
    }

    /// Deterministic CoreGraphics downscale + JPEG encode. Replaces an earlier
    /// `NSImage.lockFocus()` resize, which (a) is GUI/main-thread sensitive and
    /// (b) silently rendered at the focused screen's backing scale — on a 2x
    /// display it produced output at twice `maxDimension`. This sizes by pixels.
    static func jpegData(fromCGImage cgImage: CGImage, maxDimension: CGFloat = 1024, quality: CGFloat = 0.75) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        let maxSide = CGFloat(max(width, height))
        let scale = maxSide > maxDimension ? maxDimension / maxSide : 1

        let encoded: CGImage
        if scale < 1 {
            let targetW = max(1, Int((CGFloat(width) * scale).rounded()))
            let targetH = max(1, Int((CGFloat(height) * scale).rounded()))
            guard let ctx = CGContext(
                data: nil,
                width: targetW,
                height: targetH,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.interpolationQuality = .medium
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
            guard let scaled = ctx.makeImage() else { return nil }
            encoded = scaled
        } else {
            encoded = cgImage
        }

        let rep = NSBitmapImageRep(cgImage: encoded)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    private static func fill(ctx: CGContext, imageSize: NSSize, cgSize: CGSize, rect: CGRect) {
        let scaleX = cgSize.width / imageSize.width
        let scaleY = cgSize.height / imageSize.height
        let flipped = CGRect(
            x: rect.origin.x * scaleX,
            y: (imageSize.height - rect.origin.y - rect.height) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        ctx.fill(flipped)
    }
}
