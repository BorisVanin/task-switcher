import AppKit
import ApplicationServices

enum AppActivator {
    /// Brings `app` to the front the way the Dock switcher does — also when it has no open windows,
    /// in which case only its menu bar becomes active.
    /// - Parameter restoreMinimized: ⌥ was held on release — also restore a minimized window.
    static func activate(_ app: NSRunningApplication, restoreMinimized: Bool) {
        if app == NSRunningApplication.current {
            // TaskSwitcher itself is in the list only while Settings is open.
            SettingsWindowController.shared.show()
            return
        }
        if app.isHidden {
            app.unhide()
        }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Keep a hung app from freezing the switcher (the default AX timeout is 6 s).
        AXUIElementSetMessagingTimeout(element, 0.5)

        if restoreMinimized {
            unminimizeFirstWindow(of: element)
        }

        // A background app cannot reliably activate others since macOS 14 (cooperative activation).
        // Setting AXFrontmost works for apps with windows on this Space, but silently does nothing for an
        // app whose windows are elsewhere. Accessibility lists only windows on the current Space (and
        // minimized ones), so a window on another Space, such as a full-screen one, is found through the
        // WindowServer. Opening the app through Launch Services, as clicking its Dock icon does, switches to
        // that Space; the SkyLight front-process call only activates the menu bar there.
        // An app without any window goes through the WindowServer call the Dock itself uses.
        let windows = windows(of: element)
        if windows.contains(where: { !isMinimized($0) }) {
            if AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, true as CFBoolean) == .success {
                return
            }
        } else if windowOnOtherSpace(of: app.processIdentifier, excluding: windows.filter(isMinimized)) != nil,
                  let url = app.bundleURL {
            openApplication(at: url)
            return
        } else if setFrontProcess(app.processIdentifier, window: 0, mode: [.noWindows, .userGenerated]) {
            return
        }
        app.activate(options: [.activateAllWindows])
    }

    private static func openApplication(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        Task {
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    /// The app's frontmost normal window on another Space (a full-screen window has a Space of its own),
    /// or nil when it has none. Minimized windows are skipped: ⌘⇥ leaves them in the Dock.
    private static func windowOnOtherSpace(of pid: pid_t, excluding minimized: [AXUIElement]) -> CGWindowID? {
        let minimizedIDs = Set(minimized.compactMap { window -> CGWindowID? in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(window, &id) == .success ? id : nil
        })
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        // Front to back. Apps keep invisible and tiny helper windows in layer 0 too.
        return list.lazy.compactMap { info -> CGWindowID? in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width >= 100, bounds.height >= 100,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  !minimizedIDs.contains(id) else { return nil }
            return id
        }.first
    }

    private static func unminimizeFirstWindow(of element: AXUIElement) {
        if let window = windows(of: element).first(where: isMinimized) {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFBoolean)
        }
    }

    /// Real windows only. Finder lists its desktop here too (role AXScrollArea); counting it would send
    /// Finder without open windows down the AXFrontmost path, which silently does nothing for it.
    private static func windows(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement] ?? []).filter { window in
            var role: CFTypeRef?
            return AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success
                && role as? String == kAXWindowRole
        }
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success
            && value as? Bool == true
    }

    /// Makes TaskSwitcher itself the active app with `window` in front, the way the Dock activates apps.
    static func bringToFront(_ window: NSWindow) {
        _ = setFrontProcess(getpid(), window: CGWindowID(window.windowNumber), mode: .userGenerated)
    }

    // MARK: - SkyLight

    private static let setFrontProcessFunction: SLPSSetFrontProcessWithOptionsFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "_SLPSSetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(symbol, to: SLPSSetFrontProcessWithOptionsFunction.self)
    }()

    private static func setFrontProcess(_ pid: pid_t, window: CGWindowID, mode: SLPSMode) -> Bool {
        guard let setFrontProcessFunction else { return false }
        var psn = ProcessSerialNumber()
        guard TSGetProcessForPID(pid, &psn) == noErr else { return false }
        return setFrontProcessFunction(&psn, window, mode) == .success
    }
}
