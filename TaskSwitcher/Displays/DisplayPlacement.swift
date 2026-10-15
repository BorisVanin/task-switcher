import Foundation

/// Where the switcher appears when no display is switched on in Settings.
enum DisplayPlacement: String, CaseIterable, Identifiable {
    /// What the Dock does: the display that currently has the Dock.
    case dock
    /// The display under the mouse pointer.
    case mouse
    /// The display with the frontmost window.
    case activeWindow

    var id: Self { self }

    var title: String {
        switch self {
        case .dock: "Display with the Dock (macOS default)"
        case .mouse: "Display with the mouse pointer"
        case .activeWindow: "Display with the active window"
        }
    }
}
