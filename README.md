# Skitcho

Mark up a picture in seconds: point at things, hide what is private, and share the result.

[![Latest release](https://img.shields.io/github/v/release/oleggohman/skitcho)](https://github.com/oleggohman/skitcho/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B%20%7C%20Apple%20silicon-lightgrey)](#install)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/oleggohman/skitcho/badge)](https://scorecard.dev/viewer/?uri=github.com/oleggohman/skitcho)

Skitcho is a free, open-source image-annotation editor for the Mac. Open or paste a picture, add arrows,
shapes, text, freehand strokes and stamps, then save, export or copy it.

It does one job. There is no screen capture, no cloud sync and no PDF support. It is a native
SwiftUI/AppKit app for Apple silicon.

## Contents

- [Install](#install)
- [Quick start](#quick-start)
- [What you can do](#what-you-can-do)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Saving](#saving)
- [File format](#file-format)
- [Build from source](#build-from-source)
- [Security](#security)
- [License and trademarks](#license-and-trademarks)

## Install

Requirements: macOS 15 or later on an Apple silicon Mac. Intel Macs are not supported.

1. Download `Skitcho-<version>.dmg` from the
   [latest release](https://github.com/oleggohman/skitcho/releases/latest).
2. Open the disk image and drag `Skitcho.app` onto the `Applications` folder.
3. Open Skitcho. To edit a picture from Finder, use **Open With ▸ Skitcho**.

Releases are signed with a Developer ID and notarized by Apple, so Gatekeeper opens them normally.

Skitcho updates itself through [Sparkle](https://sparkle-project.org), which checks an EdDSA signature
before it installs anything. To update now, choose **Skitcho ▸ Check for Updates…**. Automatic checks can
be turned on or off in Settings.

<details>
<summary>Optional: verify the download with minisign</summary>

Every release after v0.1.1 also has a [minisign](https://jedisct1.github.io/minisign/) signature,
`Skitcho-<version>.dmg.minisig`. Download it next to the DMG and check the download before you open it
(`brew install minisign`; replace X.Y.Z with the version):

```bash
minisign -Vm Skitcho-X.Y.Z.dmg -P RWT4rkcOBh0Egd4d1Nc/WaPdz5wNdMeFOQ5hV/PdEo0qSVAblgc5qBim
```

It should print `Signature and comment signature verified`. The same key is in
[SECURITY.md](SECURITY.md) and in [`minisign.pub`](minisign.pub).

</details>

## Quick start

1. Open a picture with ⌘O, or press ⌥⌘N to start from the picture on the clipboard.
2. Pick a tool in the palette, or press its letter: `A` for Arrow, `R` for Rectangle, `T` for Text.
3. Drag on the picture to draw. For an arrow, press on the thing you point at and drag away from it:
   the head stays where you pressed.
4. Press `V` (or Esc) for the Select tool to move, resize or delete what you drew. ⌘Z undoes any step.
5. Press ⌘S to save a JPEG, ⇧⌘C to copy the result, or ⇧⌘E to export a PNG, JPEG or TIFF.

## What you can do

### Annotate

| Tool | What it does |
| --- | --- |
| Arrow | A bold arrow with a white outline and a soft shadow, readable on any background |
| Line, Rectangle, Rounded rectangle, Ellipse | Outline shapes |
| Text | Typed in place; outlined or plain, with an adjustable wrap width |
| Marker, Highlighter | Freehand strokes, smoothed into clean curves |
| Stamp | Approve, reject, question, attention or perfect, with an optional pointer tail and label |
| Pixelate | Hides a region, for example a name or a password |

- Every annotation has its own color (ten presets or a custom color) and one of five sizes.
- Annotations stay objects until you save a JPEG: select, move, resize, nudge, reorder, copy and paste them.
- To label a stamp, double-click it or use **Attach Label**.

### Edit the picture

Crop, resize, rotate, flip, or expand the canvas by 64 px on any edge. All of these are in the Image menu.

### Get pictures in and out

- **In:** open an image file, start with a blank canvas, use the clipboard (New from Clipboard), or drop
  a picture on the Dock icon.
- **Out:** save a JPEG, export PNG, JPEG (with a quality slider) or TIFF, optionally at Retina 2×, copy
  the flattened picture to the clipboard, or drag it out of the window into another app.
- **Keep it editable:** save as a `.skitcho` document to change the annotations later.

Skitcho follows the system light or dark appearance.

## Keyboard shortcuts

### Tools

Press a letter to switch tools. The Tools menu shows the same letters.

| Key | Tool | Key | Tool |
| --- | --- | --- | --- |
| V | Select | R | Rectangle |
| A | Arrow | U | Rounded rectangle |
| T | Text | O | Ellipse |
| M | Marker | L | Line |
| H | Highlighter | S | Stamp |
| P | Pixelate | C | Crop |

Letters do not switch tools while you edit a text, or while the Text tool is active (typing starts a
new text there). Chords with Command, Control or Option never switch tools.

### Menu commands

| Shortcut | Action |
| --- | --- |
| ⌘N / ⌘O | New / Open |
| ⌥⌘N | New from Clipboard |
| ⌘S / ⇧⌘S | Save / Save As… |
| ⇧⌘E | Export As… |
| ⇧⌘C | Copy Image |
| ⌘W | Close |
| ⌘Z / ⇧⌘Z | Undo / Redo |
| ⌘X / ⌘C / ⌘V | Cut / Copy / Paste annotations |
| ⌘A | Select All |
| ⌘] / ⌘[ | Bring Forward / Send Backward |
| ⌘+ / ⌘- | Zoom In / Zoom Out |
| ⌘0 / ⌘9 | Actual Size / Zoom to Fit |

The Image menu commands and File ▸ Duplicate have no shortcuts. Revert to Saved, Rename… and Move To…
are available only for a saved `.skitcho` document.

### Canvas

| Input | Action |
| --- | --- |
| Space + drag | Pan, with any tool |
| Pinch | Zoom |
| Arrow keys | Nudge the selection (hold Shift for ×10) |
| Delete | Delete the selection |
| Esc | Cancel what is in progress and return to the Select tool; on Select, clear the selection |

Esc in the text editor keeps the text you typed.

A new window opens in fit mode: the picture follows the window size and is never shown above 100%.
Zooming by hand (⌘+, ⌘-, ⌘0 or pinch) leaves fit mode, and ⌘9 returns to it. The bottom bar shows
"Fit · NN%" in fit mode and "NN%" otherwise.

## Saving

Skitcho saves in two formats.

| Format | Annotations | Use it for |
| --- | --- | --- |
| JPEG (quality 90%) | Flattened into the pixels | Sharing the result |
| `.skitcho` | Stay editable; autosaved | Work you want to change later |

What ⌘S does depends on what is open:

| You have open | ⌘S |
| --- | --- |
| A JPEG | Overwrites that JPEG |
| A new picture, or a PNG, HEIC or other image | Asks where to save; JPEG is preselected, "Skitcho (editable)" is the alternative |
| A `.skitcho` document | Saves the `.skitcho` document |

Save As… (⇧⌘S) always asks, with both formats. Saving a `.skitcho` document as JPEG writes a copy; the
document itself stays a `.skitcho`.

Good to know:

- A JPEG is written only when you press ⌘S or choose Save As…. Autosave never touches your image file.
- A JPEG that you reopen is flat: its annotations are part of the picture and cannot be edited.
- Saving a JPEG removes EXIF and GPS metadata and stores the colors as sRGB.
- If macOS does not give Skitcho the location of the opened file, ⌘S shows the save panel instead of
  overwriting.
- After you save an opened JPEG under a new name, ⌘S writes the new file, but the window title and
  Revert to Saved still refer to the file you opened.

## File format

A `.skitcho` document is a package: a folder that Finder shows as one file.

```text
MyImage.skitcho/
  document.json   # canvas size, image offset, annotations, format version
  base.png        # the base picture
```

Skitcho refuses to open a package written by a newer version, instead of misreading it.

## Build from source

Requirements: Xcode 27 (Swift 6.4) on an Apple silicon Mac.

```bash
swift build --arch arm64                               # build
swift test --arch arm64 --no-parallel                  # run the tests (serial only)
swift format lint --strict --recursive Sources Tests   # lint
scripts/bundle.sh                                      # assemble build/Skitcho.app (ad-hoc signed)
scripts/test-bundle.sh                                 # check the bundle
open build/Skitcho.app                                 # run
```

Always run the app from the bundle. The bare SwiftPM executable has no document types, no Sparkle
framework and no icon. A development build made without a Sparkle public key has updates disabled.

The code has three targets: `SkitchoCore` (model, rendering and file IO, with no AppKit), `SkitchoUI`
(views, canvas and tools) and `Skitcho` (the app itself).

- Workflow and rules: [CONTRIBUTING.md](CONTRIBUTING.md)
- Release procedure, for maintainers: [docs/RELEASING.md](docs/RELEASING.md)

## Security

Report a vulnerability privately through GitHub. [SECURITY.md](SECURITY.md) has the details and the
release signing key.

## License and trademarks

Skitcho is released under the [MIT license](LICENSE).

It is inspired by the feature set of the discontinued Skitch app. No code or assets from Skitch were
copied. Skitcho is not affiliated with, endorsed by or derived from Evernote or Skitch.
