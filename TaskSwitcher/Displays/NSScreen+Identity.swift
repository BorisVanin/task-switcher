import AppKit
import ColorSync

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? kCGNullDirectDisplay
    }

    /// Identifies the same physical monitor across reboots, re-plugging and port changes,
    /// unlike `CGDirectDisplayID`, which macOS may reassign. This is what pinned displays are saved as.
    var stableID: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) else { return String(displayID) }
        return string as String
    }

    var isPrimary: Bool { self == NSScreen.screens.first }
}
