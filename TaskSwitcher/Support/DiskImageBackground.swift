import AppKit
import SwiftUI

/// Background of the disk image window: the switcher example from Settings at the top, and an arrow between
/// the spots where Finder places the app (left) and the Applications shortcut (right).
///
/// Distribution/build-dmg.sh starts the app with `--render-dmg-background <folder>` to draw it, and places
/// the icons with AppleScript. The window size and icon positions there must match the constants below.
struct DiskImageBackground: View {
    /// Larger than the window's content area so the picture always reaches the bottom edge,
    /// whatever height the title bar has; the extra rows are cut off.
    static let size = CGSize(width: 640, height: 420)
    static let iconCenterY: CGFloat = 250
    static let appCenterX: CGFloat = 180
    static let applicationsCenterX: CGFloat = 460

    let model: SwitcherModel

    var body: some View {
        ZStack(alignment: .top) {
            DesktopPicture()
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
            // Keeps Finder's white icon labels readable on a bright desktop picture.
            Color.black.opacity(0.25)
            SwitcherView(model: model, iconSize: 48)
                .padding(.top, 28)
            Image(systemName: "arrow.right")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                .position(x: (Self.appCenterX + Self.applicationsCenterX) / 2, y: Self.iconCenterY)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
        .environment(\.switcherStaticBackground, true)
    }
}

enum DiskImageBackgroundRenderer {
    /// Writes background.png and background@2x.png into `directory`; build-dmg.sh merges them into one TIFF
    /// so Finder picks the sharp one on Retina displays.
    static func render(into directory: URL) -> Bool {
        let view = DiskImageBackground(model: .example())
        for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                  (try? png.write(to: directory.appendingPathComponent(name))) != nil else { return false }
        }
        return true
    }
}
