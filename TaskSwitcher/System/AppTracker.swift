import AppKit

/// Keeps regular (Dock-visible) apps in most-recently-used order, which is the order the switcher shows.
final class AppTracker {
    private var recent: [pid_t] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        recent = Self.initialOrder()

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let pid = Self.pid(from: note) else { return }
            MainActor.assumeIsolated { self?.moveToFront(pid) }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let pid = Self.pid(from: note) else { return }
            MainActor.assumeIsolated { self?.recent.removeAll { $0 == pid } }
        })
    }

    func orderedApps() -> [NSRunningApplication] {
        // TaskSwitcher itself is `.regular`, and so listed, only while its Settings window is open.
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        let byPID = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(recent)
        return recent.compactMap { byPID[$0] } + running.filter { !known.contains($0.processIdentifier) }
    }

    private func moveToFront(_ pid: pid_t) {
        recent.removeAll { $0 == pid }
        recent.insert(pid, at: 0)
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
