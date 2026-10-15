import Foundation
import ServiceManagement

/// TaskSwitcher only replaces ⌘⇥ while it runs, so it has to start at login.
///
/// It is registered as a launch agent (`<bundle id>.login.plist` in `Contents/Library/LaunchAgents`, written by the
/// build from `LaunchAgents/login.plist`) rather than as `SMAppService.mainApp`, because the agent can pass
/// `--launched-at-login`. That is the only reliable way for the app to tell a login start from the user opening it.
enum LoginItem {
    static let launchArgument = "--launched-at-login"
    private static let registeredKey = "didRegisterLoginItem"

    private static var service: SMAppService {
        SMAppService.agent(plistName: "\(Bundle.main.bundleIdentifier ?? "TaskSwitcher").login.plist")
    }

    static var launchedAtLogin: Bool { CommandLine.arguments.contains(launchArgument) }

    static var isEnabled: Bool { service.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSLog("TaskSwitcher: login item change failed: \(error.localizedDescription)")
        }
    }

    /// Registers once, and only for the installed copy, so debug builds do not end up in Login Items.
    static func registerOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: registeredKey),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        setEnabled(true)
        defaults.set(true, forKey: registeredKey)
    }
}
