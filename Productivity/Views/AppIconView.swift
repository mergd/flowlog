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

    private var glyph: String {
        let source = domain ?? siteLabel
        return String(source.prefix(1)).uppercased()
    }

    private var tint: Color {
        let hash = abs((domain ?? siteLabel).hashValue)
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
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(tint.opacity(0.18))
            Text(glyph)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}
