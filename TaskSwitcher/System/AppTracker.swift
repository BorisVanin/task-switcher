import AppKit

/// Keeps regular (Dock-visible) apps in most-recently-used order, which is the order the switcher shows.
///
/// The list and the icons are kept up to date as apps launch, activate and quit, so ⌘⇥ only reads them.
/// Asking macOS for every running process takes 15–20 ms, too long to do while handling a key press.
///
/// macOS announces launches and quits through `NSWorkspace.shared.notificationCenter`; nothing is polled.
final class AppTracker {
    let icons = AppIconCache()
    /// A regular app finished launching, so it belongs in the list.
    var onLaunch: (NSRunningApplication) -> Void = { _ in }
    /// An app quit (or was killed) and is gone from the list.
    var onTerminate: (pid_t) -> Void = { _ in }
    private var recent: [pid_t] = []
    private var regular: [NSRunningApplication] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        recent = Self.initialOrder()
        refresh()

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = Self.pid(from: note)
            MainActor.assumeIsolated { self?.launched(pid) }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let pid = Self.pid(from: note) else { return }
            MainActor.assumeIsolated { self?.activated(pid) }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let pid = Self.pid(from: note) else { return }
            MainActor.assumeIsolated { self?.terminated(pid) }
        })
    }

    func orderedApps() -> [NSRunningApplication] {
        let running = regular.filter { !$0.isTerminated }
        let byPID = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(recent)
        return recent.compactMap { byPID[$0] } + running.filter { !known.contains($0.processIdentifier) }
    }

    /// TaskSwitcher itself is `.regular`, and so listed, only while its Settings window is open.
    private func refresh() {
        regular = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        icons.prepare(regular)
    }

    private func launched(_ pid: pid_t?) {
        refresh()
        if let app = regular.first(where: { $0.processIdentifier == pid }) {
            onLaunch(app)
        }
    }

    private func activated(_ pid: pid_t) {
        recent.removeAll { $0 == pid }
        recent.insert(pid, at: 0)
        // An app can become regular after launch (TaskSwitcher itself does when Settings opens).
        if !regular.contains(where: { $0.processIdentifier == pid }) {
            refresh()
        }
    }

    private func terminated(_ pid: pid_t) {
        recent.removeAll { $0 == pid }
        regular.removeAll { $0.processIdentifier == pid }
        icons.remove(pid)
        onTerminate(pid)
    }

    nonisolated private static func pid(from note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    /// Best guess at launch: the frontmost app, then apps in front-to-back order of their windows.
    private static func initialOrder() -> [pid_t] {
        var order: [pid_t] = []
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            order.append(front)
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in windows where info[kCGWindowLayer as String] as? Int == 0 {
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t, !order.contains(pid) {
                order.append(pid)
            }
        }
        return order
    }
}
