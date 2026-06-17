import AppKit

final class WorkspaceMonitor {
    var onActivate: ((NSRunningApplication) -> Void)?
    var onDeactivate: ((NSRunningApplication) -> Void)?
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?
    var onScreenChange: (() -> Void)?

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func start() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let ws = NSWorkspace.shared

        observers.append((workspaceCenter, workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onActivate?(app)
        }))

        observers.append((workspaceCenter, workspaceCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onDeactivate?(app)
        }))

        observers.append((workspaceCenter, workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onSleep?() }))

        observers.append((workspaceCenter, workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onWake?() }))

        let defaultCenter = NotificationCenter.default
        observers.append((defaultCenter, defaultCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onScreenChange?() }))

        if let app = ws.frontmostApplication {
            onActivate?(app)
        }
    }

    func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
    }

    static var frontmostApplication: NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }
}
