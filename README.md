# Skitcho

Skitcho is a native macOS image-annotation editor for Apple silicon. It edits pictures only: open or
paste an image, mark it up, export it. It does not capture screens, record video, edit PDFs or sync to any service.

## Features

- Annotation tools: arrow, line, rectangle, rounded rectangle, ellipse, marker, highlighter, text and
  stamps (approve, reject, question, attention, perfect), with an optional label on a stamp.
- Pixelate to hide sensitive areas.
- Image operations: crop, resize, expand canvas, rotate and flip.
- Select, move, resize, nudge and reorder annotations; per-element color and size.
- Undo and redo.
- New documents from a blank canvas, an image file, a Dock drop or the clipboard.
- Copy the image or the annotations to the clipboard; paste images and annotations.
- Export to PNG, JPEG (quality setting) or TIFF, optionally at 2x (Retina); drag the image out of the window.
- Zoom, fit-to-window and Space-drag panning.
- Light and dark appearance.
- Automatic updates through Sparkle.

## Requirements

- macOS 15 or later
- Apple silicon (arm64). Intel Macs are not supported.

## Install

1. Download the latest `.zip` from [GitHub Releases](https://github.com/oleggohman/skitcho/releases).
2. Unzip it and move `Skitcho.app` to `/Applications`.

Release builds are signed with a Developer ID and notarized by Apple. Skitcho checks for updates
automatically through Sparkle (see [Updates](#updates)).

## Build, run and test

```bash
swift build --arch arm64                               # build
swift test --arch arm64 --no-parallel                  # run all tests (serial; see CONTRIBUTING.md)
swift format lint --strict --recursive Sources Tests   # lint
scripts/bundle.sh                                      # assemble build/Skitcho.app (arm64, ad-hoc signed)
scripts/test-bundle.sh                                 # verify the bundle (arm64-only, plist, codesign, tokens)
```

Run the app only through the bundle, for example `open build/Skitcho.app`. The raw SwiftPM
executable is not a proper app bundle (no document types, no Sparkle framework, no icon).

## Keyboard shortcuts

### Tools

Press a letter to switch tool (case-insensitive):

| Key | Tool | Key | Tool |
| --- | --- | --- | --- |
| V | Select | R | Rectangle |
| A | Arrow | U | Rounded rectangle |
| T | Text | O | Ellipse |
| M | Marker | L | Line |
| H | Highlighter | S | Stamp |
| P | Pixelate | C | Crop |

Precedence (highest first):

1. While a text element is being edited, every key goes to the text editor.
2. With the Text tool active, typing creates text, so letters are never tool shortcuts.
3. With any other tool, a plain letter switches to the matching tool.

Command, Control and Option chords never switch tools. Hold Space and drag to pan with any tool.

### Commands

| Shortcut | Action |
| --- | --- |
| ⌘N / ⌘O / ⌘S | New / Open / Save |
| ⌥⌘N | New from Clipboard |
| ⇧⌘E | Export As… |
| ⇧⌘C | Copy Image |
| ⌘Z / ⇧⌘Z | Undo / Redo |
| ⌘X / ⌘C / ⌘V | Cut / Copy / Paste annotations |
| ⌘A | Select All |
| Delete | Delete selection |
| Arrow keys (Shift: x10) | Nudge selection |
| Esc | Deselect |
| ⌘] / ⌘[ | Bring Forward / Send Backward |
| ⌘+ / ⌘- | Zoom In / Zoom Out |
| ⌘0 | Actual Size |
| ⌘9 | Zoom to Fit |

## File format

A `.skitcho` document is a package (a directory the Finder shows as one file):

```text
MyImage.skitcho/
  document.json   # canvas size, image offset, annotation elements, format version
  base.png        # the base image
```

Plain images open as new untitled documents. The first Save asks where to store a `.skitcho`; the
source image is never overwritten. A package written by a newer version of the app is rejected with
an error instead of being misread.

## Updates

Skitcho updates itself with [Sparkle](https://sparkle-project.org). Updates come from an
EdDSA-signed appcast published with each GitHub release, and Sparkle verifies the signature before
installing. Use the Check for Updates… menu item, or turn automatic checks on or off in Settings.
Development builds made without a public key have updates disabled. Maintainers: see
[docs/RELEASING.md](docs/RELEASING.md).

## Clean-room statement

Skitcho's feature set was inspected from the original Skitch application binary only. No code or assets
from Skitch were copied. Skitcho is not affiliated with, endorsed by or derived from Evernote or Skitch.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
