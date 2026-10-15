import AppKit
import SwiftUI

/// Borderless, non-activating panel: it shows above everything (full-screen apps included)
/// on every Space without taking focus away from the app the user is in.
final class SwitcherPanel: NSPanel {
    private let model: SwitcherModel
    private let hostingView: NSHostingView<SwitcherView>

    init(model: SwitcherModel) {
        self.model = model
        hostingView = NSHostingView(rootView: SwitcherView(model: model, iconSize: SwitcherLayout.systemIconSize))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)

        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Sizes icons for this display's width, so a panel on a small display shrinks
    /// while one on a large display keeps full-size icons.
    func present(on screen: NSScreen, maxIconSize: CGFloat) {
        let iconSize = SwitcherLayout.iconSize(
            count: model.items.count,
            availableWidth: screen.visibleFrame.width,
            maxIconSize: maxIconSize
        )
        hostingView.rootView = SwitcherView(model: model, iconSize: iconSize)
        let size = hostingView.fittingSize
        let frame = screen.frame
        setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height),
            display: true
        )
        orderFrontRegardless()
    }
}
