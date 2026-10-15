import AppKit
import Carbon.HIToolbox

/// Decides who owns ⌘⇥ right now: TaskSwitcher or the Dock.
///
/// The Dock gets ⌘⇥ back whenever TaskSwitcher could not handle it — the user switched it off,
/// Accessibility permission is missing, or Secure Keyboard Entry hides keystrokes from event taps.
/// That way ⌘⇥ never ends up doing nothing.
final class TakeoverCoordinator {
    private let tracker = AppTracker()
    private let switcher: SwitcherController
    private let interceptor: KeyboardInterceptor
    private var timer: Timer?
    private var defaultsObserver: NSObjectProtocol?

    init() {
        switcher = SwitcherController(tracker: tracker)
        interceptor = KeyboardInterceptor(handler: switcher)
    }

    func start() {
        evaluate()

        // Accessibility and Secure Input changes are not announced, so they are polled.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
    }

    /// Activates the most recently used app other than TaskSwitcher.
    func activatePreviousApp() {
        if let previous = tracker.orderedApps().first(where: { $0 != NSRunningApplication.current }) {
            AppActivator.activate(previous, restoreMinimized: false)
        }
    }

    func stop() {
        timer?.invalidate()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        switcher.cancel()
        interceptor.stop()
        NativeSwitcher.setEnabled(true)
    }

    private func evaluate() {
        let canIntercept = Preferences.isEnabled && Permissions.isAccessibilityTrusted
        if canIntercept {
            interceptor.start()
        } else {
            switcher.cancel()
            interceptor.stop()
        }

        let ownsCommandTab = interceptor.isRunning && !IsSecureEventInputEnabled()
        NativeSwitcher.setEnabled(!ownsCommandTab)
    }
}
