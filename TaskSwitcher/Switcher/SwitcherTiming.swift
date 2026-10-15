import Foundation
import os

// TEMPORARY: measures where the time goes between pressing ⌘⇥ and seeing the switcher. Remove once found.
// Read with: /usr/bin/log show --last 10m --style compact --predicate 'category == "timing"'
enum SwitcherTiming {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TaskSwitcher", category: "timing")

    /// When the current key event was pressed, from the event itself (nanoseconds since startup).
    static var eventTimestamp: UInt64 = 0
    /// When ⌘⇥ was pressed for the current session.
    private static var pressed: UInt64 = 0

    static var now: UInt64 { DispatchTime.now().uptimeNanoseconds }

    static func milliseconds(from start: UInt64, to end: UInt64 = now) -> String {
        String(format: "%.1f", Double(Int64(bitPattern: end &- start)) / 1_000_000)
    }

    static func sessionStarted() {
        pressed = eventTimestamp
        log.notice("⌘⇥ ── key event reached Task Switcher \(milliseconds(from: pressed), privacy: .public) ms after the press")
    }

    /// Logs how long `step` took, and how long after the ⌘⇥ press it finished.
    @discardableResult
    static func measure<T>(_ step: String, _ body: () -> T) -> T {
        let start = now
        let result = body()
        log.notice("\(step, privacy: .public): took \(milliseconds(from: start), privacy: .public) ms, done at +\(milliseconds(from: pressed), privacy: .public) ms")
        return result
    }

    static func mark(_ step: String) {
        log.notice("\(step, privacy: .public): at +\(milliseconds(from: pressed), privacy: .public) ms")
    }
}
