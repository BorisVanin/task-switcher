import AppKit
import SwiftUI

/// The Settings window is owned by AppKit rather than a SwiftUI `Settings` scene, so that it can be opened
/// from anywhere (every launch, a second launch, reopening the app) and keep a fixed 3:4 shape.
///
/// While it is open TaskSwitcher is a regular app — Dock icon, menu bar, and listed in ⌘⇥ like any other
/// app with a window. Closing it turns TaskSwitcher back into a background agent.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    /// Width : height = 3 : 4. The content reaches under the transparent title bar, so this is the whole window.
    static let size = NSSize(width: 480, height: 640)

    /// Called after the window closed and TaskSwitcher went back to the background,
    /// to hand focus to the app the user was in before.
    var onClose: () -> Void = {}

    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // Opened from the background (the switcher, a second launch), the request above can be refused
        // under cooperative activation, leaving the window behind the active app's windows.
        AppActivator.bringToFront(window)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onClose()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Task Switcher Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self

        let hostingController = NSHostingController(rootView: SettingsView())
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.setContentSize(Self.size)
        window.center()
        return window
    }
}
