# Task Switcher

> [!IMPORTANT]
> **This entire project was written by Claude (Anthropic's Claude Opus 5.5) working in Claude Code.**
> Every line of source code, the build setup, the scripts, the app icon, the docs and this README were
> written by the model under Boris Vanin's direction. Keep that in mind when reading, reusing or
> auditing the code.

A replacement for the macOS ⌘⇥ app switcher that can show on the displays you choose. The system
switcher always appears on the display with the Dock; Task Switcher can pin it to one or several
monitors, or follow the mouse pointer or the active window. Otherwise it behaves like the system one.

This README is for developers building and running it from source. How it works, and why it has to
work this way, is in [docs/architecture.md](docs/architecture.md).

## Requirements

- macOS 14 or later, Xcode 27 or later
- An Apple Developer account. The app takes ⌘⇥ from the Dock through the Accessibility permission,
  and macOS ties that permission to the app's signature, so it has to be signed
- [mise](https://mise.jdx.dev): installs the pinned [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  (and dmgbuild for `make dmg`) from `mise.toml`
- [direnv](https://direnv.net) (optional): loads `.envrc` into your shell

## Configuration

Your team and bundle identifier stay on your Mac, in `.envrc`, which git ignores:

```sh
cp .envrc.default .envrc
```

| Variable | Needed for | Value |
|---|---|---|
| `DEVELOPMENT_TEAM` | everything | Your Team ID (Xcode ▸ Settings ▸ Accounts). |
| `PROJECT_IDENTIFIER` | everything | The app's bundle identifier, e.g. `com.example.TaskSwitcher`. The Accessibility permission, the saved settings and the login item are tied to it, so changing it later means granting Accessibility again. |
| `NOTARY_PROFILE` | `make dmg` | A notarytool keychain profile. `.envrc.default` shows how to create one. |

Then load it with `direnv allow` (again after every edit), or `source .envrc` in each shell.

## Generating the Xcode project

The Xcode project is generated from `project.yml` and isn't committed:

```sh
mise trust      # once: lets mise use this project's mise.toml
mise install    # once: the pinned XcodeGen and dmgbuild
make            # generates TaskSwitcher.xcodeproj
make open       # generates it and opens it in Xcode
```

Run `make` again after changing `project.yml` or `.envrc`. Your team and bundle identifier are written
into the project when it is generated, so Xcode doesn't need the environment. Source files are a
synced folder: add files to `TaskSwitcher/` in Xcode or on disk, without regenerating.

## Running

Run the `TaskSwitcher` scheme from Xcode (⌘R). Settings opens, since the app has no menu bar icon:
starting the app again is how you get back to Settings.

- **Accessibility:** click **Grant Access…** in Settings and switch Task Switcher on in System Settings ▸
  Privacy & Security ▸ Accessibility. Within a second it takes ⌘⇥ over from the Dock. Debug and Release
  builds are signed differently, so each needs its own grant.
- **Stopping from Xcode:** the Stop button kills the app without letting it hand ⌘⇥ back, so ⌘⇥ does
  nothing until you log out or run:

  ```sh
  "path/to/Task Switcher.app/Contents/MacOS/Task Switcher" --restore-native-switcher
  ```

  Quitting with **Exit** in Settings or ⌘Q gives ⌘⇥ back to the Dock.
- **Login item:** only a copy started from `/Applications` registers itself to start at login, so
  debug builds never end up in Login Items.

## Building a disk image

```sh
make dmg
```

This builds a Developer ID signed, notarized and stapled `dist/TaskSwitcher-<version>-<build>.dmg`. It needs the
**Developer ID Application** certificate in your keychain and `NOTARY_PROFILE` in `.envrc`. The steps
are described in [docs/architecture.md](docs/architecture.md#making-the-disk-image-make-dmg).

## Learned from

### Open-source projects

- [AltTab](https://github.com/lwouis/alt-tab-macos): how a third-party switcher takes ⌘⇥ over from the
  Dock (`CGSSetSymbolicHotKeyEnabled`), brings an app forward with the private SkyLight call
  `_SLPSSetFrontProcessWithOptions`, and finds windows on other Spaces through the WindowServer.
  The techniques came from reading its source; no code was copied.
- [CGSInternal](https://github.com/NUIKit/CGSInternal): "a collection of private CoreGraphics and SkyLight
  routines", used for the declarations of the symbolic hot keys
  ([CGSHotKeys.h](https://github.com/NUIKit/CGSInternal/blob/master/CGSHotKeys.h)).

### Apple documentation

Activation of other apps, and switching to apps in full screen:

- [AppKit release notes for macOS 14](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14) (App Activation)
- [`NSRunningApplication.activate(from:options:)`](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:)),
  [`activate(options:)`](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:))
- [`NSApplication.activate()`](https://developer.apple.com/documentation/appkit/nsapplication/activate()),
  [`yieldActivation(to:)`](https://developer.apple.com/documentation/appkit/nsapplication/yieldactivation(to:)),
  [`ActivationOptions`](https://developer.apple.com/documentation/appkit/nsapplication/activationoptions)
- [`NSWorkspace.openApplication(at:configuration:completionHandler:)`](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)),
  [`OpenConfiguration.activates`](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/activates)

Starting at login:

- [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice),
  [`agent(plistName:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/agent(plistname:)),
  [`unregister()`](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister()),
  [`status`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.property)
- [Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- [Manage login items and background tasks on Mac](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web) (Apple Platform Deployment)

Apple Developer Forums threads:

- [Accessibility API - Access kAXDocumentAttribute of hidden fullscreen windows or tabbed documents](https://developer.apple.com/forums/thread/121114): full-screen windows are missing from an app's Accessibility window list
- [General > Login Items > Allow in the Background](https://developer.apple.com/forums/thread/712335): what happens to a login item when its app is deleted

Every other API the app uses is listed with a link to its documentation in
[docs/architecture.md](docs/architecture.md#5-api-inventory).

## License

Licensed under the [Apache License 2.0](LICENSE). © 2026 Boris Vanin.
