# Skitcho

A fast, native macOS app for marking up pictures.

[![CI](https://github.com/oleggohman/skitcho/actions/workflows/ci.yml/badge.svg)](https://github.com/oleggohman/skitcho/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/oleggohman/skitcho)](https://github.com/oleggohman/skitcho/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B%20%7C%20Apple%20silicon-lightgrey)](#install)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange)](Package.swift)

Skitcho is an open-source image-annotation editor. Open or paste a picture, mark it up with arrows,
shapes, text, freehand strokes and stamps, then export it or keep working on it later.

It annotates pictures and nothing else: there is no screen capture, no cloud sync and no PDF support.
It is a native SwiftUI/AppKit app, built for Apple silicon only (arm64).

<!-- screenshot: docs/images/screenshot.png (added after first manual test) -->

## Features

**Annotate**

- Arrow, line, rectangle, rounded rectangle and ellipse.
- Text, edited in place: outlined (readable on any background) or plain, with an adjustable wrap width.
- Freehand marker and highlighter, smoothed into clean curves.
- Stamps (approve, reject, question, attention, perfect) with an optional pointer tail and an attached
  label (double-click the stamp or use **Attach Label**).
- Per-element color (ten presets plus a custom color) and five size steps.
- Select, move, resize, nudge and reorder annotations.

**Edit the image**

- Pixelate a region to hide sensitive content.
- Crop, resize, expand the canvas, rotate and flip.

**Work with files**

- Open images, or start from a blank canvas, the clipboard (New from Clipboard) or a Dock drop.
- Save an editable `.skitcho` package; the original image is never overwritten.
- Export to PNG, JPEG (quality slider) or TIFF, optionally at Retina 2×.
- Copy the flattened image to the clipboard, or drag the image out of the window.

**App**

- Undo and redo.
- Light and dark appearance.
- Automatic updates through Sparkle.

## Install

1. Download the latest `Skitcho-<version>.dmg` from [GitHub Releases](https://github.com/oleggohman/skitcho/releases).
2. Open the disk image and drag `Skitcho.app` onto the `Applications` folder.
3. Open it. To make Skitcho the editor for an image, use Finder's **Open With ▸ Skitcho**.

Requirements: macOS 15 or later on Apple silicon. Intel Macs are not supported.

Release builds are signed with a Developer ID and notarized by Apple, so Gatekeeper opens them normally.
Updates arrive automatically through [Sparkle](https://sparkle-project.org). Use **Check for Updates…**
in the app menu, or turn automatic checks on or off in Settings. Sparkle verifies an EdDSA signature
before installing an update.

## Quick start

1. Open an image with ⌘O, or press ⌥⌘N to start from the clipboard.
2. Pick a tool from the palette or press its letter (for example `A` for Arrow, `R` for Rectangle).
3. Drag on the canvas to draw. Adjust color and size in the properties panel.
4. Switch to Select (`V`) to move, resize or delete annotations; ⌘Z undoes any step.
5. Export with ⇧⌘E (PNG, JPEG or TIFF, optional Retina 2×), copy the result with ⇧⌘C, or save an
   editable `.skitcho` document with ⌘S.

## Keyboard shortcuts

### Tools

Press a letter to switch tool (case-insensitive). The same letters are shown in the Tools menu.

| Key | Tool | Key | Tool |
| --- | --- | --- | --- |
| V | Select | R | Rectangle |
| A | Arrow | U | Rounded rectangle |
| T | Text | O | Ellipse |
| M | Marker | L | Line |
| H | Highlighter | S | Stamp |
| P | Pixelate | C | Crop |

Who gets a key press, highest priority first:

1. While a text element is being edited, every key goes to the text editor.
2. With the Text tool active, typing starts a new text, so letters are not tool shortcuts.
3. Otherwise a plain letter switches to the matching tool.

Command, Control and Option chords never switch tools.

### Menu commands

| Shortcut | Action |
| --- | --- |
| ⌘N / ⌘O / ⌘S | New / Open / Save |
| ⌥⌘N | New from Clipboard |
| ⇧⌘E | Export As… |
| ⇧⌘C | Copy Image |
| ⌘Z / ⇧⌘Z | Undo / Redo |
| ⌘X / ⌘C / ⌘V | Cut / Copy / Paste annotations |
| ⌘A | Select All |
| ⌘] / ⌘[ | Bring Forward / Send Backward |
| ⌘+ / ⌘- | Zoom In / Zoom Out |
| ⌘0 | Actual Size |
| ⌘9 | Zoom to Fit |

The Image menu (Crop, Resize…, Rotate, Flip, Expand Canvas) has no keyboard shortcuts.

### Canvas

| Input | Action |
| --- | --- |
| Space + drag | Pan, with any tool |
| Pinch (trackpad) | Zoom |
| Arrow keys | Nudge the selection (hold Shift for ×10) |
| Delete | Delete the selection |
| Esc | Deselect, or cancel the current operation |

## File format

A `.skitcho` document is a package, a folder that Finder shows as a single file:

```text
MyImage.skitcho/
  document.json   # canvas size, image offset, annotation elements, format version
  base.png        # the base image
```

Plain images open as new untitled documents, and the first Save asks where to store a `.skitcho`.
Plain images are never overwritten. A package written by a newer version of the app is rejected with
an error instead of being misread.

## Build from source

Requirements: Xcode 27 (Swift 6.4) on Apple silicon.

```bash
swift build --arch arm64                               # build
swift test --arch arm64 --no-parallel                  # run all tests (serial only)
swift format lint --strict --recursive Sources Tests   # lint
scripts/bundle.sh                                      # assemble build/Skitcho.app (arm64, ad-hoc signed)
scripts/test-bundle.sh                                 # verify the bundle (thin arm64, plist, codesign)
```

Run the app only through the bundle, for example `open build/Skitcho.app`. The bare SwiftPM
executable lacks document types, the Sparkle framework and the icon. Development builds made without a
Sparkle public key have updates disabled.

See [CONTRIBUTING.md](CONTRIBUTING.md) for workflow and rules.

## Releasing

Maintainers: see [docs/RELEASING.md](docs/RELEASING.md).

## Security

Report vulnerabilities privately through GitHub; see [SECURITY.md](SECURITY.md).

## Clean-room and trademarks

Skitcho is inspired by the feature set of the discontinued Skitch app. No code or assets from Skitch
were copied. Skitcho is not affiliated with, endorsed by or derived from Evernote or Skitch.

## License

[MIT](LICENSE)
