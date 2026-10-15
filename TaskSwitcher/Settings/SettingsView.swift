import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(Preferences.Key.isEnabled) private var isEnabled = true
    @AppStorage(Preferences.Key.placement) private var placement = DisplayPlacement.dock
    @AppStorage(Preferences.Key.maxIconSize) private var maxIconSize = Double(SwitcherLayout.systemIconSize)

    @State private var pinned = Preferences.pinnedDisplays
    @State private var displays: [DisplayOption] = []
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var isTrusted = Permissions.isAccessibilityTrusted
    @State private var dockOwnsCommandTab = NativeSwitcher.isEnabled

    var body: some View {
        let size = SettingsWindowController.size
        VStack(spacing: 0) {
            SwitcherPreview()
                .frame(height: size.height * 0.25)
            if !isTrusted {
                accessibilityBanner
            }
            form
            Divider()
            HStack {
                Button("Exit") { NSApp.terminate(nil) }
                Text(Self.version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                ownershipControl
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
        .onAppear(perform: refreshDisplays)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshDisplays()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            isTrusted = Permissions.isAccessibilityTrusted
            dockOwnsCommandTab = NativeSwitcher.isEnabled
        }
    }

    /// "Version 1.0 (1)": marketing version and build number from Info.plist.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    /// Who handles ⌘⇥ right now, and the button that hands it over.
    /// Wanting it (`isEnabled`) is not the same as having it: access may be missing or Secure Input may be on.
    private var ownershipControl: some View {
        HStack(spacing: 10) {
            Text(ownershipStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            if isEnabled {
                Button("Restore macOS Switcher") { isEnabled = false }
            } else {
                Button("Use Task Switcher") {
                    isEnabled = true
                    if !isTrusted { Permissions.requestAccessibility() }
                }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var ownershipStatus: String {
        if !dockOwnsCommandTab { return "⌘⇥ is handled by Task Switcher" }
        if isEnabled && !isTrusted { return "Waiting for Accessibility access" }
        return "⌘⇥ is handled by macOS"
    }

    private var form: some View {
        Form {
            Section {
                ForEach(displays) { display in
                    Toggle(isOn: pinBinding(for: display.id)) {
                        Label {
                            Text(display.name)
                            Text(display.detail)
                        } icon: {
                            Image(systemName: display.symbolName)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(!display.isConnected && !pinned.contains(display.id))
                }
            } header: {
                Text("Show the switcher on")
            } footer: {
                Text("The switcher appears on every display that is switched on, all at once.")
            }

            Section("When no display is switched on") {
                Picker("Show the switcher on", selection: $placement) {
                    ForEach(DisplayPlacement.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .onChange(of: placement) { Preferences.markDisplayChoiceSaved() }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
                LabeledContent("Icon size") {
                    HStack {
                        Image(systemName: "app").imageScale(.small)
                        IconSizeSlider(value: $maxIconSize)
                        Image(systemName: "app").imageScale(.large)
                    }
                }
            }

        }
        .formStyle(.grouped)
    }

    private var accessibilityBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text("Task Switcher needs Accessibility access")
                    .font(.headline)
                Text("It is used to catch ⌘⇥ before the Dock does and to bring the app you pick to the front. Task Switcher does not read or record what you type. Until access is granted, the Dock's switcher stays in charge.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Grant Access…") { Permissions.requestAccessibility() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.orange.opacity(0.08))
    }

    private func pinBinding(for id: String) -> Binding<Bool> {
        Binding {
            pinned.contains(id)
        } set: { isOn in
            if isOn { pinned.insert(id) } else { pinned.remove(id) }
            Preferences.pinnedDisplays = pinned
        }
    }

    /// Connected displays first, then switched-on displays that are currently unplugged, so they can be switched off.
    private func refreshDisplays() {
        var names = Preferences.displayNames
        let connected = NSScreen.screens.map { screen in
            names[screen.stableID] = screen.localizedName
            let resolution = "\(Int(screen.frame.width)) × \(Int(screen.frame.height))"
            return DisplayOption(
                id: screen.stableID,
                name: screen.localizedName,
                detail: screen.isPrimary ? "Main display · \(resolution)" : resolution,
                symbolName: CGDisplayIsBuiltin(screen.displayID) != 0 ? "laptopcomputer" : "display",
                isConnected: true
            )
        }
        Preferences.displayNames = names

        let connectedIDs = Set(connected.map(\.id))
        let disconnected = pinned.subtracting(connectedIDs).sorted().map { id in
            DisplayOption(
                id: id,
                name: names[id] ?? "Unknown display",
                detail: "Not connected",
                symbolName: "display.trianglebadge.exclamationmark",
                isConnected: false
            )
        }
        displays = connected + disconnected
    }
}

private struct DisplayOption: Identifiable {
    let id: String
    let name: String
    let detail: String
    let symbolName: String
    let isConnected: Bool
}
