import AppKit

/// App icons for the switcher, drawn ahead of time away from the main thread.
///
/// Fetching an app's icon can take over a second when macOS has to load it afresh. Done while handling
/// ⌘⇥, that held up the keyboard event tap long enough for macOS to switch it off, and the release of ⌘
/// was lost. Icons are therefore drawn when an app is first seen, and ⌘⇥ only reads them from here.
final class AppIconCache {
    /// The largest icon the switcher draws (192 pt) at 2x.
    nonisolated private static let pixelSize = 384

    private var images: [pid_t: NSImage] = [:]
    private var loading: Set<pid_t> = []

    /// Called on the main thread when an icon is ready.
    var onLoad: (pid_t, NSImage) -> Void = { _, _ in }

    func icon(for pid: pid_t) -> NSImage? {
        images[pid]
    }

    func prepare(_ apps: [NSRunningApplication]) {
        for app in apps {
            let pid = app.processIdentifier
            guard images[pid] == nil, !loading.contains(pid) else { continue }
            loading.insert(pid)
            let path = app.bundleURL?.path
            Task { [weak self] in
                let image = await Self.draw(path)
                self?.store(image, for: pid)
            }
        }
    }

    func remove(_ pid: pid_t) {
        images[pid] = nil
        loading.remove(pid)
    }

    private func store(_ image: CGImage?, for pid: pid_t) {
        guard loading.remove(pid) != nil, let image else { return }
        let points = CGFloat(Self.pixelSize) / 2
        let icon = NSImage(cgImage: image, size: NSSize(width: points, height: points))
        images[pid] = icon
        onLoad(pid, icon)
    }

    /// Fetches the icon and draws it into a bitmap, so drawing it later costs nothing.
    @concurrent
    nonisolated private static func draw(_ path: String?) async -> CGImage? {
        let icon = path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .application)
        guard let context = CGContext(
            data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
