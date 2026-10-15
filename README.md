# Task Switcher

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

This builds a Developer ID signed, notarized and stapled `dist/TaskSwitcher-<version>.dmg`. It needs the
**Developer ID Application** certificate in your keychain and `NOTARY_PROFILE` in `.envrc`. The steps
are described in [docs/architecture.md](docs/architecture.md#making-the-disk-image-make-dmg).

## License

Licensed under the [Apache License 2.0](LICENSE). © 2026 Boris Vanin.
