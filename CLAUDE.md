# Skitcho (project guide)

Native Apple-silicon macOS image-annotation editor (Swift 6, SwiftUI + AppKit, macOS 15+). Picture editing only.
User docs are in `README.md`; contributor rules are in `CONTRIBUTING.md`.

## Canonical commands

```bash
swift build --arch arm64
swift test --arch arm64 --no-parallel      # serial only, one test command at a time
swift format lint --strict --recursive Sources Tests
scripts/bundle.sh                          # -> build/Skitcho.app
scripts/test-bundle.sh                     # also: --release-dry-run
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
- `editor` (`EditorModel`) is a `lazy var` created on the main actor by the view; the window view re-binds the
  `UndoManager` from the environment.
- Core `Document` collides with `SwiftUI.Document`: files importing both add `import struct SkitchoCore.Document`.
- Plain images are readable but not writable, so they open untitled-like and Save asks for a `.skitcho`.

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
