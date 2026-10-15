import AppKit
import Carbon.HIToolbox

/// Runs a ⌘⇥ session: ⌘⇥ starts it, Tab / ⇧Tab / ` / arrows move, Q quits, H hides,
/// Esc cancels, releasing ⌘ switches (with ⌥ held, a minimized window is restored too).
final class SwitcherController: KeyboardHandler {
    /// A quick ⌘⇥ tap switches without flashing the panel, like the Dock.
    private static let showDelay: Duration = .milliseconds(100)

    private let tracker: AppTracker
    private let model = SwitcherModel()
    private var panels: [SwitcherPanel] = []
    private var showTask: Task<Void, Never>?
    private var isActive = false
    private var isVisible = false

    init(tracker: AppTracker) {
        self.tracker = tracker
        model.onCommit = { [weak self] in self?.commit(restoreMinimized: false) }
        tracker.icons.onLoad = { [weak self] pid, icon in self?.model.setIcon(icon, for: pid) }
        // The first panel takes about 40 ms more to draw than later ones; pay that before the first ⌘⇥.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.drawOnce()
        }
    }

    func handleKeyDown(_ keyCode: Int, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        guard isActive else {
            guard keyCode == kVK_Tab, flags.contains(.maskCommand), !flags.contains(.maskControl) else { return false }
            begin(backward: flags.contains(.maskShift))
            return true
        }

        switch keyCode {
        case kVK_Tab:
            flags.contains(.maskShift) ? model.selectPrevious() : model.selectNext()
        case kVK_ANSI_Grave, kVK_ISO_Section, kVK_LeftArrow:
            model.selectPrevious()
        case kVK_RightArrow:
            model.selectNext()
        case kVK_Escape, kVK_ANSI_Period:
            cancel()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            commit(restoreMinimized: flags.contains(.maskAlternate))
        case kVK_ANSI_Q where !isRepeat:
            quitSelected()
        case kVK_ANSI_H where !isRepeat:
            model.selected?.app?.hide()
        default:
            break
        }
        // While a session runs, ⌘-shortcuts must not leak to the frontmost app.
        return true
    }

    func handleKeyUp(_ keyCode: Int) -> Bool {
        isActive
    }

    func handleFlagsChanged(_ flags: CGEventFlags) {
        if isActive, !flags.contains(.maskCommand) {
            commit(restoreMinimized: flags.contains(.maskAlternate))
        }
    }

    func cancel() {
        guard isActive else { return }
        isActive = false
        hidePanels()
    }

    /// Runs inside the keyboard event tap, so it only reads what `AppTracker` already has: macOS switches
    /// a tap off when it takes too long to answer.
    private func begin(backward: Bool) {
        let pressed = ContinuousClock.now
        let apps = tracker.orderedApps()
        guard !apps.isEmpty else { return }
        isActive = true
        model.load(apps, icons: tracker.icons, backward: backward)
        showTask = Task { [weak self] in
            // Counted from the key press, so the work above happens during the pause instead of adding to it.
            try? await Task.sleep(until: pressed + Self.showDelay)
            guard !Task.isCancelled else { return }
            self?.showPanels()
        }
    }

    private func commit(restoreMinimized: Bool) {
        guard isActive else { return }
        let target = model.selected?.app
        isActive = false
        hidePanels()
        guard let target else { return }
        // After the event tap has answered: switching can wait up to half a second on a slow app.
        Task {
            AppActivator.activate(target, restoreMinimized: restoreMinimized)
        }
    }

    private func quitSelected() {
        guard let item = model.selected else { return }
        item.app?.terminate()
        model.remove(item.id)
        if model.items.isEmpty {
            cancel()
        } else if isVisible {
            showPanels()
        }
    }

    /// One panel per target display, all driven by the same model.
    private func showPanels() {
        guard isActive else { return }
        let screens = DisplayLocator.screens(for: Preferences.placement, pinned: Preferences.pinnedDisplays)
        while panels.count < screens.count {
            panels.append(SwitcherPanel(model: model))
        }
        for (panel, screen) in zip(panels, screens) {
            panel.present(on: screen, maxIconSize: Preferences.maxIconSize)
        }
        for panel in panels.dropFirst(screens.count) {
            panel.orderOut(nil)
        }
        isVisible = true
    }

    /// Draws the switcher once, invisibly, so the first ⌘⇥ is as quick as the ones after it.
    private func drawOnce() {
        guard !isActive, panels.isEmpty, let screen = NSScreen.main else { return }
        model.load(tracker.orderedApps(), icons: tracker.icons, backward: false)
        let panel = SwitcherPanel(model: model)
        panels.append(panel)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.present(on: screen, maxIconSize: Preferences.maxIconSize)
        Task {
            if !isVisible {
                panel.orderOut(nil)
            }
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
        }
    }

    private func hidePanels() {
        showTask?.cancel()
        showTask = nil
        for panel in panels {
            panel.orderOut(nil)
        }
        isVisible = false
    }
}
