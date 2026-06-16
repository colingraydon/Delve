# Delve

A free, open-source disk space visualizer for macOS. Delve scans a drive or
folder and draws what's using your space as an interactive **treemap**, where
bigger files and folders are bigger rectangles, so you can spot space hogs at
a glance and clear them out.

> **Status:** unsigned, un-notarized builds (see [Installing](#installing)).
> macOS 14 (Sonoma) or later.

## What it does

- **Scan any disk or folder.** Launches to a list of your mounted drives.
  Pick one (or choose a specific folder) to scan.
- **Treemap view.** Each item is a tile sized by how much space it uses, with
  distinct colors so neighbors are easy to tell apart. Click a folder tile to
  zoom in, then use the breadcrumbs or back button to come back out.
- **Sidebar breakdown.** The current folder's contents listed largest-first,
  with sizes and color dots matching the map.
- **Trash collector.** Drag tiles onto the trash can to queue them, review the
  queue in the bottom bar, then **Move All to Trash**, with a 5-second
  countdown and Undo before anything actually moves.
- **Safety first.** Delve refuses to trash system locations, your home folder
  and its standard subfolders, and media libraries. Items go to the macOS
  Trash, and nothing is ever permanently deleted by the app.

## Installing

1. Download the latest `Delve.dmg` from the
   [**Releases**](https://github.com/colingraydon/Delve/releases/latest) page.
2. Open the DMG and drag **Delve** into your **Applications** folder.

### First launch: the Gatekeeper warning

These builds are **not signed with an Apple Developer ID and not notarized**
(that requires a paid Apple Developer account). Because of that, macOS
Gatekeeper will block the first launch with a message like *"Apple cannot check
it for malicious software."* This is expected for an unsigned app. Here is how
to open it:

- **Right-click** (or Control-click) **Delve.app** in Applications and choose
  **Open**, then click **Open** again in the dialog. You only need to do this
  once.
- If that doesn't work, remove the download quarantine flag from Terminal:

  ```sh
  xattr -dr com.apple.quarantine /Applications/Delve.app
  ```

If you'd rather not trust a prebuilt binary, you can
[build it yourself](#building-from-source). It's a couple of commands.

### Granting access for a full scan

To scan your whole startup disk, macOS may prompt for access to folders like
Desktop, Documents, and Downloads. For complete results, grant Delve **Full
Disk Access** in **System Settings -> Privacy & Security -> Full Disk Access**.
Without it the scan still works but under-counts protected areas.

## Building from source

Requires Xcode 16+ on macOS 14+.

```sh
git clone https://github.com/colingraydon/Delve.git
cd Delve
open Delve.xcodeproj   # then press Cmd-R to run
```

Run the tests:

```sh
xcodebuild test -project Delve.xcodeproj -scheme Delve -destination 'platform=macOS'
```

Build a distributable disk image into `dist/`:

```sh
./scripts/build_dmg.sh
```

The DMG is ad-hoc signed by default. To produce a notarized, warning-free build
you need an Apple Developer ID. Pass it (and a stored notarytool credential)
via environment variables. See the comments at the top of
[`scripts/build_dmg.sh`](scripts/build_dmg.sh).

## Releases

Pushing a version tag builds the DMG in CI and attaches it to a GitHub Release:

```sh
git tag v1.0
git push origin v1.0
```

See [`.github/workflows/release.yml`](.github/workflows/release.yml).

## License

[MIT](LICENSE) © Colin Graydon
