import AppKit

/// Only one TaskSwitcher may own ⌘⇥. Starting the app again shows Settings of the copy that is already running.
enum SingleInstance {
    private static let showSettingsRequest =
        Notification.Name("\(Bundle.main.bundleIdentifier ?? "TaskSwitcher").showSettings")

    static var runningInstance: NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0 != NSRunningApplication.current }
    }

    /// Asks the running copy to show Settings; the caller should then exit.
    static func handOff(to running: NSRunningApplication) {
        // This launch is the active app; let the running copy bring its window to the front.
        NSApp.yieldActivation(to: running)
        DistributedNotificationCenter.default().postNotificationName(
            showSettingsRequest, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    static func observeRequests(_ handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: showSettingsRequest, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}
