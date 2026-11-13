# Skitcho (project guide)

Native Apple-silicon macOS image-annotation editor (Swift 6, SwiftUI + AppKit, macOS 15+). Picture editing only.
User docs are in `README.md`; contributor rules are in `CONTRIBUTING.md`.

## Canonical commands

```bash
swift build --arch arm64
swift test --arch arm64 --no-parallel      # serial only, one test command at a time
swift format lint --strict --recursive Sources Tests
scripts/bundle.sh                          # -> build/Skitcho.app
scripts/test-bundle.sh                     # also: --release-dry-run (needs minisign: brew install minisign)
scripts/test-workflows.sh
```

- Run the app **only via `build/Skitcho.app`**. The bare SwiftPM executable lacks document types, Sparkle and the icon.
- **arm64 only.** Always pass `--arch arm64`; no x86_64 or universal slices anywhere (`test-bundle.sh` asserts thin arm64).
- SwiftPM, `git commit` and the bundle scripts need the sandbox disabled. `open` does not work in a sandbox.
- Build, test and release happen only on the maintainer's Mac; there is no CI build. GitHub runs only the Linux security scans. The local release flow is in `docs/RELEASING.md`.

## Architecture

Three targets plus tests (`Package.swift`):

- `SkitchoCore`: model, editor logic, image ops, rendering, IO. **AppKit-free**, so it is fully unit-testable.
- `SkitchoUI`: SwiftUI/AppKit views, canvas and tool controllers, panels, pasteboard bridge, theme tokens.
- `Skitcho`: the executable (`@main`, menus in `Commands.swift`, Sparkle `Updater`).

Strategy: put logic in Core, keep UI thin, test both.

### Coordinate rule

Document space is top-left origin, y-down, in image pixels. The single flip to CoreGraphics' y-up is in
`DocumentRenderer` (the canvas view is `isFlipped` and undoes its flip before calling it). Do not flip elsewhere.

### Document concurrency pattern

- `SkitchoDocument` is `@MainActor` and `@preconcurrency ReferenceFileDocument`.
- Its `init(configuration:)`, `init(initial:)` and `fileWrapper(snapshot:configuration:)` are `nonisolated` and pure
  (`PackageCodec`); they never touch the editor. Never use `MainActor.assumeIsolated` in document code.
- `snapshot(contentType:)` is `nonisolated` too: NSDocument saves asynchronously and SwiftUI calls it on a
  background dispatch worker while the main thread is blocked in the save, so it must never touch main-actor
  state and never wait for the main thread (no `DispatchQueue.main.sync`, no awaited main-actor hop). It returns the
  value of a lock-protected `SavableDocumentStore` (`Mutex<State>`: the document plus `isEditingText`) that the
  main actor keeps current via
  `SkitchoDocument.publish()`, triggered by `EditorModel.onDocumentChange` and the text edit's change callback
  (`CanvasView.onSavableDocumentChange`, every keystroke). The "saved during a text edit" undo checkpoint
  (`TextToolController.checkpointSavedEdit`) is scheduled asynchronously from `snapshot`, never run inside it.
- `editor` (`EditorModel`) is a `lazy var` created on the main actor by the view; the window view re-binds the
  `UndoManager` from the environment.
- Core `Document` collides with `SwiftUI.Document`: files importing both add `import struct SkitchoCore.Document`.
- Saving is split in two. `.skitcho` goes through `NSDocument` (`SkitchoDocument` writes only that type). A
  flattened JPEG (`SaveFormat`, quality 0.9) is written by `SaveCoordinator` through an explicit command:
  ⌘S overwrites an opened JPEG (or the target chosen by Save As) only on that command, and asks via the Save
  panel (JPEG preselected, "Skitcho (editable)" as the alternative) for new pictures and other image types.
  The File menu is the `FileMenuItem` table, rendered by `Commands.swift`.
- **HARD rule:** never add a lossy image type (JPEG or similar) to `SkitchoDocument.writableContentTypes`.
  SwiftUI hard-codes autosave-in-place for every writable type, which would silently overwrite the user's file
  (pinned by `SaveFormatTests.swiftUIPlatformDocumentAutosavesInPlace`).

### Fit mode

`CanvasView.fitMode` (default on) makes the zoom follow the window and canvas size, capped at 100%. It is
cleared only by the manual zoom methods (`zoomIn`, `zoomOut`, `actualSize`, pinch `magnify`) and set only by
`zoomToFit`. Do not clear it anywhere else.

### Esc routing

`CanvasView.handleKey` lets the active tool controller handle Esc first (cancel the drag, crop, pixelate, ...),
then switches to the Select tool and keeps the selection; on Select itself Esc clears the selection. While a
text element is edited the key goes to `TextEditorOverlay`, whose `onEscape` callback (after the commit) returns
focus to the canvas and switches to Select.

### Undo pattern

- `EditorModel.perform(name) { change }` snapshots, applies, and registers `restore(old, name)`; `restore`
  re-registers the current state so redo works. A no-op change registers nothing.
- Interactive gestures (drag, draw, live color) use `beginInteractive()`, live updates, then
  `commitInteractive(name:)` for exactly one undo step (`cancelInteractive()` reverts).
- In tests, create the `UndoManager` with `groupsByEvent = false` so each registration is its own undo step.

### Tokens

- Chrome colors come from `BrandColor`, annotation colors from `AnnotationColor`. Hex literals live only in those
  two files (or on lines tagged `lint:allow-hex`); `test-bundle.sh` greps for violations.
- System fonts only, through `Typography` tokens; no font files. Spacing, radius and motion also come from tokens.

### Tool shortcuts

Letters switch tools unless text is being edited or the Text tool is active (type-to-create wins);
Command, Control and Option chords never switch. See `ToolShortcutRouter`. Menu items for tools carry no key
equivalents on purpose (they would fire while typing).

## Conventions

- Feature work on a branch or worktree, never `main`; Conventional Commits; comments in English.
- No secrets in the repo; signing material lives only in the maintainer's keychain, never in GitHub.
- Do not commit local tool directories such as `.boost/`.
