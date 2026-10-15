import AppKit

enum DisplayLocator {
    /// The screens the switcher should appear on: every connected display that is switched on,
    /// otherwise the one display chosen by `placement`. Never empty while at least one display is connected.
    static func screens(for placement: DisplayPlacement, pinned: Set<String>) -> [NSScreen] {
        let pinnedScreens = NSScreen.screens.filter { pinned.contains($0.stableID) }
        if !pinnedScreens.isEmpty {
            return pinnedScreens
        }

        let fallback = mouseScreen ?? NSScreen.screens.first
        let screen = switch placement {
        case .dock: dockScreen ?? NSScreen.screens.first
        case .mouse: fallback
        case .activeWindow: activeWindowScreen ?? fallback
        }
        return [screen].compactMap { $0 }
    }

    private static var mouseScreen: NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    /// The Dock is the only thing that shrinks `visibleFrame` at the bottom or sides of a display.
    /// With auto-hide on there is no such inset, and the primary display is used.
    private static var dockScreen: NSScreen? {
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        return NSScreen.screens.first { screen in
            switch orientation {
            case "left": screen.visibleFrame.minX > screen.frame.minX
            case "right": screen.visibleFrame.maxX < screen.frame.maxX
            default: screen.visibleFrame.minY > screen.frame.minY
            }
        }
    }

    private static var activeWindowScreen: NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }

        // The list is front to back, so the first normal-layer window of the frontmost app is its active one.
        for info in windows
        where info[kCGWindowOwnerPID as String] as? pid_t == pid && info[kCGWindowLayer as String] as? Int == 0 {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            return screen(containingMostOf: rect)
        }
        return nil
    }

    /// `rect` is in CoreGraphics global coordinates (origin top-left of the primary display).
    private static func screen(containingMostOf rect: CGRect) -> NSScreen? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let cocoaRect = NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        return NSScreen.screens.max { lhs, rhs in
            area(lhs.frame.intersection(cocoaRect)) < area(rhs.frame.intersection(cocoaRect))
        }
    }

    private static func area(_ rect: NSRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
