import Foundation

/// Runs cleanup when the app is killed with a signal (`kill`, `pkill`, launchd, the installer),
/// so the Dock's ⌘⇥ is restored even when `applicationWillTerminate` is never called.
enum TerminationGuard {
    private static var sources: [DispatchSourceSignal] = []

    static func install(_ cleanup: @escaping @MainActor () -> Void) {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { cleanup() }
                exit(EXIT_SUCCESS)
            }
            source.resume()
            sources.append(source)
        }
    }
}
