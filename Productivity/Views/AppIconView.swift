import AppKit
import SwiftUI

enum AppIconLoader {
    static func image(for bundleId: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }
}

struct AppIconView: View {
    let bundleId: String
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let image = AppIconLoader.image(for: bundleId) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

struct SiteIconView: View {
    let siteLabel: String
    let domain: String?
    var size: CGFloat = 22
    /// When set, overlays the browser's app icon as a small corner badge.
    var browserBundleId: String? = nil

    @State private var favicon: NSImage?

    /// The domain we actually use for the favicon — the parsed one, or one inferred
    /// from a recognized site label when the live URL wasn't readable.
    private var resolvedDomain: String? {
        SiteCatalog.canonicalDomain(domain) ?? SiteCatalog.inferredDomain(forLabel: siteLabel)
    }

    private var glyph: String {
        let source = resolvedDomain ?? siteLabel
        return String(source.prefix(1)).uppercased()
    }

    private var tint: Color {
        let hash = abs((resolvedDomain ?? siteLabel).hashValue)
        let hues: [Color] = [
            Color(red: 0.35, green: 0.55, blue: 0.95),
            Color(red: 0.55, green: 0.42, blue: 0.92),
            Color(red: 0.28, green: 0.72, blue: 0.58),
            Color(red: 0.92, green: 0.48, blue: 0.38),
        ]
        return hues[hash % hues.count]
    }

    var body: some View {
        ZStack {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.12)
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(tint.opacity(0.18))
                Text(glyph)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let browserBundleId, let image = AppIconLoader.image(for: browserBundleId) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.6, height: size * 0.6)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                            .strokeBorder(DashboardTheme.surface, lineWidth: size * 0.07)
                    }
                    .offset(x: size * 0.22, y: size * 0.22)
            }
        }
        .task(id: resolvedDomain) {
            favicon = nil
            guard let resolvedDomain else { return }
            if let data = await FaviconStore.shared.favicon(for: resolvedDomain) {
                favicon = NSImage(data: data)
            }
        }
    }
}
