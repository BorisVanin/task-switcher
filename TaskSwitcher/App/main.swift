import AppKit

// Plain AppKit entry point: no SwiftUI scenes, so no menu bar icon and no Dock icon (LSUIElement).
// The only UI besides the switcher itself is the Settings window.
private let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
