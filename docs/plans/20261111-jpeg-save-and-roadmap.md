# Skitcho 0.2.0 — roadmap items + JPEG save by default

## Overview
Roadmap items. All four are in `docs/backlog/` with `worth: yes`. They run first and are independent of the JPEG work:
1. `arrow-head-at-press-point`: the arrowhead sits where the drag starts.
2. `arrow-skitch-style-look`: a bold arrow with a white outline and a soft shadow.
3. `esc-switches-to-select-tool`: Esc returns to the Select tool after ending or cancelling whatever is in progress.
4. `canvas-fit-follows-window-resize`: the picture refits when the window or canvas changes size.
   - Fit mode is on by default.
   - A manual zoom turns it off; ⌘9 turns it back on.
   - Fit never exceeds 100% (maintainer decision).

JPEG save by default (maintainer request, 2026-11-11). This part runs last:
- ⌘S saves a flattened JPEG (picture plus annotations, quality 90%) by default.
- The editable `.skitcho` format stays available as the second choice.
- ⌘S on an opened JPG overwrites it in place.
- A JPEG file changes only when the user explicitly saves; it is never autosaved.

Release: version **0.2.0**, built locally and notarized. Publishing waits for the maintainer's manual test.

The maintainer is away and asked for autonomous execution. Decisions not settled here are made by the executor and logged as `[decision]`.

## Context (from discovery and plan review, evidence on this machine: Xcode 27.2, MacOSX27.2.sdk)
- SwiftUI's private `SwiftUI.PlatformDocument` / `FileWrapperPlatformDocument` hard-codes `+autosavesInPlace == true` and `preservesVersions == true` (runtime ObjC introspection).
- SwiftUI's swiftinterface has **no autosave API**: zero `autosav` matches in SwiftUI or SwiftUICore.
- `NSDocumentController.autosavingDelay` covers only legacy periodic autosave, not autosave-in-place on close, quit or deactivate.
- ⇒ Any type listed in `writableContentTypes` can be silently autosaved in place. **Rule: never add `.jpeg` (or any lossy image type) to `writableContentTypes`.**
- `FileDocumentWriteConfiguration` has no public init, so `fileWrapper(snapshot:configuration:)` cannot be called from tests with a JPEG configuration.
- `UTType.skitchoDocument` lives in `Sources/SkitchoUI/Document/UTType+Skitcho.swift`, which Core cannot see.
- `SkitchoDocument`:
  - `readableContentTypes = [.skitchoDocument, .image]`, `writableContentTypes = [.skitchoDocument]`; both stay.
  - `snapshot` is `nonisolated` and reads the `SavableDocumentStore`.
  - `fileWrapper` is `nonisolated` and uses `PackageCodec`. The 0.1.1 crash fix must not regress.
- Arrow:
  - `ArrowPath.make` (current: head 3w, headHalf 0.6·head, base half `max(0.25w, tail)`, tail `max(0.08w, 1.5)`), drawn by `DocumentRenderer` with a shared soft shadow.
  - Only `ShapeToolController.kind(for:from:to:)` creates arrows.
  - Every other consumer preserves `start`/`end` order: `HandleLayout.moveEndpoint`, `ImageOps` remap, `Element` transform, `EditorModel` double-head toggle. Bounds and hit-testing use the symmetric polygon.
- Esc while editing text: the first responder is `TextEditorOverlay` (NSTextView). Esc arrives at its `cancelOperation(_:)` → `onCommit`, never at `CanvasView.handleKey`. Stamp labels use the same overlay. `ToolShortcutRouter` returns nil for Esc (not a `.character`).
- Zoom:
  - `CanvasScrollView.layout()` already runs on every viewport change. It calls `zoomToFit()` once (guarded by `didInitialFit`) and `updateFrameSize()`.
  - `zoomToFit` uses `setZoom`.
  - `editorDidChange` detects `canvasSize` changes (`lastCanvasSize`).
  - The bottom-bar percentage button calls `actualSize`.
  - ⌘9 and the bottom-bar fit button reach `CanvasHandle.zoomToFit` via `EditorCommandModel`.

## Development Approach
- **testing approach:** TDD for geometry and the JPEG writer; regular code-first plus tests for UI controllers. Every task includes its tests.
- **Branches:** LOCAL branch `feat/jpeg-save-and-roadmap` only. Never push; only the orchestrator pushes `main`, after review.
- **Commands** (serial, never two test processes at once):
  - `swift build --arch arm64` with zero project warnings
  - `swift test --arch arm64 --no-parallel`
  - `swift format lint --strict --recursive Sources Tests`
  - `scripts/test-bundle.sh`
- SwiftPM, the scripts and `git commit` need the agent sandbox disabled. Never run `open`.
- **Commits:** Conventional Commits, no trailers, one logical change each. Never commit `.boost/`.
- When a task lands a roadmap item, `git rm` its `docs/backlog/<slug>.md` **in the same commit**.
- **CRITICAL: all tests must pass before the next task.** Update this plan if scope changes.

## Testing Strategy
- Unit tests for every task. No GUI e2e exists, and agents cannot run the GUI. Runtime save-panel and NSDocument behaviour is listed under Post-Completion manual checks.
- Pixel tests use `RendererShapeTests` helpers (sRGB RGBA8, shadows off unless a test checks the shadow).
- UI controller tests call controllers and `CanvasView` methods directly (`@MainActor`). Viewport tests use `makeScrollView`, `setFrameSize` and `layoutSubtreeIfNeeded()`; no window is needed.

## Progress Tracking
- Mark completed items `[x]` immediately. Prefix new tasks with ➕ and blockers with ⚠️.

## Solution Overview
- **Roadmap items:** small, contained changes in the canvas, controllers and arrow geometry/renderer (details below).
- **JPEG save — chosen design (A, safe; decided autonomously because the maintainer is away, logged as `[decision]`):**
  - The document's writable types stay `[.skitchoDocument]`. AppKit can therefore never autosave or overwrite a JPEG.
  - The File menu's save group (`CommandGroup(replacing: .saveItem)`) is replaced by a main-actor `SaveCoordinator` per window. It calls the window's `NSDocument` directly (never `NSApp.sendAction`). The full rules are in **Technical Details › SaveCoordinator**; this is the summary:
    - **⌘S on an opened JPG** overwrites that file with the flattened JPEG. The URL is read at save time; if no URL is available, ⚠️ the panel is shown instead.
    - **⌘S on an untitled document or another image type (PNG, HEIC, …)**, and **Save As… (⇧⌘S) everywhere**, show our panel: **JPEG** (default), **Skitcho (editable)**.
      - Choosing JPEG writes the file, and later ⌘S overwrites it, except on a `.skitcho` document, where it writes a copy.
      - Choosing Skitcho hands off to `nsDocument.save(to:ofType:for: .saveAsOperation)`, which uses the unchanged nonisolated `snapshot`/`fileWrapper`.
    - **`.skitcho` documents:** ⌘S → `nsDocument.save(nil)`. Autosave stays on for them, because the format is lossless and editable.
  - **Known deviation, logged ⚠️ for the maintainer:**
    - `.skitcho` documents are still autosaved.
    - Closing a *dirty* image-backed window shows AppKit's own "Save changes?" sheet, whose save path offers Skitcho only.
    - Neither ever overwrites the original image.
  - The JPEG encoder is the pure function `SaveFormat.jpegData(for:)` → `Exporter`. It can be called off the main actor and is unit-tested. The coordinated file replacement happens in the main-actor `SaveCoordinator`.

## Technical Details
- `SaveFormat` (SkitchoUI, `Sources/SkitchoUI/Document/SaveFormat.swift`):
  - `enum SaveFormat { case jpeg, skitcho }`, with `jpegQuality = 0.9`, the file extension and `UTType`.
  - `static func jpegData(for: Document) throws -> Data`, which calls `Exporter` at 1×. Flatten or size errors map to a thrown error carrying a readable message (`ErrorMessages`).
- `SaveCoordinator` (SkitchoUI, `@MainActor`, one per window):
  - **NSDocument access:** resolve the window's NSDocument once per command with `NSDocumentController.shared.document(for: window)` (fallback `window.windowController?.document`). Call it directly (`save(nil)`, `save(to:ofType:for:completionHandler:)`, `duplicate(nil)`, `revertToSaved(nil)`, …), never through `NSApp.sendAction`. Use completion handlers; never block the main thread, because SwiftUI saves asynchronously and calls `snapshot` on a worker.
  - **Opened-JPEG URL:** read at save time, never cached at init or in the coordinator. `nsDocument.fileURL` is the primary source; the configuration URL is a fallback only, since it is captured when the view body runs. Use `nsDocument.fileURL`, else `ReferenceFileDocumentConfiguration.fileURL` (pass `file.fileURL` from `DocumentGroup` into `EditorWindowView`). Accept it only when its `UTType` or the document's `fileType` conforms to `.jpeg`.
  - **⚠️ When both URLs are nil at runtime:** SwiftUI may treat opened images as untitled, and there is no supported way to recover the URL (`FileDocumentReadConfiguration` has no URL). ⌘S then shows the JPEG-default panel. This is logged for the maintainer and checked in Post-Completion.
  - **`save()` precedence:**
    1. NSDocument `fileType` is `.skitcho` and `fileURL != nil` → `nsDocument.save(nil)`.
    2. Otherwise, a JPEG target exists (`jpegTarget`, or the opened JPEG URL) → JPEG write.
    3. Otherwise → `saveAs()`.
  - **`saveAs()`** always uses our panel, with JPEG preselected and Skitcho second:
    - JPEG on a `.skitcho` document writes a **copy** and does not retarget, so ⌘S keeps saving `.skitcho` (`[decision]`).
    - JPEG on an image or untitled document writes and sets `jpegTarget`.
    - Skitcho → `nsDocument.save(to:ofType: skitcho, for: .saveAsOperation)` and clears `jpegTarget`.
  - **JPEG write:**
    - Commit any active text edit first (main actor; the live string must be saved), then flatten `editor.document`.
    - Write through `NSFileCoordinator(filePresenter: nsDocument)` with `.forReplacing`, so the document's own presenter is excluded and no auto-revert can discard the vectors.
    - Write to a temp file on the same volume (`FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)`). Then, inside the coordinator's accessor and using the URL it passes in, call `FileManager.replaceItemAt(_:withItemAt:)`, which keeps the creation date and xattrs.
    - Then set `nsDocument.fileModificationDate` to the new file's date and call `updateChangeCount(.changeCleared)`.
    - Errors surface through `ErrorMessages` and leave the document dirty.
  - **Panel:** `NSSavePanel` with an accessory popup built from the `Typography`/`Spacing`/`BrandColor` tokens (system font). Changing the popup updates `allowedContentTypes` and the extension. The default name comes from the document's display name.
  - Overwriting an opened JPEG drops EXIF/GPS metadata and stores sRGB. Log as `[decision]` and note it in the README.
  - Injected seams for tests: `presentPanel`, `writer`, and a document resolver that returns a test `NSDocument` subclass. No protocol wrapper over NSDocument.
- **Commands:** `Sources/Skitcho/Commands.swift` replaces `.saveItem`, whose swiftdoc lists Close, Save, Save As/Duplicate and Revert to Saved. Re-add all of them explicitly, routed to the key window through `EditorCommandModel`:
  - Close (⌘W) → `NSApp.keyWindow?.performClose(nil)`, routed **outside** `EditorCommandModel` and enabled whenever any window is key, so it keeps working in the About and Settings windows
  - Save (⌘S) → coordinator `save()`
  - Save As… (⇧⌘S) → coordinator `saveAs()`
  - Duplicate (no shortcut, `[decision]`: ⇧⌘S is Save As) → `nsDocument.duplicate(nil)`, enabled for every document window, including image-backed ones
  - The items are defined as a small table in SkitchoUI: title, key equivalent and enablement rule, on `EditorCommandModel` or a static `FileMenuItems`. `Commands.swift` only renders that table, and tests check it.
  - Revert to Saved → `revertToSaved(nil)`
  - Rename… / Move To… → `rename(nil)` / `move(nil)`
  - Revert, Rename and Move are enabled only for `.skitcho` documents with a `fileURL`.
- Arrow direction:
  - Keep `kind(for:from:to:)` geometry for `.line`.
  - For `.arrow`, construct `.arrow(start: to, end: from)`: the head (`end`) is at the press point and the tail follows the drag.
  - Shift snap and minimum length are measured from the press point.
  - With Option (from center), the press point is the center: the same swap applies, so the head is on the side opposite the drag (documented, tested).
- Arrow look:
  - Target constants: head length `4w` (cap 0.4·L kept); head half-width `0.7 × head`; swept barbs (barb x = head base − 0.15·head); shaft half-width at the head base `0.45w`; tail half-width `0.15w`, with a round cap.
  - The double-headed variant gets the same retune.
  - Outline: stroke the arrow path in white under the fill, with `lineWidth = 2 × max(1.5, 0.12w)` and `.round` join and cap (no miter spike on the tip).
  - Fill on top. One shadow for outline and fill together, drawn through a transparency layer.
  - Pad `baseBounds`/hit/invalidation by the outline width.
- Esc:
  - (1) **Text overlay:** add an `onEscape` path to `TextEditorOverlay.cancelOperation`. The canvas commits as today, makes itself first responder, then sets `currentTool = .select`. This also covers stamp labels.
  - (2) **Canvas `handleKey`:** after the active controller handles Esc (cancelling a gesture, crop or pixelate), set `currentTool = .select` if it is not already Select.
  - **Leaving a non-Select tool keeps the current selection** (decision). Only Esc *on* Select clears the selection.
  - `ToolShortcutRouter` is unchanged.
- Fit mode:
  - `CanvasView.fitMode` (default true).
  - `CanvasScrollView.layout()`: while `fitMode`, call `canvas.zoomToFit()` (this replaces the `didInitialFit` one-shot); otherwise call `updateFrameSize()` as today.
  - `fitMode = false` only in `zoomIn`, `zoomOut`, `actualSize` and `magnify(with:)`. Never set it inside `setZoom`.
  - Public `zoomToFit()` sets it to true.
  - In fit mode, `editorDidChange` also refits when `canvasSize` changes (crop, rotate, resize, undo). Do NOT refit when only `bottomReserve` changes, because the crop bar appearing would rezoom mid-drag.
  - The bottom bar shows `Fit · 63%` while in fit mode, and the accessibility label matches.

## What Goes Where
- **Implementation Steps:** code, tests, docs in this repo.
- **Post-Completion:** manual GUI checks by the maintainer, then publishing 0.2.0.

## Implementation Steps

### Task 1: Arrowhead at the press point

**Files:**
- Modify: `Sources/SkitchoUI/Canvas/ShapeToolController.swift`
- Modify: `Tests/SkitchoUITests/ShapeToolTests.swift` (+ `HandleTests.swift` if affected)
- Delete: `docs/backlog/arrow-head-at-press-point.md`

- [x] the arrow tool builds `.arrow(start: dragPoint, end: pressPoint)`; `.line` unchanged; Shift snap and minimum length pivot on the press point; Option rule as in Technical Details
- [x] write tests:
  - drag P→Q gives `end == P` and `start == Q`
  - the Shift snap angle is measured at P
  - a too-short drag is still a no-op
  - Option-from-center places the head opposite the drag
  - the double-headed toggle still works
  - handle drag on the head end moves `end`
- [x] `git rm docs/backlog/arrow-head-at-press-point.md` in this task's commit
- [x] run tests — must pass before task 2

### Task 2: Bold outlined arrow

**Files:**
- Modify: `Sources/SkitchoCore/Geometry/ArrowPath.swift`, `Sources/SkitchoCore/Render/DocumentRenderer.swift`, `Sources/SkitchoCore/Model/Element.swift` (bounds padding)
- Modify: `Tests/SkitchoCoreTests/GeometryTests.swift`, `Tests/SkitchoCoreTests/RendererShapeTests.swift`
- Delete: `docs/backlog/arrow-skitch-style-look.md`

- [x] apply the target constants (head 4w capped at 0.4·L, headHalf 0.7·head, swept barbs, base half 0.45w, tail half 0.15w with a round cap) to single- and double-headed arrows, with the constants in one documented place
- [x] keep `ArrowPath.minimumLength` at 9w: decouple it from the head factor (`[decision]`), so Task 1's minimum-length test still holds
- [x] render the white round-join outline under the fill, with one shared shadow; pad bounds by the outline
- [x] write a test that a short double-headed arrow has no self-intersecting outline
- [x] write geometry tests that pin the new numbers: head half-width, base half-width, tail half-width, barb sweep, cap at 0.4·L, symmetry, zero length
- [x] write render tests: white outline pixels just outside the fill edge on a dark background; fill colour inside; no spike past the tip by more than the outline width; shadow present when enabled
- [x] `git rm docs/backlog/arrow-skitch-style-look.md` in this task's commit
- [x] run tests — must pass before task 3

### Task 3: Esc returns to the Select tool

**Files:**
- Modify: `Sources/SkitchoUI/Canvas/TextEditorOverlay.swift`, `Sources/SkitchoUI/Canvas/TextToolController.swift` (if needed), `Sources/SkitchoUI/Canvas/CanvasView.swift`
- Modify: tests in `Tests/SkitchoUITests` (TextTool, Shape, Crop, Pixelate, Commands or a new `EscapeTests.swift`)
- Delete: `docs/backlog/esc-switches-to-select-tool.md`

- [x] overlay Esc: commit as today, return first responder to the canvas, switch to Select (covers stamp labels)
- [x] canvas Esc: after the active controller's own Esc, switch to Select when not already on it; leaving a non-Select tool keeps the selection; Esc on Select clears it (as today)
- [x] write tests, through the real paths (`overlay.cancelOperation(nil)` via the canvas, and `canvas.handleKey` with an Esc event or the existing key seam):
  - text editing → committed + Select
  - stamp label editing → committed + Select
  - mid-drag shape → cancelled, no element, + Select, and later drags/mouse-up create nothing and don't crash
  - pending pixelate → cancelled + Select
  - pending crop → cancelled + Select
  - on Select → selection cleared
  - arrow tool with a selection → Select and the selection is kept
- [x] `git rm docs/backlog/esc-switches-to-select-tool.md` in this task's commit
- [x] run tests — must pass before task 4

### Task 4: Fit mode follows window and canvas size

**Files:**
- Modify: `Sources/SkitchoUI/Canvas/CanvasView.swift` (incl. `CanvasScrollView`), `Sources/SkitchoUI/Panels/EditorWindowView.swift` (label)
- Modify: `Tests/SkitchoUITests/CanvasMappingTests.swift`
- Delete: `docs/backlog/canvas-fit-follows-window-resize.md`

- [x] add `fitMode` (default on); `CanvasScrollView.layout()` refits while it is on (replacing `didInitialFit`); cap 100%, centred, margin and the current reserve included
- [x] `fitMode = false` only in `zoomIn`/`zoomOut`/`actualSize`/`magnify`; `zoomToFit()` sets it true; in fit mode, refit on `canvasSize` change but not on `bottomReserve`-only changes
- [x] the bottom-bar label shows `Fit · NN%` in fit mode, with a matching accessibility label
- [x] in `layout()`, skip `setZoom` when the fitted zoom is within 1e-9 of the current zoom, so `onZoomChange`/SwiftUI cannot churn during a live resize; tests touching `editorDidChange` (which runs from an async Task) must yield or await
- [x] write tests:
  - scroll view resize in fit mode changes the zoom and never exceeds 1.0
  - after `zoomIn` or `actualSize` (the percentage button), a resize keeps the zoom
  - `zoomToFit()` re-enters fit mode
  - in fit mode, a canvas size change (crop/rotate/resize, and their undo) refits
  - the crop bar appearing does not change the zoom
  - `zoomToFit` itself does not clear fit mode
- [x] `git rm docs/backlog/canvas-fit-follows-window-resize.md` in this task's commit
- [x] run tests — must pass before task 5

### Task 5: JPEG writer and save formats (pure part)

**Files:**
- Create: `Sources/SkitchoUI/Document/SaveFormat.swift`
- Create: `Tests/SkitchoUITests/SaveFormatTests.swift`
- Create: a test pinning the autosave fact (read-only introspection)

- [ ] `SaveFormat` (`.jpeg` default first, `.skitcho`), `jpegQuality = 0.9`, `jpegData(for:)` via `Exporter` at 1×, with errors mapped to readable messages
- [ ] write tests:
  - JPEG decodes, has the canvas size and has annotation pixels flattened in
  - an oversized canvas throws, no crash
  - `jpegData` works when called from `DispatchQueue.global()` (off the main actor)
  - `writableContentTypes` is still exactly `[.skitchoDocument]` — already pinned by `DocumentSpikeTests.writableTypesAreSkitchoOnly`; reference it, do not duplicate
- [ ] write a read-only introspection test: `NSClassFromString("SwiftUI.PlatformDocument")` responds `autosavesInPlace == true`. It documents why JPEG must not be a writable type and fails loudly if Apple changes it (skip if the class is absent)
- [ ] run tests — must pass before task 6

### Task 6: SaveCoordinator logic (JPEG default, Skitcho handoff, safe overwrite)

**Files:**
- Create: `Sources/SkitchoUI/Document/SaveCoordinator.swift`
- Modify: `Sources/SkitchoUI/Panels/EditorWindowView.swift`, `Sources/Skitcho/SkitchoApp.swift` (pass `file.fileURL`), `Sources/SkitchoUI/Document/SkitchoDocument.swift` (only if needed)
- Create: `Tests/SkitchoUITests/SaveCoordinatorTests.swift`

- [ ] implement `SaveCoordinator` exactly as described in Technical Details:
  - direct NSDocument resolution
  - URL read at save time
  - `save()` precedence and `saveAs()` rules
  - JPEG write: commit the text edit, presenter-excluded coordination, `replaceItemAt`, `fileModificationDate`, `.changeCleared`
  - Skitcho handoff via a completion handler
  - injected panel, writer and document seams
- [ ] write tests with a test `NSDocument` subclass that records `save(_:)`/`saveAs(_:)`/`save(to:ofType:for:completionHandler:)` and presents a temp file, and a stubbed panel:
  - opened JPEG + `save()` overwrites that file with a decodable flattened JPEG; `isDocumentEdited == false`; `fileModificationDate` equals the file's date
  - opened JPEG with both URLs nil → panel with JPEG preselected (the ⚠️ fallback)
  - untitled + `save()` → panel; choosing JPEG writes and sets the target; the next `save()` writes without a panel
  - choosing Skitcho → save-as handoff with the skitcho type, `jpegTarget` cleared
  - `.skitcho` document: `save()` → `save(nil)`; `saveAs()` + JPEG writes a copy, and the next `save()` still → `save(nil)`
  - opened PNG: `save()` shows the panel and the PNG bytes are unchanged
  - ⌘S during a text edit saves the live string
  - a write failure leaves the document dirty and shows the readable message
- [ ] run tests — must pass before task 7

### Task 7: Save panel accessory and File menu

**Files:**
- Create: `Sources/SkitchoUI/Panels/SaveFormatAccessoryView.swift`
- Modify: `Sources/Skitcho/Commands.swift`, `Sources/SkitchoUI/Panels/EditorCommandModel.swift`
- Modify: `Tests/SkitchoUITests/CommandsTests.swift`

- [ ] add the accessory popup (JPEG default, Skitcho) using the project tokens; changing it updates `allowedContentTypes` and the extension; wire it into the coordinator's real `presentPanel`
- [ ] replace `.saveItem` and re-add Close ⌘W, Save ⌘S, Save As… ⇧⌘S, Duplicate (no shortcut), Revert to Saved, Rename… and Move To…, routed to the key window, with enablement as in Technical Details
- [ ] write tests:
  - the File-menu table exposes all re-added items with the right shortcuts
  - Close is enabled when a non-document window (About/Settings) is key
  - enablement: Revert, Rename and Move only for saved `.skitcho` documents; Save and Save As for every document window
  - the popup changes the allowed type and extension
- [ ] run tests — must pass before task 8

### Task 8: Verify acceptance criteria
- [ ] every Overview item is implemented and tested; `docs/backlog/` no longer holds the 4 items
- [ ] full `swift test --arch arm64 --no-parallel` (all three passed lines), zero project warnings, lint, `scripts/test-bundle.sh`, `scripts/test-bundle.sh --release-dry-run`, `scripts/test-workflows.sh`
- [ ] the save paths never touch main-actor state off-main: `snapshot`/`fileWrapper` are unchanged and nonisolated; `SaveCoordinator` is main-actor only; `writableContentTypes == [.skitchoDocument]`
- [ ] manual GUI check deferred to the maintainer (`open` is blocked for agents)

### Task 9: [Final] Update documentation
- [ ] README:
  - save behaviour: JPEG default, the Skitcho option, an opened JPG is overwritten only on ⌘S, a reopened JPEG is flat, EXIF/GPS is dropped and colours are stored as sRGB, and `.skitcho` documents autosave
  - Esc in the shortcuts table
  - fit to window in the canvas table
  - the arrow drawing direction in Quick start
- [ ] CLAUDE.md: replace line ~53 ("Plain images are readable but not writable…") with the new save design and the rule "never add a lossy image type to `writableContentTypes` (SwiftUI hard-codes autosave-in-place)"; add fit mode
- [ ] move this plan to `docs/plans/completed/` (orchestrator, after reviews)

## Post-Completion
*Items requiring manual intervention or external systems — no checkboxes, informational only*

The maintainer installs the locally built, notarized `Skitcho-0.2.0.dmg` and checks:
- **Opened JPG:** draw, then ⌘S — the file is overwritten with the annotations, and the dot clears. Draw again, close without saving, and choose Don't Save — the JPG is unchanged.
- **New picture or opened PNG:** ⌘S shows the panel with JPEG preselected. Choosing Skitcho creates an editable `.skitcho` file.
- **⇧⌘S:** Save As works from any document.
- **Arrow:** the head is at the press point; the bold white-outlined look.
- **Esc:** returns to Select, including while typing text.
- **Window resize:** refits the picture until you zoom manually; ⌘9 resumes fitting.
- **After ⌘S on an opened JPG:**
  - Did it overwrite in place, or show the panel (the ⚠️ fallback)?
  - Keep editing for 10+ seconds and switch apps: the annotations stay editable, nothing reverts, and no "changed by another application" alert appears.
- **⌘S while typing text:** the typed text is saved.
- **`.skitcho` document:** ⌘W closes; Duplicate, Revert to Saved and Rename work.
- **⌘W in About and Settings:** still closes those windows.

After the maintainer says go: tag `v0.2.0` on the tested `main` commit, then `gh release create` with the DMG and appcast. This is not a first release, so the feed merge and version guards apply.
