import AppKit
import CoreGraphics

enum ScreenshotPreprocessor {
    struct RedactionContext {
        let focusedBundleId: String?
        let focusedWindowFrame: CGRect?
        let blocklistedBundleIds: [String]
        let aggressive: Bool
        let allWindows: [(bundleId: String, frame: CGRect)]
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
        var target = image
        let maxSide = max(image.size.width, image.size.height)
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let resized = NSImage(size: newSize)
            resized.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
            resized.unlockFocus()
            target = resized
        }
        guard let tiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else { return nil }
        return jpeg
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
