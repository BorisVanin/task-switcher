import AppKit
import ApplicationServices

enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// The system shows its Accessibility prompt only once per app. The first request shows it;
    /// later requests open Privacy & Security ▸ Accessibility, where access can still be turned on.
    static func requestAccessibility() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Preferences.Key.didRequestAccessibility) {
            openAccessibilitySettings()
        } else {
            defaults.set(true, forKey: Preferences.Key.didRequestAccessibility)
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
