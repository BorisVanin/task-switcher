import CoreGraphics

protocol KeyboardHandler: AnyObject {
    /// Returns `true` to swallow the event.
    func handleKeyDown(_ keyCode: Int, flags: CGEventFlags, isRepeat: Bool) -> Bool
    /// Returns `true` to swallow the event.
    func handleKeyUp(_ keyCode: Int) -> Bool
    func handleFlagsChanged(_ flags: CGEventFlags)
}

/// Session-wide keyboard event tap. Requires the Accessibility permission, because it swallows events.
final class KeyboardInterceptor {
    private let handler: KeyboardHandler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    init(handler: KeyboardHandler) {
        self.handler = handler
    }

    func start() {
        guard tap == nil else { return }
        let events: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.source = nil
    }

    fileprivate func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        SwitcherTiming.eventTimestamp = event.timestamp
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            SwitcherTiming.mark("event tap was switched off by macOS (\(type == .tapDisabledByTimeout ? "timeout" : "user input")), switching it back on")
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            // Key events were missed while the tap was off; the release of ⌘ may be one of them.
            handler.handleFlagsChanged(CGEventSource.flagsState(.combinedSessionState))
            return false
        case .keyDown:
            return handler.handleKeyDown(
                Int(event.getIntegerValueField(.keyboardEventKeycode)),
                flags: event.flags,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        case .keyUp:
            return handler.handleKeyUp(Int(event.getIntegerValueField(.keyboardEventKeycode)))
        case .flagsChanged:
            handler.handleFlagsChanged(event.flags)
            return false
        default:
            return false
        }
    }
}

/// The tap's run loop source is on the main run loop, so the callback always arrives on the main thread.
nonisolated private func keyboardTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    // Safe: the callback never leaves the main thread (see above).
    nonisolated(unsafe) let interceptorPointer = refcon
    nonisolated(unsafe) let tappedEvent = event
    let swallow = MainActor.assumeIsolated {
        Unmanaged<KeyboardInterceptor>.fromOpaque(interceptorPointer).takeUnretainedValue().process(type, tappedEvent)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
