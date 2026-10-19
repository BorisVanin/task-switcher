import AppKit

/// Keeps regular (Dock-visible) apps in most-recently-used order, which is the order the switcher shows.
///
/// The list and the icons are kept up to date as apps launch, activate and quit, so ⌘⇥ only reads them.
/// Asking macOS for every running process takes 15–20 ms, too long to do while handling a key press.
///
/// macOS announces launches and quits through `NSWorkspace.shared.notificationCenter`; nothing is polled.
/// An app can also change its activation policy while it runs: a menu-bar app that opens a window becomes
/// regular, and one that closes its last window goes back to accessory and leaves the Dock. There is no
/// notification for that, so the policy of every running app is observed with KVO.
///
/// Every observed `NSRunningApplication` is kept alive for as long as it is observed. AppKit keeps these
/// objects in a table it walks on every process change; one that is deallocated with an observer still
/// registered leaves a dangling entry there, and the app crashes in AppKit shortly after launch.
final class AppTracker {
    let icons = AppIconCache()
    /// A regular app finished launching, or a running app became regular, so it belongs in the list.
    var onAdd: (NSRunningApplication) -> Void = { _ in }
    /// An app quit (or was killed), or stopped being regular, and is gone from the list.
    var onRemove: (pid_t) -> Void = { _ in }
    private var recent: [pid_t] = []
    private var regular: [NSRunningApplication] = []
    private var observers: [NSObjectProtocol] = []
    private var watched: [pid_t: Watched] = [:]

    private struct Watched {
        let app: NSRunningApplication
        let policy: NSKeyValueObservation
    }

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
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        regular = running.filter { $0.activationPolicy == .regular }
        icons.prepare(regular)
        observePolicy(of: running)
    }

    private func launched(_ pid: pid_t?) {
        refresh()
        if let app = regular.first(where: { $0.processIdentifier == pid }) {
            onAdd(app)
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
        stopWatching(pid)
        icons.remove(pid)
        onRemove(pid)
    }

    private func observePolicy(of running: [NSRunningApplication]) {
        let pids = Set(running.map(\.processIdentifier))
        for pid in Array(watched.keys) where !pids.contains(pid) {
            stopWatching(pid)
        }
        for app in running where watched[app.processIdentifier] == nil {
            let pid = app.processIdentifier
            let policy = app.observe(\.activationPolicy) { [weak self] _, _ in
                // KVO calls back on whichever thread applied the change.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.policyChanged(pid) }
                }
            }
            watched[pid] = Watched(app: app, policy: policy)
        }
    }

    /// The observer is removed while the app object is still alive (see the class comment).
    private func stopWatching(_ pid: pid_t) {
        guard let entry = watched.removeValue(forKey: pid) else { return }
        entry.policy.invalidate()
    }

    /// An app joined or left the Dock: it joins or leaves the list the same way.
    private func policyChanged(_ pid: pid_t) {
        let wasListed = regular.contains { $0.processIdentifier == pid }
        refresh()
        let app = regular.first { $0.processIdentifier == pid }
        if let app, !wasListed {
            onAdd(app)
        } else if app == nil, wasListed {
            icons.remove(pid)
            onRemove(pid)
        }
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
