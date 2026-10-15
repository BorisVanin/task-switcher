import AppKit
import Observation
import UniformTypeIdentifiers

struct SwitcherItem: Identifiable {
    let id: pid_t
    /// `nil` for the example items shown in Settings and on the disk image.
    let app: NSRunningApplication?
    let name: String
    /// `nil` until the icon is drawn (see `AppIconCache`); the cell stays empty until then.
    var icon: NSImage?
}

/// State of one ⌘⇥ session. Shared by every panel, so all displays show the same selection.
@Observable
final class SwitcherModel {
    private(set) var items: [SwitcherItem] = []
    var selectedIndex = 0

    @ObservationIgnored var onCommit: () -> Void = {}
    /// Mouse position when the session started. Hover selects only after the mouse actually moves,
    /// otherwise a panel appearing under a resting pointer would steal the selection.
    @ObservationIgnored private var mouseOrigin = NSPoint.zero

    var selected: SwitcherItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    func load(_ apps: [NSRunningApplication], icons: AppIconCache, backward: Bool) {
        items = apps.map {
            SwitcherItem(
                id: $0.processIdentifier,
                app: $0,
                name: $0.localizedName ?? "",
                icon: icons.icon(for: $0.processIdentifier)
            )
        }
        // Like the Dock: ⌘⇥ starts on the previous app, ⌘⇧⇥ on the least recent one.
        selectedIndex = backward ? max(items.count - 1, 0) : min(1, max(items.count - 1, 0))
        mouseOrigin = NSEvent.mouseLocation
    }

    /// Apps for the pictures of the switcher (Settings, the disk image background) — the same set every
    /// time instead of whatever happens to be running. Apps that are not installed are left out.
    static func example() -> SwitcherModel {
        let bundleIDs = [
            "com.apple.finder",
            "com.apple.Safari",
            "com.apple.mail",
            "com.googlecode.iterm2",
            "com.apple.systempreferences",
            "com.apple.Photos",
        ]
        let model = SwitcherModel()
        model.items = bundleIDs
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .enumerated()
            .map { index, url in
                SwitcherItem(
                    id: pid_t(-1 - index),
                    app: nil,
                    name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                    icon: NSWorkspace.shared.icon(forFile: url.path)
                )
            }
        model.selectedIndex = 0
        return model
    }

    /// An icon that was not ready when the session started.
    func setIcon(_ icon: NSImage, for pid: pid_t) {
        if let index = items.firstIndex(where: { $0.id == pid }) {
            items[index].icon = icon
        }
    }

    func selectNext() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
    }

    func remove(_ id: pid_t) {
        items.removeAll { $0.id == id }
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
    }

    func hover(_ index: Int) {
        guard NSEvent.mouseLocation != mouseOrigin else { return }
        selectedIndex = index
    }
}
