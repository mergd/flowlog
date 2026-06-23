import Foundation
import Sparkle

@MainActor
enum SparkleUpdater {
    private static let controller = SPUStandardUpdaterController(
        startingUpdater: shouldStartAutomatically,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    static var updater: SPUUpdater { controller.updater }

    private static var shouldStartAutomatically: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
