import AppKit
import SwiftUI

/// Proportions of the system switcher (macOS 26), as fractions of the icon size.
/// App icon artwork has its own transparent margin, so icons sit almost edge to edge.
enum SwitcherLayout {
    /// Icon size the system switcher uses. The icon size slider is centred on it and snaps to it.
    static let systemIconSize: CGFloat = 128
    static let iconSizeRange: ClosedRange<Double> = 64...192
    static let minIconSize: CGFloat = 24

    static let cellSpacing: CGFloat = 0.05
    static let outerPadding: CGFloat = 0.17
    static let bottomPadding: CGFloat = 0.10
    /// The selection tile sits close around the icon artwork, with corners concentric with the icon's.
    /// Measured from a screenshot of the system switcher.
    static let highlightSize: CGFloat = 0.925
    static let highlightCornerRadius: CGFloat = 0.245
    static let panelCornerRadius: CGFloat = 0.38
    /// Share of the display width the panel may take before icons shrink.
    static let maxWidthFraction: CGFloat = 0.92

    static func iconSize(count: Int, availableWidth: CGFloat, maxIconSize: CGFloat) -> CGFloat {
        let n = CGFloat(max(count, 1))
        let widthPerIcon = n + (n - 1) * cellSpacing + 2 * outerPadding
        let fitting = availableWidth * maxWidthFraction / widthPerIcon
        return max(minIconSize, min(maxIconSize, fitting.rounded(.down)))
    }

    /// The panel is a rounded rectangle, not a capsule.
    static func panelCornerRadius(for iconSize: CGFloat) -> CGFloat {
        iconSize * panelCornerRadius
    }

    static func labelFontSize(for iconSize: CGFloat) -> CGFloat {
        min(15, max(11, iconSize * 0.105))
    }

    /// Rounds slider values to steps of 8 and pulls values close to the system size onto it.
    static func snappedIconSize(_ value: Double) -> Double {
        let system = Double(systemIconSize)
        let snapped = abs(value - system) < 6 ? system : (value / 8).rounded() * 8
        return min(iconSizeRange.upperBound, max(iconSizeRange.lowerBound, snapped))
    }
}

struct SwitcherView: View {
    let model: SwitcherModel
    let iconSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: iconSize * SwitcherLayout.cellSpacing) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                cell(item, isSelected: index == model.selectedIndex)
                    .onHover { inside in
                        if inside { model.hover(index) }
                    }
                    .onTapGesture {
                        model.selectedIndex = index
                        model.onCommit()
                    }
            }
        }
        .padding([.top, .horizontal], iconSize * SwitcherLayout.outerPadding)
        .padding(.bottom, iconSize * SwitcherLayout.bottomPadding)
        .background { PanelBackground(cornerRadius: SwitcherLayout.panelCornerRadius(for: iconSize)) }
        .fixedSize()
    }

    private func cell(_ item: SwitcherItem, isSelected: Bool) -> some View {
        VStack(spacing: iconSize * 0.01) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Color.clear
                }
            }
                .frame(width: iconSize, height: iconSize)
                .background {
                    if isSelected {
                        SelectionTile(size: iconSize)
                    }
                }
            // Like the system, only the selected app's name is shown, under the tile.
            // The hidden labels keep every cell the same height.
            Text(item.name)
                .font(.system(size: SwitcherLayout.labelFontSize(for: iconSize), weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: iconSize * (1 + SwitcherLayout.cellSpacing))
                .opacity(isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The system's selection: a solid tile behind the icon. In the dark theme it is a lighter grey with a barely
/// visible rim; in the light theme a darker grey with no rim.
/// Drawn rather than made of real glass: glass on top of the glass panel renders inconsistently.
private struct SelectionTile: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.switcherSymmetricSelection) private var symmetric

    /// The tile must leave a whole number of points on each side of the icon frame. With a half-point gap
    /// (a 62 pt tile on a 67 pt icon, say) a 1x display has to put the extra pixel on one side.
    private var tileSize: CGFloat {
        let exact = size * SwitcherLayout.highlightSize
        return symmetric ? size - 2 * ((size - exact) / 2).rounded() : exact
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * SwitcherLayout.highlightCornerRadius, style: .continuous)
        Group {
            if colorScheme == .light {
                shape.fill(.black.opacity(0.21))
            } else {
                shape
                    .fill(.white.opacity(0.22))
                    .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
            }
        }
        .frame(width: tileSize, height: tileSize)
    }
}

extension EnvironmentValues {
    /// Draw the panel without system materials. Glass and behind-window blur only exist in a live window,
    /// so a picture rendered with `ImageRenderer` (the disk image background) needs a plain look-alike.
    @Entry var switcherStaticBackground = false
    /// Keep the selection tile exactly centred on its icon. Used by the preview at the top of Settings.
    @Entry var switcherSymmetricSelection = false
}

/// Rounded rectangle like the system panel: Liquid Glass on macOS 26 and later, a HUD blur with a rim before that.
private struct PanelBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.switcherStaticBackground) private var isStatic

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if isStatic {
            shape
                .fill(Color(white: 0.1).opacity(0.55))
                .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            // Regular glass is nearly opaque white in the light theme; the system panel lets far more through.
            Color.clear.glassEffect(.clear, in: shape)
        } else {
            VisualEffectBackground()
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
