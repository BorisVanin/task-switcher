# TaskSwitcher — Architecture

TaskSwitcher re-implements the macOS ⌘⇥ app switcher and fixes its multi-monitor behaviour. The Dock always
shows the switcher on the display that has the Dock. TaskSwitcher lets the user choose where it shows,
including **pinning it to one or several selected monitors at once**.

- Platform: macOS 14 Sonoma or later. Swift 6 with SwiftUI and AppKit.
- Distribution: **Developer ID**, notarized, delivered as a `.dmg`: drag the app onto Applications. This is not a Mac App Store app (see [Signing and distribution](#signing-and-distribution)).
- Runs as a menu-bar agent (`LSUIElement`) with no Dock icon.

---

## 1. How the system switcher works, and what limits a replacement

| Fact | Consequence |
|---|---|
| ⌘⇥ belongs to the **Dock** process. The WindowServer delivers it as a *symbolic hot key*, before any app or event tap sees it. | A normal hot key or event tap never receives ⌘⇥ while the Dock still owns it. The Dock's hot key has to be switched off first ([§3](#3-replacing-the-dock-switcher-the-trick)). |
| Apple has no public API to change the Dock switcher (its position, its look, or which display it uses). | The whole switcher is re-implemented: key handling, app list, UI, and activation. |
| Since macOS 14, app activation is *cooperative*: a background app cannot reliably bring another app to the front with `NSRunningApplication.activate`. | Activation goes through Accessibility (`AXFrontmost`). |
| Swallowing keystrokes system-wide needs the **Accessibility** permission. | The Settings window explains why and offers **Grant Access…**. Until it is granted, the Dock keeps ⌘⇥. |
| The App Sandbox blocks event taps that change events, Accessibility control of other apps, and private WindowServer calls. | The app cannot be sandboxed, so it cannot ship on the Mac App Store. Developer ID is the only option. |

---

## 2. Components

```
┌────────────────────── Task Switcher.app (LSUIElement, not sandboxed, hardened runtime) ────────────────────────┐
│                                                                                                                │
│  main.swift (AppKit, no menu bar icon) ── SettingsWindowController → SettingsView               │
│        │                                                                                                       │
│  AppDelegate ── maintenance flag (--restore-native-switcher), LoginItem, TerminationGuard                       │
│        │                                                                                                       │
│  TakeoverCoordinator ── decides every second / on preference change who owns ⌘⇥: us or the Dock               │
│        │        ├─ Permissions (AXIsProcessTrusted)                                                            │
│        │        ├─ IsSecureEventInputEnabled (password fields)                                                 │
│        │        ├─ NativeSwitcher (CGSSetSymbolicHotKeyEnabled — private)                                      │
│        │        └─ KeyboardInterceptor (CGEventTap, session level)                                             │
│        │                         │ keyDown / keyUp / flagsChanged                                              │
│        ▼                         ▼                                                                             │
│  SwitcherController (session state machine) ── AppTracker (MRU order via NSWorkspace notifications)            │
│        │                     ├─ DisplayLocator (placement → [NSScreen], stable display UUIDs)                  │
│        │                     ├─ SwitcherPanel × N (one non-activating NSPanel per target display)              │
│        │                     │      └─ SwitcherView (SwiftUI; shared @Observable SwitcherModel)                │
│        │                     └─ AppActivator (AX frontmost / unhide / un-minimize)                             │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| File | Responsibility |
|---|---|
| `App/main.swift` | AppKit entry point. There is no SwiftUI scene and no menu bar icon. |
| `App/AppDelegate.swift` | Startup. Handles `--restore-native-switcher` and `--render-dmg-background`. Registers the login item. |
| `App/TakeoverCoordinator.swift` | The single place that turns the Dock's ⌘⇥ off or back on. Fails safe: if TaskSwitcher cannot handle ⌘⇥, the Dock gets it back. |
| `App/TerminationGuard.swift` | Restores the Dock's ⌘⇥ on SIGTERM, SIGINT and SIGHUP. |
| `System/NativeSwitcher.swift` + `Support/TaskSwitcher-Bridging-Header.h` | Private symbolic-hot-key API. |
| `System/KeyboardInterceptor.swift` | `CGEventTap`. Re-enables itself if the system disables it on timeout. |
| `System/AppTracker.swift` | Most-recently-used order of regular apps. The list is kept current as apps launch, activate, quit and change their activation policy (a menu-bar app that opens or closes its window; observed with KVO, as macOS sends no notification for it), so ⌘⇥ never asks macOS for every process (15–20 ms). |
| `System/AppIconCache.swift` | App icons, fetched and drawn into bitmaps on a background thread when an app is first seen. Fetching an icon can take over a second when macOS loads it afresh; a cell stays empty until its icon is ready. |
| `System/AppActivator.swift` | Brings the chosen app forward, including apps without open windows. With ⌥ held, also restores a minimized window. |
| `System/Permissions.swift`, `System/LoginItem.swift` | Accessibility prompt and status. Login item: a launch agent registered through `SMAppService`, which passes `--launched-at-login`. |
| `Displays/*` | Placement modes, stable display identity, choosing the screen. |
| `Switcher/*` | Session logic, panel, SwiftUI view, layout maths. |
| `Settings/*` | `UserDefaults` keys and the Settings UI. |

### 2.1 Session behaviour (matches the Dock switcher)

| Input | Action |
|---|---|
| ⌘⇥ / ⌘⇧⇥ | Start a session. The previous app is selected (⌘⇧⇥ selects the least recent). A quick tap switches without showing the panel: it appears 100 ms after the key press. The panel is drawn once, invisibly, a second after start, so the first ⌘⇥ is as quick as later ones. |
| Tab / ⇧Tab, ← →, `` ` `` (or the ISO key above Tab) | Move the selection. |
| Release ⌘ | Activate the selected app. Holding ⌥ also restores a minimized window. |
| Return | Activate now. |
| Q / H | Quit or hide the selected app. The list updates in place. |
| Esc, ⌘. | Cancel. |
| Mouse hover / click | Select / activate. Hover counts only after the pointer moves, so a panel that opens under a resting pointer does not change the selection. |

While a session is running, every key event is swallowed so that ⌘-shortcuts do not reach the frontmost app.
`flagsChanged` events always pass through.

### 2.2 Multi-monitor placement (the fix)

Settings lists every display with its own on/off switch.

- **One or more connected displays switched on:** the switcher appears on **all of them at once**. Each display
  gets its own `SwitcherPanel`. All panels share one `SwitcherModel`, so selection and hover stay in sync.
- **None switched on, or none of the switched-on displays connected:** the switcher appears on one display,
  chosen by `DisplayPlacement`:

| Mode | Screen |
|---|---|
| `dock` (default, same as macOS) | The display whose `visibleFrame` is inset on the Dock's edge (orientation read from the `com.apple.dock` defaults). If the Dock auto-hides, the primary display. |
| `mouse` | The display under `NSEvent.mouseLocation`. |
| `activeWindow` | The display that holds most of the frontmost app's top window (from `CGWindowListCopyWindowInfo`, converted from CG top-left to Cocoa bottom-left coordinates). |

### 2.3 Settings window and app lifecycle

- **Settings window:** an AppKit `NSWindow` (`SettingsWindowController`), not a SwiftUI `Settings` scene, so it can be opened from
  anywhere. It is fixed at 3:4 (480 × 640 pt). Its content reaches under the transparent title bar.
- **Top 25% of the window:** `SwitcherPreview`. This is the real `SwitcherView`, filled with a fixed set of example apps (`SwitcherModel.example()`: Finder, Safari, Mail, iTerm2, System Settings, Photos; any that are not installed are left out),
  on top of the current desktop picture
  ([`desktopImageURL(for:)`](https://developer.apple.com/documentation/appkit/nsworkspace/desktopimageurl(for:))).
  Below it come the display switches, the fallback placement, general options and permissions.
- **When Settings opens:** whenever the user starts the app. There is no menu bar icon, so starting the app is how you reach Settings. At login, Settings opens only if no display choice has been saved yet, or if it was saved with an older `settingsVersion` (`Preferences.currentSettingsVersion`, bumped whenever the meaning or format of the saved choice changes). A choice counts as saved once the user switches a display on or off or picks a fallback placement.
- **Detecting a login start:** macOS has no API for this. The login item is therefore a launch agent (`<bundle id>.login.plist` in `Contents/Library/LaunchAgents`, written at build time from the template `LaunchAgents/login.plist` with the app's bundle identifier filled in, and registered with [`SMAppService.agent(plistName:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/agent(plistname:))). It starts the app with `--launched-at-login`. Registering the agent also starts a copy immediately; that copy sees the running instance and exits silently, without opening Settings.
- **Who handles ⌘⇥:** the bottom bar shows who handles ⌘⇥ now: TaskSwitcher, macOS, or waiting for Accessibility. Next to the status is **Use TaskSwitcher** or **Restore macOS Switcher**, stored as `replaceDockSwitcher`.
- **Settings in the switcher:** while the Settings window is open, TaskSwitcher switches to the `.regular` activation policy ([`setActivationPolicy(_:)`](https://developer.apple.com/documentation/appkit/nsapplication/setactivationpolicy(_:))). It gets a Dock icon and a menu bar, and is listed in ⌘⇥ like any app with a window. Closing the window switches it back to `.accessory` and activates the previously used app.
- **Exit and shortcuts:** the window has an **Exit** button at the bottom left. ⌘W closes the window and ⌘Q quits. These shortcuts come from a hidden main menu: an LSUIElement app never shows its menu bar, but AppKit still routes key equivalents through it.
- **Accessibility:** while access is missing, a banner under the preview explains why it is needed. Its **Grant Access…** button shows the system prompt the first time. The system shows that prompt only once per app, so later clicks open Privacy & Security ▸ Accessibility instead.
- **Single instance:** a second launch (`open -n`, running the binary directly, a different build) finds the running copy with
  [`runningApplications(withBundleIdentifier:)`](https://developer.apple.com/documentation/appkit/nsrunningapplication/runningapplications(withbundleidentifier:)).
  It hands activation over with [`yieldActivation(to:)`](https://developer.apple.com/documentation/appkit/nsapplication/yieldactivation(to:)),
  asks the running copy to show Settings through
  [`DistributedNotificationCenter`](https://developer.apple.com/documentation/foundation/distributednotificationcenter), and exits.
  Opening the app from Finder or Spotlight while it runs re-activates the running copy, which shows Settings in
  `applicationShouldHandleReopen`.

**Display identity.** `CGDirectDisplayID` can change when monitors are re-plugged, moved to a different port, or
after a reboot. Pinned displays are therefore saved as the ColorSync display UUID
(`CGDisplayCreateUUIDFromDisplayID`), which is tied to the vendor, model and serial. Settings remembers each
display's last `localizedName`, so a pinned monitor that is unplugged still shows by name.
Known limit: two identical monitors that report no serial number get the same UUID. They are then pinned or
unpinned together.

**Per-display sizing.** Each panel works out its own icon size from its display's width (up to the
*Icon size* setting). A panel on a laptop display shrinks; a panel on a large external display keeps
full-size icons.

**Panel configuration.** The panel uses `NSPanel` with `.nonactivatingPanel` and `.borderless`. `canBecomeKey` is false, so it never steals focus.
Level is `.popUpMenu`. Collection behaviour is
`[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, so it shows on every Space and over
full-screen apps.

**Look (matches the macOS 26 switcher):**
- **Panel:** a rounded rectangle, not a capsule. Its corners are concentric with the selection tile: the tile's radius plus the gap to the panel edge, about 0.38 × icon size. On macOS 26 and later it is real Liquid Glass ([`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))). On older versions it is an `NSVisualEffectView` (`.hudWindow`) with a light rim.
- **Icons:** they sit almost edge to edge, because the artwork has its own transparent margin.
- **Selection:** a solid, lighter grey tile around the icon only, at 98% of the icon frame, with a barely visible rim. It is drawn, not made of glass, because glass on top of the glass panel renders inconsistently.
- **App name:** only the selected app's name is shown, under the tile.
- **Icon size setting:** an `NSSlider` with a single tick mark, because SwiftUI's `Slider` cannot draw one. The range 64–192 is centred on the system size (128 pt), so the tick marks that size. Values within 6 pt of it snap to it; everything else moves in steps of 8.

---

## 3. Replacing the Dock switcher (“the trick”)

The WindowServer keeps a table of *symbolic hot keys*: system shortcuts owned by the Dock and other system
processes. ⌘⇥ is ID `1` and ⌘⇧⇥ is ID `2`. The private, but long-stable, call

```c
CGError CGSSetSymbolicHotKeyEnabled(CGSSymbolicHotKey hotKey, bool isEnabled);
bool    CGSIsSymbolicHotKeyEnabled(CGSSymbolicHotKey hotKey);
```

switches a hot key off **for the current login session**. While it is off, ⌘⇥ arrives as ordinary `keyDown`
events, which our session event tap receives and swallows. The symbols are exported by CoreGraphics (re-exported from
SkyLight), so they are declared in the bridging header and linked normally. Hardened runtime and notarization
both allow this, because no entitlement is needed to call a system library. AltTab and similar tools use the same
technique.

Why this approach rather than the alternatives:

| Alternative | Rejected because |
|---|---|
| Writing `AppleSymbolicHotKeys` in `com.apple.symbolichotkeys.plist` | Persistent. If the app is deleted or crashes, ⌘⇥ stays dead even after logout. Needs `activateSettings -u` or a re-login to take effect. |
| Injecting code into the Dock (SIMBL-style, `mach_inject`) | Requires turning off SIP and library validation. Breaks with every macOS update. Impossible to notarize. |
| Carbon `RegisterEventHotKey` | Cannot take a key that the WindowServer already owns. Cannot detect ⌘ being released, and cannot swallow the follow-up keys. |
| `NSEvent.addGlobalMonitorForEvents` | Observe-only. It cannot swallow events. |
| Listen-only event tap (Input Monitoring permission) | Cannot swallow events. |

### 3.1 Safety net: ⌘⇥ must never end up doing nothing

1. **Fail safe at runtime.** `TakeoverCoordinator` turns the Dock's ⌘⇥ off only while the event tap is running.
   It turns it back on immediately when the user switches TaskSwitcher off, when Accessibility is revoked,
   or when **Secure Keyboard Entry** is on (password fields, Terminal's Secure Keyboard Entry). Secure input hides keystrokes from event taps,
   so the Dock handles ⌘⇥ during that time.
2. **Clean exit.** Quit, `applicationWillTerminate`, SIGTERM, SIGINT and SIGHUP all re-enable the Dock's hot keys.
3. **Crash.** The setting lives only in the WindowServer session, so a logout always restores it. Without a logout,
   `"Task Switcher" --restore-native-switcher` re-enables it right away.
4. **Tap timeouts.** macOS switches a tap off when its callback takes too long (about a second), and key events sent meanwhile are lost.
   The callback therefore only reads prepared state: the app list and icons are ready in advance, and switching to the chosen app
   runs after the callback has returned. If the tap is switched off anyway (`tapDisabledByTimeout` or `tapDisabledByUserInput`), it is
   re-enabled in the callback, and the current modifier keys are read so a release of ⌘ missed meanwhile still ends the session.

### 3.2 Installation

`Distribution/build-dmg.sh` builds `TaskSwitcher-<version>-<build>.dmg`. Opening it mounts a disk named TaskSwitcher, which shows the app icon:
the volume carries `.VolumeIcon.icns`, copied from the built app, and the Finder custom-icon flag. On the disk are
`Task Switcher.app` and a shortcut to `/Applications`. There is no installer and no administrator password.

| Step | What happens |
|---|---|
| Install | Drag `Task Switcher.app` onto the Applications shortcut. |
| First launch | The user opens the app. It registers the login agent (only when running from `/Applications`, so debug builds never register) and opens Settings, where the banner asks for Accessibility. Once access is granted, the Dock's ⌘⇥ is turned off and TaskSwitcher takes over. |
| Every login | The login agent starts the app with `--launched-at-login`. The app takes ⌘⇥ again without showing a window, unless the display choice is missing or outdated. |
| Upgrade | Quit the running copy with **Exit** in Settings (this hands ⌘⇥ back to the Dock), replace the app, then open the new one. |
| Uninstall | Quit with **Exit**, then move the app to the Trash. macOS removes its login item with it. The Accessibility entry and the preferences stay behind, as for any drag-installed app. |

---

## 4. Signing and distribution

| Setting | Debug | Release | Why |
|---|---|---|---|
| `CODE_SIGN_STYLE` | Automatic | Manual | Developer ID certificates are not managed by automatic signing. |
| `CODE_SIGN_IDENTITY` | `Apple Development` | `Developer ID Application` | Release is distributed outside the Mac App Store. |
| `DEVELOPMENT_TEAM` | `$DEVELOPMENT_TEAM` | same | From `.envrc` when the project is generated, and passed again by the distribution scripts. |
| `ENABLE_HARDENED_RUNTIME` | YES | YES | Required for notarization. No exception entitlements are needed. |
| `ENABLE_APP_SANDBOX` | NO | NO | See [§1](#1-how-the-system-switcher-works-and-what-limits-a-replacement). |
| `OTHER_CODE_SIGN_FLAGS` | `--timestamp` | `--timestamp` | Notarization requires a secure timestamp. |
| `PRODUCT_BUNDLE_IDENTIFIER` | `$PROJECT_IDENTIFIER` | same | From `.envrc` when the project is generated. The Accessibility (TCC) entry is tied to it and to the signing team. |

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`make gen`, pinned in `mise.toml`) and is not committed. The team and bundle identifier come from the environment, so the repository holds neither.
`TaskSwitcher/` is a synced folder, so Xcode itself picks up every file in it, including the Icon Composer icon.

Debug and Release have different signatures, so macOS treats them as different apps for Accessibility. Each
needs its own permission grant.

### Making the disk image: `make dmg`

Everything runs from the command line, with no Xcode Organizer. `make dmg` regenerates the project first.

| File | Role |
|---|---|
| `.envrc` (local) / `.envrc.default` (template) | `DEVELOPMENT_TEAM`, `PROJECT_IDENTIFIER` and `NOTARY_PROFILE`, loaded by direnv. The scripts load `.envrc` themselves when run outside a direnv shell. |
| `Distribution/common.sh` | Shared settings. Intermediate files go to `$TMPDIR/taskswitcher-dist`, outside the project. Only the finished `.dmg` goes to `dist/`. |
| `Distribution/export-app.sh` | `xcodebuild archive` (universal) → `-exportArchive` with `method = developer-id` → checks hardened runtime, secure signature and no `get-task-allow`. |
| `Distribution/build-dmg.sh` + `Distribution/dmg-settings.py` | The exported app draws the window background itself (`--render-dmg-background`, `DiskImageBackground`): the same switcher example as in Settings, with an arrow from the app to Applications. `tiffutil` merges the 1× and 2× renders. [dmgbuild](https://dmgbuild.readthedocs.io), pinned in `mise.toml`, then builds the image from `dmg-settings.py`: app, Applications shortcut, disk icon, background, a 640 × 428 window, 128 pt icons, app on the left and Applications on the right, with no toolbar, status bar or path bar. It writes these straight into the disk's `.DS_Store`. Finder is never scripted, because when it is, it adjusts the window: on macOS 26 it widened this one to 920 pt. Finally the script signs the `.dmg` with Developer ID Application. |
| `Distribution/notarize.sh` | `notarytool submit --wait` (which also checks the app inside) → `stapler staple` → `stapler validate` + `spctl` Gatekeeper check. |
| `Distribution/set-file-icon.sh` | Last step: gives the `.dmg` file the app icon ([`setIcon(_:forFile:options:)`](https://developer.apple.com/documentation/appkit/nsworkspace/seticon(_:forfile:options:))). The icon is Finder metadata outside the signed contents, so it is set after stapling. It survives AirDrop and zip files, but not a bare upload to a web server. |

The path bar and status bar Finder sometimes shows at the bottom of disk image windows are not part of the image. They
come from the user's Finder settings (View ▸ Show Path Bar / Show Status Bar), which apply to every window that does not
store its own choice. That is why Blender's disk shows them too. `dmg-settings.py` stores "off" for both in the disk's `.DS_Store`.

Requirements: the **Developer ID Application** certificate in the keychain, and a notarytool keychain profile.
The profile belongs to the Apple ID and team, not to a project, so one stored for another app works here too.

## 5. API inventory

### Used

| Area | API | Notes |
|---|---|---|
| Key interception | [`CGEvent.tapCreate`](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)), [`CGEventTapLocation.cgSessionEventTap`](https://developer.apple.com/documentation/coregraphics/cgeventtaplocation), [`CGEvent.tapEnable`](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)) | `.defaultTap` (can swallow events). Needs Accessibility. |
| Taking ⌘⇥ from the Dock | `CGSSetSymbolicHotKeyEnabled` / `CGSIsSymbolicHotKeyEnabled` (private). See [CGSInternal/CGSHotKeys.h](https://github.com/NUIKit/CGSInternal/blob/master/CGSHotKeys.h) and the AltTab implementation in [alt-tab-macos](https://github.com/lwouis/alt-tab-macos) | Session-only. Restored on exit. |
| Secure input | `IsSecureEventInputEnabled` (Carbon HIToolbox). See [TN2150 Using Secure Event Input Fairly](https://developer.apple.com/library/archive/technotes/tn2150/_index.html) | Hands ⌘⇥ back to the Dock while secure input is on. |
| Permissions | [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions), [`AXIsProcessTrusted`](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted) | Prompt on the first request, System Settings afterwards. Polled, because the system sends no notification when it changes. |
| App list | [`NSWorkspace.runningApplications`](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications), [`NSRunningApplication`](https://developer.apple.com/documentation/appkit/nsrunningapplication) (`activationPolicy`, `icon`, `localizedName`, `hide`, `unhide`, `terminate`) | Only `.regular` apps appear, which matches the Dock. |
| Most-recently-used order | [`NSWorkspace.didActivateApplicationNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification), [`didTerminateApplicationNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didterminateapplicationnotification) | |
| Initial order and active-window display | [`CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) | Owner PID, layer and bounds only. These need no Screen Recording permission. |
| Activation | [`AXUIElementCreateApplication`](https://developer.apple.com/documentation/applicationservices/1459374-axuielementcreateapplication), [`AXUIElementSetAttributeValue`](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue) with `kAXFrontmostAttribute` / `kAXMinimizedAttribute`, [`AXUIElementSetMessagingTimeout`](https://developer.apple.com/documentation/applicationservices/1459475-axuielementsetmessagingtimeout); fallback [`NSRunningApplication.activate(options:)`](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:)). Apps without a visible window are activated with `_SLPSSetFrontProcessWithOptions(psn, 0, noWindows \| userGenerated)`, a private SkyLight call loaded with `dlsym`, the same one AltTab and yabai use. `AXFrontmost` silently does nothing for such apps, but the SkyLight call makes their menu bar active, as the Dock does. Accessibility does not list windows on other Spaces, full-screen ones included ([forum thread](https://developer.apple.com/forums/thread/121114)). When an app has none on this Space but has one elsewhere (looked up with `CGWindowListCopyWindowInfo(.optionAll)`, minimized windows excluded through `_AXUIElementGetWindow`, private), it is opened with [`NSWorkspace.openApplication(at:configuration:)`](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)), as clicking its Dock icon does, which switches to that Space. Tried first and dropped: passing the window to `_SLPSSetFrontProcessWithOptions` and making it key with `SLPSPostEventRecordTo` (AltTab's method) only activated the menu bar on macOS 27. | See cooperative activation: [`activate(from:options:)`](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:)). |
| Displays | [`NSScreen`](https://developer.apple.com/documentation/appkit/nsscreen) (`screens`, `frame`, `visibleFrame`, `localizedName`, `deviceDescription["NSScreenNumber"]`), [`NSApplication.didChangeScreenParametersNotification`](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification), `CGDisplayCreateUUIDFromDisplayID` ([ColorSync](https://developer.apple.com/documentation/colorsync)) | Stable display identity for pinning. |
| Switcher window | [`NSPanel`](https://developer.apple.com/documentation/appkit/nspanel), [`.nonactivatingPanel`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel), [`NSWindow.CollectionBehavior`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct), [`NSWindow.Level`](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct), [`NSVisualEffectView`](https://developer.apple.com/documentation/appkit/nsvisualeffectview) | |
| UI | [`NSHostingView`](https://developer.apple.com/documentation/swiftui/nshostingview), [`AppStorage`](https://developer.apple.com/documentation/swiftui/appstorage), [Observation](https://developer.apple.com/documentation/observation) | |
| Login item | [`SMAppService.agent(plistName:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/agent(plistname:)) ([ServiceManagement](https://developer.apple.com/documentation/servicemanagement)) | Appears under System Settings ▸ General ▸ Login Items. |
| Signing and distribution | [Developer ID](https://developer.apple.com/developer-id/), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime), [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) | `hdiutil(1)`, `codesign(1)`, `xcrun notarytool`, `xcrun stapler`. |

### Explored and kept for later

| API | Possible use | Cost |
|---|---|---|
| [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) — [`SCShareableContent`](https://developer.apple.com/documentation/screencapturekit/scshareablecontent), [`SCScreenshotManager`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager) | Window thumbnails for a per-window mode (Windows-style Alt-Tab). | Screen Recording permission, plus the monthly re-consent prompt on recent macOS. |
| [`kAXWindowsAttribute`](https://developer.apple.com/documentation/applicationservices/kaxwindowsattribute), `_AXUIElementGetWindow` (private) | List and raise individual windows. Map AX windows to `CGWindowID` (already used for activation). | Slow for apps that do not respond quickly. Needs per-app caching. |
| [`CGRequestListenEventAccess`](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()) | Input Monitoring-only mode. | Cannot swallow keys, so it is not enough to replace ⌘⇥. |
| [`NSWorkspace.activeSpaceDidChangeNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification) | Space-aware filtering ("only apps on this Space"). | Window-to-Space mapping needs private CGS calls. |
| [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) / Mac App Store | — | Not possible with this design (see §1). |

---

## 6. Settings (UserDefaults, domain: the app's bundle identifier)

| Key | Type | Default |
|---|---|---|
| `replaceDockSwitcher` | Bool | `true` |
| `displayPlacement` | String (`dock` / `mouse` / `activeWindow`), used when no display is switched on | `dock` |
| `pinnedDisplays` | [String] UUIDs of displays switched on | `[]` |
| `didRequestAccessibility` | Bool | — |
| `settingsVersion` | Int, the version the display choice was saved with | — |
| `knownDisplayNames` | [UUID: name] | — |
| `maxIconSize` | Double, 64–192 | `128` (system size) |
| `didRegisterLoginItem` | Bool | — |

## 7. Ideas for later

- Per-window mode with thumbnails (ScreenCaptureKit + AX), on its own shortcut such as ⌥⇥.
- ↑ / ↓ to open App Exposé for the selected app, as the Dock does.
- Choose a display per Space or per display arrangement (remembered sets of pinned displays).
