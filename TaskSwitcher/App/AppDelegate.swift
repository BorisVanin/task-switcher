import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: TakeoverCoordinator?
    private var settingsRequestObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()

        let arguments = CommandLine.arguments
        // Used by Distribution/build-dmg.sh to draw the disk image background with the app's own views.
        if let index = arguments.firstIndex(of: "--render-dmg-background"), arguments.indices.contains(index + 1) {
            let rendered = DiskImageBackgroundRenderer.render(into: URL(fileURLWithPath: arguments[index + 1]))
            exit(rendered ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        // Gives ⌘⇥ back to the Dock right away, also after a crash left it disabled for the rest of the
        // login session.
        if arguments.contains("--restore-native-switcher") {
            NativeSwitcher.setEnabled(true)
            exit(EXIT_SUCCESS)
        }

        if let running = SingleInstance.runningInstance {
            // Registering the login agent starts a login copy right away; it must leave without a trace.
            if !LoginItem.launchedAtLogin {
                SingleInstance.handOff(to: running)
            }
            exit(EXIT_SUCCESS)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.registerOnFirstLaunch()
        TerminationGuard.install { NativeSwitcher.setEnabled(true) }

        let coordinator = TakeoverCoordinator()
        coordinator.start()
        self.coordinator = coordinator

        SettingsWindowController.shared.onClose = { [weak coordinator] in
            coordinator?.activatePreviousApp()
        }
        settingsRequestObserver = SingleInstance.observeRequests {
            SettingsWindowController.shared.show()
        }

        NSApp.mainMenu = Self.makeKeyEquivalentsMenu()
        // Opened by the user: always show Settings. Started at login: only when there is nothing
        // (current) to work with yet.
        if !LoginItem.launchedAtLogin || !Preferences.hasCurrentSettings {
            SettingsWindowController.shared.show()
        }
    }

    /// An LSUIElement app never shows its menu bar, but AppKit still routes key equivalents through it.
    /// This gives the Settings window ⌘Q and ⌘W, with AppKit's handling of non-Latin keyboard layouts.
    private static func makeKeyEquivalentsMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Task Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let mainMenu = NSMenu()
        mainMenu.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu
        mainMenu.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        return mainMenu
    }

    /// Opening the app from Finder or Spotlight while it runs re-activates this copy instead of starting a new one.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
