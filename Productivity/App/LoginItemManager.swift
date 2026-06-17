import Foundation
import ServiceManagement

@MainActor
enum LoginItemManager {
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            AppSettings.shared.loginItemEnabled = isRegistered
        } catch {
            AppSettings.shared.loginItemEnabled = isRegistered
        }
    }

    static func syncWithPreference() {
        let preferred = AppSettings.shared.loginItemEnabled
        guard preferred != isRegistered else { return }
        setEnabled(preferred)
    }
}
