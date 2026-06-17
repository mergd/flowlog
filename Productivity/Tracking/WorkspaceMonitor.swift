import AppKit

final class WorkspaceMonitor {
    var onActivate: ((NSRunningApplication) -> Void)?
    var onDeactivate: ((NSRunningApplication) -> Void)?
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?
    var onScreenChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let ws = NSWorkspace.shared

        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onActivate?(app)
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onDeactivate?(app)
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onSleep?() })

        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onWake?() })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onScreenChange?() })

        if let app = ws.frontmostApplication {
            onActivate?(app)
        }
    }

    func stop() {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()
    }

    static var frontmostApplication: NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }
}
