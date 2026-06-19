import Foundation

/// Installs the bundled `flowlog` reporting CLI into the user's PATH.
///
/// The script ships inside the app bundle (Contents/Resources/flowlog) and is
/// symlinked into `/usr/local/bin` so `flowlog` works in any terminal. That
/// directory is root-owned, so install/uninstall run through a one-time macOS
/// admin prompt via AppleScript's `with administrator privileges`. A symlink
/// (rather than a copy) means the CLI tracks app updates automatically.
enum CommandLineToolInstaller {
    static let installPath = "/usr/local/bin/flowlog"

    enum Status: Equatable {
        /// Symlink at `installPath` resolves to this app's bundled script.
        case installed
        /// Something is at `installPath` but it points elsewhere (old app
        /// location, a hand-rolled copy, or a stale version). Re-installing fixes it.
        case installedElsewhere(String)
        /// Nothing is installed yet.
        case notInstalled
        /// The script is missing from the app bundle — shouldn't happen in a
        /// release build, but guards against a broken bundle.
        case unavailable
    }

    /// URL of the `flowlog` script copied into the app bundle's Resources.
    static var bundledScriptURL: URL? {
        Bundle.main.url(forResource: "flowlog", withExtension: nil)
    }

    static func currentStatus() -> Status {
        guard let bundled = bundledScriptURL?.resolvingSymlinksInPath().path else {
            return .unavailable
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: installPath) || isSymlink(installPath) else {
            return .notInstalled
        }

        // Resolve through the symlink and compare to where our script actually lives.
        let resolved = URL(fileURLWithPath: installPath).resolvingSymlinksInPath().path
        return resolved == bundled ? .installed : .installedElsewhere(resolved)
    }

    /// Symlink the bundled script into `/usr/local/bin`. Prompts for admin once.
    static func install() throws {
        guard let src = bundledScriptURL?.path else {
            throw InstallError.scriptMissingFromBundle
        }
        // `mkdir -p` because /usr/local/bin may not exist on a fresh Apple-silicon Mac.
        let command = "mkdir -p /usr/local/bin && ln -sf \(shellQuote(src)) \(shellQuote(installPath))"
        try runPrivileged(command)
    }

    /// Remove the symlink. Prompts for admin once.
    static func uninstall() throws {
        let command = "rm -f \(shellQuote(installPath))"
        try runPrivileged(command)
    }

    enum InstallError: LocalizedError {
        case scriptMissingFromBundle
        case privilegedCommandFailed(String)

        var errorDescription: String? {
            switch self {
            case .scriptMissingFromBundle:
                return "The flowlog command-line script is missing from the app bundle."
            case .privilegedCommandFailed(let message):
                return message
            }
        }
    }

    // MARK: - Privileged execution

    /// Runs a shell command with administrator privileges via AppleScript, which
    /// surfaces the standard macOS authorization dialog. Returns normally on
    /// success; throws `privilegedCommandFailed` if the user cancels or it errors.
    private static func runPrivileged(_ shellCommand: String) throws {
        let source = "do shell script \"\(appleScriptEscape(shellCommand))\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            throw InstallError.privilegedCommandFailed("Could not construct the install command.")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            // User cancelling the password prompt is error -128; report it plainly.
            let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if number == -128 {
                throw InstallError.privilegedCommandFailed("Installation was cancelled.")
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error."
            throw InstallError.privilegedCommandFailed(message)
        }
    }

    // MARK: - Escaping helpers

    private static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    /// Wrap a path in single quotes for the shell, escaping embedded single quotes.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape a string for embedding inside an AppleScript double-quoted literal.
    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
