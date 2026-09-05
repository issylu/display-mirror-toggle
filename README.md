# DisplayToggle

A tiny macOS menu bar utility to switch between **Extend Desktop** and **Mirror Displays** with a single click — no need to dig through System Settings.

## Features

- **Left-click** the menu bar icon to instantly toggle Mirror ⇄ Extend.
- **Right-click** for more options:
  - **Mirror source** — choose whether the built-in display or the external display drives the mirrored image (only relevant while mirroring).
  - **Per-display resolution** — switch resolution for the built-in display or any connected external display, without opening System Settings.
- Runs as a background menu bar item only (no Dock icon).
- No dependencies — pure Swift + AppKit + CoreGraphics.

## Requirements

- macOS 11+ (uses SF Symbols)
- Xcode Command Line Tools (for `swiftc`) — no full Xcode project needed

## Build

```sh
./build.sh
```

This compiles `main.swift` and packages `DisplayToggle.app` in the same folder.

## Install

```sh
cp -R DisplayToggle.app /Applications/
open /Applications/DisplayToggle.app
```

Optional — start automatically at login: **System Settings → General → Login Items** → add `DisplayToggle.app`.

## Usage

| Action | Effect |
|---|---|
| Left-click icon | Toggle Mirror / Extend |
| Right-click → Mirror source | Pick which display's image is shown when mirroring |
| Right-click → resolution submenu | Change resolution of that specific display |
| Right-click → Quit | Exit the app |

## How it works

Built entirely on public `CoreGraphics` display-configuration APIs — no private frameworks.

- `CGBeginDisplayConfiguration` / `CGConfigureDisplayMirrorOfDisplay` / `CGCompleteDisplayConfiguration` drive the mirror toggle, wrapped in a single atomic configuration transaction.
- `CGConfigureDisplayWithDisplayMode` applies a resolution change the same way.

A couple of non-obvious gotchas discovered while building this:

- **`CGGetActiveDisplayList` excludes mirror slaves.** Once a display is already mirroring another, it drops out of the "active" list, so a naive implementation loses track of it and can't toggle back. Use `CGGetOnlineDisplayList` instead — it lists every connected display regardless of mirror state.
- **`CGDisplayCopyAllDisplayModes` hides the "friendly" HiDPI resolutions by default.** On a Retina display, the human-readable scaled resolutions you see in System Settings (e.g. `1792 x 1120`) are only returned when you pass the `kCGDisplayShowDuplicateLowResolutionModes` option; without it, you only get raw unscaled native-pixel modes. Each `CGDisplayMode` exposes both `.width`/`.height` (logical/point size) and `.pixelWidth`/`.pixelHeight` (actual framebuffer pixels) — a true Retina-scaled mode has `pixelWidth == width * 2`, which is how this app filters down to just the "friendly numbers" and falls back to the full list for non-Retina external displays.
- **`CGConfigureDisplayMirrorOfDisplay` is technically deprecated** but still functions correctly as of macOS Sonoma — there's currently no modern public replacement, which is why third-party display tools still rely on it.

## License

Personal project — no license file yet.
