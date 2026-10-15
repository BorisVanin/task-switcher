import AppKit
import SwiftUI

/// AppKit slider, because SwiftUI's `Slider` cannot draw a single tick mark.
/// The range is centred on the system icon size, so the one tick (always drawn in the middle) marks it,
/// and values near it snap onto it.
struct IconSizeSlider: NSViewRepresentable {
    @Binding var value: Double

    func makeNSView(context: Context) -> NSSlider {
        let range = SwitcherLayout.iconSizeRange
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.numberOfTickMarks = 1
        slider.tickMarkPosition = .below
        slider.isContinuous = true
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        if slider.doubleValue != value {
            slider.doubleValue = value
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc func valueChanged(_ slider: NSSlider) {
            let snapped = SwitcherLayout.snappedIconSize(slider.doubleValue)
            slider.doubleValue = snapped
            value.wrappedValue = snapped
        }
    }
}
