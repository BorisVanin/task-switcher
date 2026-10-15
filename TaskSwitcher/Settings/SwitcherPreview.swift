import AppKit
import SwiftUI

/// The header art of Settings: the real switcher view with the example apps, on top of the current desktop picture.
struct SwitcherPreview: View {
    /// Room left at the top for the window's close / minimize buttons.
    private static let titleBarHeight: CGFloat = 28

    @State private var model = SwitcherModel.example()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DesktopPicture()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                SwitcherView(model: model, iconSize: iconSize(for: proxy.size))
                    .padding(.top, Self.titleBarHeight)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Fits the switcher into the art: limited by width like the real panel, and by the art's height.
    private func iconSize(for size: CGSize) -> CGFloat {
        let byWidth = SwitcherLayout.iconSize(count: model.items.count, availableWidth: size.width, maxIconSize: 96)
        // Panel height ≈ icon × 1.27 plus the name label and a little air around the panel.
        let labelHeight = SwitcherLayout.labelFontSize(for: 64) * 1.3
        let byHeight = (size.height - Self.titleBarHeight - labelHeight - 10) / 1.27
        return max(SwitcherLayout.minIconSize, min(byWidth, byHeight).rounded(.down))
    }
}

/// The current desktop picture, filling its frame; a gradient when there is none to read.
struct DesktopPicture: View {
    @State private var image = Self.load()

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [Color(red: 0.2, green: 0.25, blue: 0.55), Color(red: 0.55, green: 0.3, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private static func load() -> NSImage? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }
}
