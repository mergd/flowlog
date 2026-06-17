import AppKit

enum SystemSettings {
    enum Pane {
        case accessibility
        case screenCapture
        case appleIntelligence
    }

    static func open(_ pane: Pane) {
        guard let url = url(for: pane) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func url(for pane: Pane) -> URL? {
        switch pane {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenCapture:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .appleIntelligence:
            URL(string: "x-apple.systempreferences:com.apple.AppleIntelligence-Settings.extension")
                ?? URL(string: "x-apple.systempreferences:")
        }
    }
}
