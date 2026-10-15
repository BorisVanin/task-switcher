import Foundation

enum Preferences {
    enum Key {
        static let isEnabled = "replaceDockSwitcher"
        static let placement = "displayPlacement"
        static let pinnedDisplays = "pinnedDisplays"
        static let displayNames = "knownDisplayNames"
        static let maxIconSize = "maxIconSize"
        static let didRequestAccessibility = "didRequestAccessibility"
        static let settingsVersion = "settingsVersion"
    }

    /// Bump when the meaning or format of the saved display choice changes:
    /// the next start, even at login, opens Settings so the user can check the choice again.
    static let currentSettingsVersion = 1

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.isEnabled: true,
            Key.placement: DisplayPlacement.dock.rawValue,
            Key.maxIconSize: Double(SwitcherLayout.systemIconSize),
        ])
    }

    private static var defaults: UserDefaults { .standard }

    static var isEnabled: Bool { defaults.bool(forKey: Key.isEnabled) }

    /// The user has made a display choice in Settings with the current settings version.
    /// Without it, a start at login opens Settings as well.
    static var hasCurrentSettings: Bool {
        defaults.integer(forKey: Key.settingsVersion) == currentSettingsVersion
    }

    /// Called whenever the user switches a display on or off or picks the fallback placement.
    static func markDisplayChoiceSaved() {
        defaults.set(currentSettingsVersion, forKey: Key.settingsVersion)
    }

    static var placement: DisplayPlacement {
        defaults.string(forKey: Key.placement).flatMap(DisplayPlacement.init(rawValue:)) ?? .dock
    }

    static var maxIconSize: CGFloat { CGFloat(defaults.double(forKey: Key.maxIconSize)) }

    /// Stable display IDs (see `NSScreen.stableID`).
    static var pinnedDisplays: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.pinnedDisplays) ?? []) }
        set {
            defaults.set(newValue.sorted(), forKey: Key.pinnedDisplays)
            markDisplayChoiceSaved()
        }
    }

    /// Last known name per stable display ID, so a pinned but disconnected display keeps its name in Settings.
    static var displayNames: [String: String] {
        get { defaults.dictionary(forKey: Key.displayNames) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.displayNames) }
    }
}
