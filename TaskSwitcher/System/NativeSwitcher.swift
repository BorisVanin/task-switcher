import CoreGraphics

/// The Dock's ⌘⇥ and ⌘⇧⇥ are WindowServer "symbolic hot keys". While they are disabled,
/// those keystrokes are delivered as ordinary key events, so our event tap sees them instead of the Dock.
///
/// The setting lives in the WindowServer for the current login session only: it survives a Dock restart
/// but not a logout, and nothing is written to disk.
enum NativeSwitcher {
    private static let hotKeys: [CGSSymbolicHotKey] = [.commandTab, .commandShiftTab]

    /// `true` while the Dock handles ⌘⇥.
    static var isEnabled: Bool {
        hotKeys.contains { CGSIsSymbolicHotKeyEnabled($0) }
    }

    static func setEnabled(_ enabled: Bool) {
        for hotKey in hotKeys where CGSIsSymbolicHotKeyEnabled(hotKey) != enabled {
            _ = CGSSetSymbolicHotKeyEnabled(hotKey, enabled)
        }
    }
}
