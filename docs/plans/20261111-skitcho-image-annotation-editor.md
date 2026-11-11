# Skitcho — native macOS image annotation editor

## Overview
- Build **Skitcho**, a native macOS app (Swift 6, SwiftUI shell + AppKit canvas) for annotating pictures: open an image, draw arrows/shapes/text/stamps/freehand marks, pixelate, crop/resize/rotate, then save or export.
- Problem: the reference app (Skitch 2.9, x86_64, Evernote-bound, abandoned) mixes a good annotation editor with capture, sync and account features. The user needs **only the picture-editing part**, rebuilt as a modern native app.
- **Apple silicon native (hard requirement)**: every Mach-O in the shipped app (the main binary plus the embedded Sparkle framework and its helpers) is thin `arm64`. There is no x86_64 slice, no universal binary and no Rosetta. Enforcement:
  - the binary is built thin
  - every Mach-O in the bundle is thinned
  - a `lipo -archs` assert runs on every Mach-O after codesign
  - an in-process smoke test checks that the process is not translated
- **Open source**: MIT license, public repo `github.com/oleggohman/skitcho`. The repo holds no secrets and no non-redistributable assets.
- **Auto-update from GitHub Releases** via Sparkle 2. Updates are EdDSA-signed, and `appcast.xml` is published as a release asset. A tag push triggers GitHub Actions (arm64 runner) to build, Developer ID-sign and notarize.
- **CloudZone design system** for app chrome: palette tokens, type scale and weights, spacing, radii, button variants, transitions. **System fonts only (SF Pro via `.system`). No custom or bundled fonts**, by user decision. This overrides the design system's Landour/Wix Madefor rule.
- **Out of scope**:
  - screen capture, timed snap, camera
  - Evernote login/sync/sharing/library
  - PDF annotation
  - analytics
  - polygon tool, embedded bitmap layers, "funny" emoticon stamps
- Clean-room: the reference was inspected with REA (Hopper provider) only to list features and default parameters. No code, nibs or image assets are copied. Icons are SF Symbols (UI only) or our own vector geometry.

## Context (from discovery)
- Repo: `/Users/oleggohman/Documents/GenAIProjects/SKITCHO` is empty (git init only). Work happens on branch `feat/image-annotation-editor`.
- Toolchain: Swift 6.4.2, Xcode 27.2, macOS 27.2 SDK, arm64 host. `swift format` 6.4 is used for lint. No xcodegen/tuist/swiftlint.
- Verified in the reviewer spike on this machine:
  - SwiftPM uses the **Swift Build backend**, so the release product path comes from `swift build -c release --arch arm64 --show-bin-path` (currently `.build/out/Products/Release`). Never hard-code it.
  - `ReferenceFileDocument` is `Sendable` in this SDK. The pattern that compiles is `@MainActor final class X: @preconcurrency ReferenceFileDocument`.
  - `CGPath` is **not** Sendable. `CGImage` and `CGAffineTransform` are fine.
  - A `@MainActor @Observable` model compiles with `UndoManager.registerUndo(withTarget:handler:)`.
  - `@testable import` works.
  - Offscreen `NSView.cacheDisplay` works under `swift test --no-parallel`.
  - `swift build`/`swift test` **fail inside the agent sandbox** because module cache and swift-build service writes are blocked. Executors must run SwiftPM commands with the sandbox disabled.
- Reference findings (REA evidence on `Skitch.app/Contents/MacOS/Skitch`, sha256 `02d7c867…`):
  - Document model (`SkitchDOM*`) with element kinds Arrow, Line, Rectangle, Ellipse, Polygon, Vector, Text, Stamp, Bitmap. Every element supports transform/translate/rotate/scale, hit testing, JSON serialization and tool color, and stores **absolute tool size** (`toolSizeAbsolute`), converting from relative size at creation.
  - Sizes (`+[SkitchPropertySize relativeToolSizeFromSkitchPropertySizeID:]`, table `0x1004ab0d0`): relative **[0.2, 0.4, 0.6, 0.8, 1.0]**, default **0.6**. Highlighter defaults to yellow.
  - Arrow (`+[SkitchDOMArrow makeArrowPathFromPoint:toPoint:arrowSize:]`): one closed filled path whose shaft tapers into a triangular head. The head grows with size and is capped at **0.4 × length**; shaft half-width is `max(size·0.08, 1.5)`. There is a minimum length and an optional head at the start.
  - Freehand: a live low-pass filter, then corner detection plus recursive cubic bezier fitting.
  - Text: styled outline ("bubble") vs plain, wrap width, in-place editing, type-to-create.
  - Stamps: approve/reject/question/attention/perfect with a tail and an attached label.
  - Image tools: pixelate (region + block size), crop (grid, W×H), resize (proportion link), expand canvas, rotate, flip, with a max-size guard.
  - Export: PNG/JPEG(quality)/TIFF and retina 2×, plus copy and drag-out. Undo uses named actions.
- Dependencies: Sparkle 2 (MIT, SwiftPM binary target, `Skitcho` executable only). Everything else is Apple frameworks.

## Development Approach
- **testing approach**: TDD for SkitchoCore (model, geometry, raster ops, render, export, editor commands) and theme token tables. Code-first plus tests for UI controllers (point-based, no NSEvent) and scripts.
- complete each task fully before moving to the next; small focused changes
- **CRITICAL: every task MUST include new/updated tests**, covering success and error/edge cases
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- canonical commands (arm64 always explicit; never pass more than one `--arch`):
  - build `swift build --arch arm64`
  - test `swift test --arch arm64 --no-parallel` (serial only; never two test processes at once)
  - lint `swift format lint --strict --recursive Sources Tests`
  - bundle `scripts/bundle.sh`
  - bundle checks `scripts/test-bundle.sh`
- **sandbox**: SwiftPM, codesign and lipo commands need the agent sandbox disabled (module cache / swift-build writes). Run the app only as `build/Skitcho.app`, because it needs Info.plist for UTIs and the regular activation policy. `swift run` is unsupported. Launching the app (`open`) is a user-run step.
- comments in English. Colors come only from `BrandColor` (chrome) and `AnnotationColor` (content); a lint check rejects hex literals elsewhere.
- never commit secrets (certificates, API keys, Sparkle private key)

## Testing Strategy
- **Core unit tests** (Swift Testing) in `Tests/SkitchoCoreTests`. Pixel tests render into an explicit sRGB RGBA8 premultiplied `CGContext` with `shadows: false`, sample away from anti-aliased edges and use a ±2 tolerance. Fixtures (e.g. EXIF-rotated JPEG) are generated in-test with `CGImageDestination`, never committed.
- **UI tests** in `Tests/SkitchoUITests`, `@MainActor`. Tool controllers take document-space points plus modifier flags, so tests call them directly with no NSEvent or window. Coordinate mapping is tested at several zoom levels. At most one optional test hosts a view in an offscreen borderless `NSWindow`.
- **Bundle tests**: `scripts/test-bundle.sh` asserts:
  - bundle structure and Info.plist keys
  - every Mach-O is `arm64` only
  - `codesign --verify --deep --strict` passes
  - no hex literals outside the two token files
  - no font files in the repo/bundle
- **Coverage**: Core line coverage ≥ 80% via `swift test --arch arm64 --no-parallel --enable-code-coverage`, then `xcrun llvm-cov report` on the reported profdata. If it falls short, add Core tests until it passes.
- No e2e UI framework. Manual UI walkthrough is in Post-Completion.

## Progress Tracking
- mark completed items with `[x]` immediately; ➕ for new tasks; ⚠️ for blockers; keep plan in sync

## Solution Overview
- **SwiftPM, three targets** (no Xcode project):
  - `SkitchoCore` (library, **no AppKit**: CoreGraphics/CoreText/ImageIO/UniformTypeIdentifiers/Foundation only): model, geometry, renderer, raster ops, codecs, editor state and commands, clipboard **Data** encoding.
  - `SkitchoUI` (library): CloudZone `Theme`, `SkitchoDocument`, `CanvasView` + tool controllers, SwiftUI panels, pasteboard bridge.
  - `Skitcho` (executable): `@main` App, `DocumentGroup`, `Commands`, Sparkle `UpdaterController`. Only this target links Sparkle.
- **Why an AppKit canvas inside SwiftUI**: AppKit gives precise mouse/keyboard handling, cursors, NSTextView in-place editing and file-promise drag-out. SwiftUI keeps the shell, toolbar, menus and panels simple.
- **Non-destructive editing**: elements are vectors over a base bitmap until export. Only pixelate, crop, resize, rotate and flip change the bitmap, and they are undoable through document snapshots.
- **File format** `.skitcho`: a package containing `document.json` and `base.png`. A plain image opens as an "untitled-like" document: the first ⌘S asks where to save a `.skitcho`, and the source image is never overwritten.
- **Auto-update**: `SPUStandardUpdaterController` with a "Check for Updates…" menu item and automatic daily checks that can be toggled in Settings.
  - Feed: `https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml`.
  - Sparkle verifies both the EdDSA signature and the Developer ID team.
- **Release pipeline**: a `v*` tag triggers GitHub Actions on an arm64 macOS runner pinned to Xcode 27.x, behind a protected `release` environment. Steps: test → bundle → sign (hardened runtime) → notarize + staple → zip → `generate_appcast` (merged with the previous appcast) → `gh release create`. Separately, `ci.yml` runs build, lint, tests and bundle checks on PRs and pushes.

## Technical Details

### Coordinate system (single rule, all tasks)
- Document space has a **top-left origin, y-down, in image pixels** of the canvas.
- `DocumentRenderer` is the only code that bridges to CoreGraphics y-up. It applies `translateBy(0, canvasHeight)` + `scaleBy(1, -1)` once, and handles the CGImage draw flip and the CoreText text-matrix flip internally.
- `CanvasView` is a flipped NSView. View↔document mapping is `doc = (view − contentOrigin) / zoom`.
- Hit-test tolerance is passed in **document units** (the canvas divides view px by zoom).

### Model (`Sendable`, value types, no CGPath stored)
- `Document`: `baseImage: CGImage`, `canvasSize: CGSize`, `imageOrigin: CGPoint`, `background: AnnotationColor`, `elements: [Element]` (z-order = array order), `version: Int`. It is `Sendable` and `Equatable` (image compared by identity plus size).
- `Element`: `id: UUID`, `kind: ElementKind`, `style: Style`, `rotation: Double` (radians, around `bounds` center; used by rect/rounded/ellipse/text/stamp; 0 for others). **Geometry is stored in document space.** Move, crop and resize edit geometry directly. Rotate90 and flip map points and adjust `rotation`. There is no stored affine transform.
- `ElementKind` cases:
  - `.arrow(start, end, doubleHeaded)`
  - `.line(start, end)`
  - `.rect(CGRect, rounded: Bool)`
  - `.ellipse(CGRect)`
  - `.freehand(segments: [BezierSegment], highlighter: Bool)`, where `BezierSegment` holds 4 `CGPoint`s; raw points exist only in the tool while drawing
  - `.text(TextContent{string, origin, wrapWidth?, styled: Bool})`
  - `.stamp(StampKind, center, tailAngle: Double?, labelID: UUID?)`
- `Style`: `color: AnnotationColor`, `sizeStep: SizeStep`, **`strokeWidth: Double` and `fontSize: Double` frozen at creation** (`SizeStep.relative × base × max(1, imageShortSide/1000)` at that moment). The size picker recomputes them for the selection using the current image. `resize(scale:)` multiplies them. Crop, expand, rotate and flip leave them unchanged.
- `StampKind` cases: approve (✓, green), reject (✗, red), question (?, blue), attention (!, orange), perfect (★, lavender). Glyphs are **drawn geometry only** (CGPath built at render time); SF Symbols are never used in Core.

### Concurrency / document pattern (exact; established in Task 2)
```swift
@MainActor final class SkitchoDocument: @preconcurrency ReferenceFileDocument {
  static let readableContentTypes: [UTType] = [.skitchoDocument, .image]
  static let writableContentTypes: [UTType] = [.skitchoDocument]
  nonisolated let initial: Document             // Sendable value, set by both inits
  lazy var editor = EditorModel(document: initial, undoManager: nil) // @MainActor; created on first main-actor access (from the view)
  nonisolated init(configuration: ReadConfiguration) throws  // decoding only (PackageCodec / ImageImporter); NO main-actor work, NO MainActor.assumeIsolated
  nonisolated init()                            // blank canvas via Document.blank
  func snapshot(contentType: UTType) throws -> Document      // reads editor.document
  nonisolated func fileWrapper(snapshot: Document, configuration: WriteConfiguration) throws -> FileWrapper // pure PackageCodec, never touches editor
}
```
- `DocumentGroup(newDocument: { SkitchoDocument() })` calls the `nonisolated init()`, so there is no isolation warning. `MainActor.assumeIsolated` is forbidden in document code because SwiftUI/NSDocument may read files off the main thread. If the exact form differs on the SDK, Task 2 records the working form here before later tasks start.
- Verified in Task 2: the pattern compiles warning-free as written. Two additions: (1) Core `Document` collides with `SwiftUI.Document`, so any SkitchoUI file importing both SwiftUI and SkitchoCore adds `import struct SkitchoCore.Document` (the `SkitchoCore.Document` qualifier does not work because the `SkitchoCore` marker enum shadows the module name); (2) `DocumentGroup(newDocument:editor:)` is written with both labels (swift-format rejects the trailing-closure form); `SkitchoDocument` exposes a `nonisolated init(initial:)` for tests; tests touching static content types must be `@MainActor`.
- Undo: `EditorModel(document:undoManager:)` takes an `UndoManager?`. `EditorWindowView` re-binds it from `@Environment(\.undoManager)`. `ReferenceFileDocument` dirty state then follows registrations on the window's manager.
  - `perform(_ name: String, _ change: (inout Document) -> Void)` snapshots `old`, applies the change, then registers `{ $0.restore(old, name) }`. `restore` re-registers the current state, so redo works.
  - No-op changes (equal document) register nothing.
  - Gestures use `beginInteractive()` (snapshot, live updates, no registration) and `commitInteractive(name:)`, which registers exactly one step. `cancelInteractive()` reverts.

### Tokens
- **AnnotationColor** (content palette, Core):
  - brand hues: `red` #f96c5d, `orange` #f8a23a, `blue` #2fa8f7, `purple` #5d77f9, `lavender` #af85f5 (CloudZone "pink" token), `navy` #0e1e4d
  - plus `black` and `white`
  - two documented **content-only exceptions**: `yellow` #ffd60a (highlighter default) and `green` #34c759 (approve stamp)
  - `custom(RGBA)`
- **BrandColor** (chrome, SkitchoUI). CloudZone tokens: blue, purple, pink, darkBlue, mutedBlue, white, black, ghostGray, lightestGray, mutedGray, lightGray, mediumGray, darkMutedGray, paleBlue, lightestBlue, lightBlue, mediumBlue, red, orange. Semantic aliases resolve per appearance:
  - light: sidebar `darkBlue` with inverted icons, selected tool `blue`, hover `purple`, canvas surround `paleBlue` (20 pt radius), panels `white` with `ghostGray` border
  - dark: window `darkBlue`, panels `mutedBlue`, text `white`, captions `lightGray`
  - selection handles `blue` with a `white` outline; crop/modal dim is black at 0.4
- **Typography: system font only** (`Font.system` / `NSFont.systemFont`). CloudZone sizes 10/12/14/15/16/20/40 map to tokens `label/caption/bodySmall/input/body/title/largeTitle`. Weights 400/500/600 → `.regular/.medium/.semibold`; body defaults to `.medium`. No font files anywhere.
- Spacing is 4/8/16/24/32/40/48/64/80/96. Radius is tiny 4, medium 16, large 20, pill 40. Motion is 0.1/0.15/0.25/0.35/0.5 s, always ease-in-out.
- `CZButtonStyle` variants: primary (blue, hover purple), secondary (paleBlue, hover lightBlue), transparent, link. Sizes small 24 pt and normal 38 pt. Disabled uses mutedGray. `CZCard` has a 2 pt ghostGray border, radius 20 and padding 32 (24 inside compact panels).

### Tools and interaction
- Tools:
  - V select/pan; A arrow; T text; M marker; H highlighter; R rect; U rounded rect; O ellipse; L line; S stamp; P pixelate; C crop
  - Space-drag pans with any tool
- **Selection rule**: with a drawing tool, mouse-down on the **handle or selected element** of the current selection manipulates it; anywhere else it draws a new element. With V, a click selects the top-most hit, a drag moves it, and a drag on empty space makes a marquee.
- Shortcuts:
  - Delete removes the selection, arrows nudge (Shift ×10), Esc deselects
  - ⌘Z / ⇧⌘Z undo/redo; ⌘C/⌘V copy/paste elements; ⇧⌘C copies the image
  - ⌘+/⌘−/⌘0 zoom; ⌘]/⌘[ bring forward/send backward
  - typing with no text in editing creates text (type-to-create)
- `ImageOps`: `pixelate(rect, blockSize)` (manual block average, clipped), `crop(rect)`, `resize(scale)`, `expandCanvas(edge, amount)`, `rotate90(clockwise)`, `flip(axis)`. A side larger than 16384 px throws `ImageOpError.tooLarge`; an empty or out-of-bounds rect throws `.invalidRect`.
- `Exporter.data(document, format: .png | .jpeg(quality) | .tiff, scale: 1|2)` uses `CGImageDestination`. `ElementClipboard.encode/decode` works on `Data` (Core). The NSPasteboard bridge in SkitchoUI uses type `com.oleggohman.skitcho.elements`, image PNG+TIFF, and `NSFilePromiseProvider` for drag-out.

### Bundle / Info.plist
- `CFBundleIdentifier=com.oleggohman.skitcho`; `LSMinimumSystemVersion=15.0` (= Package.swift platform); `LSRequiresNativeExecution=true`
- `CFBundleDocumentTypes`:
  - `public.image`: role Editor
  - `com.oleggohman.skitcho.document`: Editor, `LSTypeIsPackage=true`
- `UTExportedTypeDeclarations`: `com.oleggohman.skitcho.document`, conforming to `com.apple.package` + `public.composite-content`, extension `skitcho`
- Sparkle keys: `SUFeedURL`, `SUPublicEDKey` (from env `SPARKLE_PUBLIC_ED_KEY`, empty in dev), `SUEnableAutomaticChecks=YES`, `SUScheduledCheckInterval=86400`
- Versions:
  - `CFBundleShortVersionString` comes from tag `vX.Y.Z` (dev: `0.0.0`).
  - `CFBundleVersion` = `git rev-list --count HEAD`, which is monotonic; Sparkle compares it.
  - Without commits, the build version is `0`.
  - CI checkouts use `fetch-depth: 0`, otherwise the count would always be 1.
  - release.sh asserts the build number is greater than the latest published `sparkle:version` in the fetched appcast.
- Icon: generated by `scripts/app-icon.swift` (Task 29). Until then the default icon is used.
- Release secrets (Actions; names match local apple-signer env vars): `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `AppleIDENTITY`, `AppleStoreAPIKey`, `AppleIssuerID`, `ApplePrivateKey`, `SPARKLE_ED_PRIVATE_KEY`. Repo variable: `SPARKLE_PUBLIC_ED_KEY`. Secrets are read only through `env:` and never echoed. A temporary keychain is always deleted.

## What Goes Where
- **Implementation Steps**: code, tests, scripts, workflows and docs in this repo.
- **Post-Completion**: maintainer secrets, repo creation, first release, manual UX walkthrough.

## Implementation Steps

### Task 1: SwiftPM scaffold, open-source files, CI, arm64 bundle script

**Files:**
- Create: `Package.swift`, `Sources/SkitchoCore/SkitchoCore.swift`, `Sources/SkitchoUI/SkitchoUI.swift`, `Sources/Skitcho/SkitchoApp.swift`
- Create: `Tests/SkitchoCoreTests/SmokeTests.swift`, `Tests/SkitchoUITests/SmokeTests.swift`
- Create: `scripts/bundle.sh`, `scripts/test-bundle.sh`, `Resources/Info.plist.template`
- Create: `.swift-format`, `.gitignore`, `LICENSE`, `.github/workflows/ci.yml`

- [x] `Package.swift`:
  - swift-tools 6.0 (Swift 6 mode by default), platform `.macOS(.v15)`, no unsafeFlags
  - targets `SkitchoCore`, `SkitchoUI`, `Skitcho` (executable), `SkitchoCoreTests`, `SkitchoUITests`
  - Sparkle 2 pinned `exact:` to the current 2.x release, linked by `Skitcho` only
- [x] `scripts/bundle.sh` (no `set -x` anywhere; Sparkle embedding is added in Task 28):
  - abort unless `uname -m` = `arm64` and `sysctl -n sysctl.proc_translated` ≠ 1
  - `BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)` after building
  - assemble `build/Skitcho.app` from Info.plist.template with version substitution; copy `*.bundle` from `$BIN_DIR` into `Contents/Resources` only if any exist
  - versions: `CFBundleShortVersionString` = `$VERSION` env or `0.0.0`; `CFBundleVersion` = `git rev-list --count HEAD` if `git rev-parse HEAD` succeeds, else `0` (the repo has no commits yet)
  - sign: ad-hoc `codesign -f -s -` by default, or `$SIGN_IDENTITY` with `-o runtime --timestamp`
  - finally assert `lipo -archs` = `arm64` for **every** Mach-O in the app (including `Contents/MacOS/Skitcho`)
- [x] `scripts/test-bundle.sh`: runs bundle.sh, then asserts:
  - the Info.plist keys from Technical Details
  - every Mach-O is arm64-only
  - `codesign --verify --deep --strict` passes
  - no `*.ttf`/`*.otf` files in the repo or bundle
  - no `#[0-9a-fA-F]{6}` or `Color(hex:` literals in `Sources/` outside `AnnotationColor.swift`/`BrandColor.swift`, unless the line carries `// lint:allow-hex`
- [x] `.swift-format` (2-space, 120 cols); `.gitignore` (`.build/`, `build/`, `dist/`, `.swiftpm/`, `*.p12`, `*.p8`, `*.key`, `.env*`); `LICENSE` MIT "Copyright (c) 2026 Oleg Gohman"
- [x] `ci.yml`, on push/PR: (⚠️ runner `macos-26` is a placeholder: a hosted image with Xcode 27.x was not verified; the Xcode-select step fails loudly if none is present. Revisit when an Xcode 27 image exists)
  - `permissions: contents: read`; `actions/checkout` pinned by commit SHA with `fetch-depth: 0`
  - runner: the newest arm64 GitHub macOS image that ships Xcode 27.x (never an Intel runner)
  - `sudo xcode-select -s` that Xcode, then assert `swift --version` contains `6.4` and `uname -m` = `arm64`. If no hosted image has Xcode 27, record ⚠️ in this plan and gate the warning-free check on the pinned toolchain only
  - steps: build, lint, `swift test --arch arm64 --no-parallel`, `scripts/test-bundle.sh`
- [x] smoke tests: modules import; `#if !arch(arm64)` → `Issue.record`; `sysctl.proc_translated` == 0
- [x] run build, tests, lint and test-bundle. Must pass before task 2.

### Task 2: De-risk spike — DocumentGroup + `.skitcho` package + Swift 6 isolation

**Files:**
- Create: `Sources/SkitchoCore/Model/Document.swift` (minimal Sendable stub: canvasSize, baseImage, elements=[])
- Create: `Sources/SkitchoCore/IO/PackageCodec.swift` (minimal: document.json + base.png)
- Create: `Sources/SkitchoCore/Editor/EditorModel.swift` (minimal `@MainActor @Observable` holding `document`)
- Create: `Sources/SkitchoUI/Document/SkitchoDocument.swift`, `Sources/SkitchoUI/Document/UTType+Skitcho.swift`
- Modify: `Sources/Skitcho/SkitchoApp.swift`, `Resources/Info.plist.template`
- Create: `Tests/SkitchoUITests/DocumentSpikeTests.swift`

- [x] implement the exact pattern from Technical Details › Concurrency, with `DocumentGroup` showing a placeholder view of the image
- [x] the project sources build **warning-free**: `swift build --arch arm64 2>&1 | grep -E '^/.*/Sources/.*\.swift:[0-9]+:[0-9]+: warning:' | wc -l` = 0 (ignore SwiftPM environment/artifact notices). If the pattern needs changes, update Technical Details in this plan.
- [x] write tests: FileWrapper round-trip through `SkitchoDocument.fileWrapper`/`init(configuration:)` equivalents (call PackageCodec + snapshot directly); `writableContentTypes == [.skitchoDocument]`; reading PNG data yields a document. No UTI registry lookups in tests.
- [x] write test: the document decoding path runs from `Task.detached` (off the main actor) without trapping; afterwards, `editor` accessed on the main actor holds the decoded document
- [x] run tests + test-bundle. Must pass before task 3.

### Task 3: Annotation style tokens — colors and sizes

**Files:**
- Create: `Sources/SkitchoCore/Style/AnnotationColor.swift`, `SizeStep.swift`, `Style.swift`
- Create: `Tests/SkitchoCoreTests/StyleTests.swift`

- [x] `AnnotationColor` RGBA table (comment the yellow/green content exceptions), `cgColor`, `luminance`, `contrastingOutline`
- [x] `SizeStep` → relative [0.2…1.0], default 0.6; `Style.make(tool:sizeStep:color:imageSize:)` freezes `strokeWidth`/`fontSize`; per-tool defaults (highlighter yellow)
- [x] write tests: tables, freezing formula at several image sizes, Codable round-trip, contrasting outline
- [x] write tests for edge cases: custom color clamping, unknown size id decodes to default
- [x] run tests. Must pass before task 4.

### Task 4: Geometry kernel — arrow path, shapes, hit testing

**Files:**
- Create: `Sources/SkitchoCore/Geometry/ArrowPath.swift`, `ShapePaths.swift`, `HitTest.swift`, `CGExtensions.swift`
- Create: `Tests/SkitchoCoreTests/GeometryTests.swift`

- [x] `ArrowPath.make(from:to:width:doubleHeaded:) -> CGPath`: tapered shaft, head ≤ 0.4·L, minimum length 3·head
- [x] rect/rounded/ellipse/line paths with rotation about center
- [x] hit testing (tolerance in document units): stroked path, rect intersection, filled interior option
- [x] helpers: distance to segment, rotate about point, 15° snap
- [x] write tests: head cap, symmetry, zero length, hit inside/outside tolerance, snap
- [x] run tests. Must pass before task 5.

### Task 5: Freehand smoothing and bezier fitting

**Files:**
- Create: `Sources/SkitchoCore/Geometry/LowPassFilter.swift`, `BezierFitter.swift`
- Create: `Tests/SkitchoCoreTests/BezierFitterTests.swift`

- [x] low-pass filter (α configurable, drops points within 0.5 doc units)
- [x] Schneider recursive cubic fit (Newton–Raphson reparameterization, corner detection) → `[BezierSegment]`
- [x] write tests: line → 1 segment, circle within tolerance, V corner kept
- [x] write tests for edge cases: 0/1/2 points, duplicates, no NaN
- [x] run tests. Must pass before task 6.

### Task 6: Full document model and `.skitcho` codec

**Files:**
- Modify: `Sources/SkitchoCore/Model/Document.swift`, `Sources/SkitchoCore/IO/PackageCodec.swift`
- Create: `Sources/SkitchoCore/Model/Element.swift`, `StampKind.swift`
- Create: `Tests/SkitchoCoreTests/ModelTests.swift`

- [x] `Element`/`ElementKind`/`TextContent`/`StampKind` per Technical Details (Sendable, Equatable, no CGPath); per-element `bounds`, `hitTest(point:tolerance:)`, `translated(by:)`, `scaled(by:about:)`
- [x] versioned Codable JSON; `PackageCodec` typed errors
- [x] write tests: JSON round-trip for every kind, package round-trip in a temp dir, bounds with rotation
- [x] write tests for errors: missing base.png, future version, corrupt JSON
- [x] run tests. Must pass before task 7.

### Task 7: Renderer — base, shapes, arrows, freehand, flatten

**Files:**
- Create: `Sources/SkitchoCore/Render/DocumentRenderer.swift`
- Create: `Tests/SkitchoCoreTests/RendererShapeTests.swift`

- [x] `draw(document, in:, scale:, excluding:, shadows:)` applies the single y-flip rule. It draws the background and base image at imageOrigin, then shapes/arrows/freehand with an optional soft shadow; the highlighter uses multiply blend at 0.4 alpha
- [x] `flatten(document, scale:) -> CGImage` (sRGB RGBA8)
- [x] write tests: **orientation** (image with red top-left quadrant renders red at output top-left), stroke pixel color, interior untouched, highlighter darkens without replacing, 2× dimensions
- [x] run tests. Must pass before task 8.

### Task 8: Renderer — text

**Files:**
- Create: `Sources/SkitchoCore/Render/TextRenderer.swift`
- Modify: `Sources/SkitchoCore/Render/DocumentRenderer.swift`
- Create: `Tests/SkitchoCoreTests/RendererTextTests.swift`

- [x] CoreText framesetter with the system font (content stays independent of installed fonts); styled = outline (contrasting color, width ∝ fontSize) under fill; plain = fill only; wrap width; `TextRenderer.size(for:)`
- [x] write tests: measure grows with string and wraps at wrapWidth, glyphs are not mirrored (ink bounding box above baseline in document space), styled draws the outline color at the glyph edge
- [x] run tests. Must pass before task 9.

### Task 9: Renderer — stamps

**Files:**
- Create: `Sources/SkitchoCore/Render/StampRenderer.swift`
- Modify: `Sources/SkitchoCore/Render/DocumentRenderer.swift`
- Create: `Tests/SkitchoCoreTests/RendererStampTests.swift`

- [x] badge circle plus drawn glyph paths (✓ ✗ ? ! ★), optional tail triangle at `tailAngle`, size from `strokeWidth`
- [x] write tests: badge center pixel is glyph or fill color as expected per kind, the tail adds ink in the tail direction only, every kind renders without throwing
- [x] run tests. Must pass before task 10.

### Task 10: Raster image operations

**Files:**
- Create: `Sources/SkitchoCore/Ops/ImageOps.swift`
- Create: `Tests/SkitchoCoreTests/ImageOpsTests.swift`

- [x] `pixelate`, `crop`, `resize`, `expandCanvas`, `rotate90`, `flip` with consistent element geometry/rotation updates; size guard; invalid rect
- [x] write tests: exact 2-px block averages on 4×4, crop translates arrow, **crop leaves strokeWidth unchanged**, **resize 0.5 halves strokeWidth and geometry**, rotate ×4 and flip ×2 are identity
- [x] write tests for errors: too large, invalid rect
- [x] run tests. Must pass before task 11.

### Task 11: Editor core — perform, undo/redo, selection, interactive gestures

**Files:**
- Modify: `Sources/SkitchoCore/Editor/EditorModel.swift`
- Create: `Sources/SkitchoCore/Editor/Tool.swift`
- Create: `Tests/SkitchoCoreTests/EditorUndoTests.swift`

- [x] `Tool` enum (shortcuts, default style); `EditorModel(document:undoManager:)`, `perform`, `restore` with redo re-registration, no-op detection, `begin/commit/cancelInteractive`
- [x] selection: select/toggle/selectAll/deselect/topMostHit; add/remove/move/nudge/reorder (forward/backward)
- [x] write tests (own `UndoManager()`): undo then redo restores each state, `undoActionName`, an interactive gesture is one undo step, cancel reverts, empty delete adds no entry, nudge 1/10, reorder
- [x] run tests. Must pass before task 12.

### Task 12: Editor — style targeting, element clipboard data, image-op commands

**Files:**
- Modify: `Sources/SkitchoCore/Editor/EditorModel.swift`
- Create: `Sources/SkitchoCore/Editor/ElementClipboard.swift`
- Create: `Tests/SkitchoCoreTests/EditorCommandTests.swift`

- [ ] `applyColor/applySizeStep/toggleTextStyle/toggleDoubleHead` target the selection (recomputing frozen sizes with the current image), else the "next element" style
- [ ] `ElementClipboard.encode/decode(Data)`; paste inserts with new IDs, offset +10, and selects them
- [ ] image-op commands wrapping `ImageOps` with names ("Crop Image", "Resize Image", "Pixelate", "Rotate", "Flip", "Expand Canvas")
- [ ] write tests: style to selection vs next element, paste offsets/new IDs, invalid data ignored, each image op undoable
- [ ] run tests. Must pass before task 13.

### Task 13: Import and export (Data-based)

**Files:**
- Create: `Sources/SkitchoCore/IO/Exporter.swift`, `ImageImporter.swift`
- Create: `Tests/SkitchoCoreTests/ExportImportTests.swift`

- [ ] `Exporter.data` for PNG/JPEG(q)/TIFF at 1×/2×
- [ ] `ImageImporter.load(data:)`/`load(url:)`: EXIF orientation applied, converted to sRGB; `Document.blank(size: 800×600, background: .white)`
- [ ] write tests: export→decode each format (dims, type), JPEG quality changes size, an in-test generated orientation-6 JPEG imports upright
- [ ] write tests for errors: unreadable data, zero-size image
- [ ] run tests. Must pass before task 14.

### Task 14: CloudZone theme — colors, type scale (system font), spacing, motion, components

**Files:**
- Create: `Sources/SkitchoUI/Theme/BrandColor.swift`, `Typography.swift`, `Spacing.swift`, `Motion.swift`, `CZButtonStyle.swift`, `CZCard.swift`
- Create: `Tests/SkitchoUITests/ThemeTests.swift`

- [ ] `BrandColor` hex table (only hex in SkitchoUI) and semantic aliases with light/dark dynamic `NSColor(name:dynamicProvider:)` plus a SwiftUI `Color` bridge
- [ ] `Typography` tokens → `Font.system(size:weight:)` / `NSFont.systemFont`; **no font files, no font registration**
- [ ] `Spacing`, `Radius`, `Motion` tokens; `CZButtonStyle` (variants × sizes, disabled, hover with quick ease-in-out); `CZCard`
- [ ] write tests: all hex parse, aliases differ between light and dark, typography resolves to the system font family at the expected sizes/weights, durations match the token set
- [ ] run tests + test-bundle (hex lint). Must pass before task 15.

### Task 15: Canvas view — rendering, zoom, coordinate mapping, select/pan

**Files:**
- Create: `Sources/SkitchoUI/Canvas/CanvasView.swift`, `ToolController.swift`, `SelectPanToolController.swift`, `Cursors.swift`
- Create: `Tests/SkitchoUITests/CanvasMappingTests.swift`

- [ ] `CanvasView` (flipped, in NSScrollView): renders via `DocumentRenderer`, themed surround, zoom fit/in/out/actual/pinch, Space-drag pan; converts NSEvents to doc points and forwards them to the active controller
- [ ] `ToolController` protocol: `mouseDown/Dragged/Up(at: CGPoint, modifiers:)`, `keyDown`, `cursor`, `overlay(in:)`
- [ ] V tool: click select, drag move (interactive commit), marquee
- [ ] SF Symbol cursors per tool
- [ ] write tests: view↔doc mapping round-trips at zoom 0.25/1/3, V tool click selects top-most, drag moves with one undo step, marquee selects contained elements
- [ ] run tests. Must pass before task 16.

### Task 16: Shape tools — arrow, line, rect, rounded rect, ellipse

**Files:**
- Create: `Sources/SkitchoUI/Canvas/ShapeToolController.swift`
- Create: `Tests/SkitchoUITests/ShapeToolTests.swift`

- [ ] drag creates the element with a live preview; Shift = square/circle/15° snap, Option = from center; minimum size, below which a click creates nothing
- [ ] the selection rule from Technical Details (handles/selected element → manipulate, else draw)
- [ ] write tests: each tool's drag produces the expected kind/geometry, Shift snap, tiny click is a no-op, a drag starting on an unselected element draws a new one
- [ ] run tests. Must pass before task 17.

### Task 17: Freehand marker and highlighter

**Files:**
- Create: `Sources/SkitchoUI/Canvas/FreehandToolController.swift`
- Create: `Tests/SkitchoUITests/FreehandToolTests.swift`

- [ ] live low-pass preview; on mouse-up fit segments and add the element (highlighter flag/style)
- [ ] write tests: a point stream produces one freehand element with ≥1 segment, the highlighter default color is yellow, a single point is a no-op
- [ ] run tests. Must pass before task 18.

### Task 18: Selection handles and direct manipulation

**Files:**
- Create: `Sources/SkitchoUI/Canvas/HandleLayout.swift`, `SelectionOverlay.swift`
- Modify: `Sources/SkitchoUI/Canvas/ToolController.swift`
- Create: `Tests/SkitchoUITests/HandleTests.swift`

- [ ] 8 resize handles + rotate handle for boxes/text/stamps, endpoint handles for arrow/line; marching ants; `blue` handles with `white` outline
- [ ] handle drags via interactive gestures; keyboard: Delete, arrows nudge, Esc, ⌘]/⌘[
- [ ] write tests: resize keeps the opposite corner fixed, an endpoint drag changes only that end, Shift rotate snaps 15°, each drag is one undo step
- [ ] run tests. Must pass before task 19.

### Task 19: Text tool with in-place editing

**Files:**
- Create: `Sources/SkitchoUI/Canvas/TextToolController.swift`, `TextEditorOverlay.swift`
- Create: `Tests/SkitchoUITests/TextToolTests.swift`

- [ ] the controller state machine (idle → editing(id) → committed) is separate from the NSTextView overlay. A click creates text and opens the overlay matched to zoom; double-click edits existing text
- [ ] `commit(text:)`: empty → removed with no undo entry; non-empty → one undo step; wrap-width handle; type-to-create
- [ ] write tests (state machine, no first responder): create→commit, empty removal, edit is one undo step, type-to-create seeds the first character
- [ ] run tests. Must pass before task 20.

### Task 20: Stamp tool

**Files:**
- Create: `Sources/SkitchoUI/Canvas/StampToolController.swift`
- Create: `Tests/SkitchoUITests/StampToolTests.swift`

- [ ] a click places the current stamp kind; dragging sets the tail angle; "Attach Label" creates a linked text positioned beside the stamp
- [ ] write tests: tail angle from the drag vector, a click without drag has no tail, the label link survives a move
- [ ] run tests. Must pass before task 21.

### Task 21: Pixelate tool

**Files:**
- Create: `Sources/SkitchoUI/Canvas/PixelateToolController.swift`, `Sources/SkitchoUI/Panels/ApplyCancelBar.swift`
- Create: `Tests/SkitchoUITests/PixelateToolTests.swift`

- [ ] drag region with marching ants; block-size slider; Apply (primary)/Cancel (secondary) bar; Return/Esc keys
- [ ] write tests: apply calls the pixelate command with the clipped rect and is undoable, cancel leaves the document unchanged
- [ ] run tests. Must pass before task 22.

### Task 22: Crop and expand canvas

**Files:**
- Create: `Sources/SkitchoUI/Canvas/CropToolController.swift`, `Sources/SkitchoUI/Panels/CropBar.swift`
- Create: `Tests/SkitchoUITests/CropToolTests.swift`

- [ ] crop overlay: handles, rule-of-thirds grid, dim outside, W×H fields kept in sync with the rect; Apply/Cancel
- [ ] expand-canvas edge buttons (+64 px per click) shown in crop mode
- [ ] write tests: fields ↔ rect sync, apply crop is undoable, expand grows the canvas on the chosen edge
- [ ] run tests. Must pass before task 23.

### Task 23: Resize, rotate and flip

**Files:**
- Create: `Sources/SkitchoUI/Panels/ResizeBar.swift`
- Create: `Tests/SkitchoUITests/ResizeTests.swift`

- [ ] resize: scale slider, W/H fields, proportion link toggle; Apply/Cancel
- [ ] rotate 90° CW/CCW and flip H/V command actions
- [ ] write tests: the proportion link keeps the aspect ratio, unlinked edits change one axis, the size guard surfaces an error message state
- [ ] run tests. Must pass before task 24.

### Task 24: Document window wiring

**Files:**
- Modify: `Sources/SkitchoUI/Document/SkitchoDocument.swift`, `Sources/Skitcho/SkitchoApp.swift`
- Create: `Sources/SkitchoUI/Panels/EditorWindowView.swift`
- Create: `Tests/SkitchoUITests/DocumentTests.swift`

- [ ] `EditorWindowView` uses the CloudZone two-column layout: the tool palette area on the left, the canvas in the center (rounded, `paleBlue`), properties on the right and the bottom bar. It binds `@Environment(\.undoManager)` into `EditorModel`
- [ ] an opened plain image is untitled-like (first ⌘S → `.skitcho` save panel; the source is never overwritten)
- [ ] write tests: snapshot/fileWrapper round-trip with elements, image-opened documents report `.skitchoDocument` as the save type, undo registrations mark the document dirty (via the manager)
- [ ] run tests. Must pass before task 25.

### Task 25: Tool palette and properties panel

**Files:**
- Create: `Sources/SkitchoUI/Panels/ToolPalette.swift`, `PropertiesPanel.swift`
- Create: `Tests/SkitchoUITests/PanelTests.swift`

- [ ] palette: `darkBlue` sidebar, SF Symbol buttons, selected tool `blue`, hover `purple`, sub-tools (shape kinds, stamp kinds) in a plain popover (no pinning)
- [ ] properties: annotation swatches + custom `ColorPicker`, 5 size dots, text styled/plain toggle, arrow double-head toggle
- [ ] write tests: tapping a palette item sets `currentTool`; swatch/size/toggles call the right editor commands (view-model level, not pixels)
- [ ] run tests. Must pass before task 26.

### Task 26: Menus, commands, new-document sources, pasteboard bridge

**Files:**
- Create: `Sources/Skitcho/Commands.swift`, `Sources/SkitchoUI/Pasteboard/PasteboardBridge.swift`
- Create: `Sources/SkitchoUI/Panels/AboutView.swift`
- Create: `Tests/SkitchoUITests/CommandsTests.swift`

- [ ] menus:
  - File: New Blank, New from Clipboard ⌥⌘N via `@Environment(\.newDocument)`, Open, Save, Export As…, Copy Image
  - Edit: Undo/Redo, Copy/Paste/Delete, Select All
  - Arrange: Bring Forward ⌘], Send Backward ⌘[
  - Image: Crop, Resize, Rotate, Flip, Expand Canvas
  - View: zoom
  - Tools: shortcuts
  - commands are enabled based on editor state
- [ ] `PasteboardBridge`: element copy/paste (custom type ↔ `ElementClipboard` Data), image copy (PNG+TIFF), reading an image for New from Clipboard; Dock-icon drop opens images via the document controller
- [ ] About: "Skitcho — by CloudZone", version, MIT license
- [ ] write tests: the pasteboard bridge round-trips elements and images on a private `NSPasteboard(name:)`, the command enablement table
- [ ] run tests. Must pass before task 27.

### Task 27: Export UI, Copy Image, drag-out

**Files:**
- Create: `Sources/SkitchoUI/Panels/ExportAccessoryView.swift`, `Sources/SkitchoUI/Canvas/DragOutSource.swift`
- Create: `Tests/SkitchoUITests/ExportUITests.swift`

- [ ] Export As… `NSSavePanel` + accessory (`CZCard`: format, JPEG quality, Retina 2×) that remembers the last choice in UserDefaults
- [ ] drag-out handle in the bottom bar: `NSFilePromiseProvider` writes a flattened PNG named after the document
- [ ] write tests: accessory state → `ExportFormat`, the promise writer produces a decodable PNG in a temp dir
- [ ] run tests. Must pass before task 28.

### Task 28: Auto-update with Sparkle 2

**Files:**
- Create: `Sources/Skitcho/Updater.swift`, `Sources/SkitchoUI/Panels/SettingsView.swift`
- Modify: `Sources/Skitcho/SkitchoApp.swift`, `Sources/Skitcho/Commands.swift`, `Resources/Info.plist.template`, `Package.swift`, `scripts/bundle.sh`, `scripts/test-bundle.sh`
- Create: `Tests/SkitchoAppTests/UpdaterTests.swift`

- [ ] `UpdaterController` wraps `SPUStandardUpdaterController`. "Check for Updates…" is bound to `canCheckForUpdates`. Settings has a single "Automatically check for updates" toggle; the interval is the Info.plist daily default
- [ ] dev builds (empty `SUPublicEDKey`) do not start the updater; the menu item is disabled with the help text "Updates are disabled in development builds"
- [ ] add a `--self-test` launch argument handled before SwiftUI starts: `@main enum Entry` checks `CommandLine.arguments` for `--self-test` and, if present, touches Sparkle (`SPUUpdater` type metadata), prints `ok` and returns; otherwise it calls `SkitchoApp.main()`. `SkitchoApp` loses its own `@main`
- [ ] `bundle.sh` Sparkle embedding, exactly in this order:
  1. `ditto "$BIN_DIR/Sparkle.framework" Contents/Frameworks/Sparkle.framework` (keeps `Versions/Current` symlinks); then remove `Headers`, `PrivateHeaders`, `Modules` **both** as top-level symlinks and as `Versions/B/` directories (dangling symlinks fail `codesign --strict`); copy no `*.dSYM` and no `PackageFrameworks`
  2. delete `Sparkle.framework/Versions/B/XPCServices` (only needed by sandboxed apps; Skitcho is not sandboxed)
  3. `lipo -thin arm64 X -output X` in place on `Versions/B/Sparkle`, `Versions/B/Autoupdate`, `Versions/B/Updater.app/Contents/MacOS/Updater`
  4. `install_name_tool -add_rpath @executable_path/../Frameworks Contents/MacOS/Skitcho`, and `-delete_rpath` any absolute toolchain path found by `otool -l`
  5. sign inside-out with `codesign -f` (never `--deep` when signing), adding `-o runtime --timestamp` when `$SIGN_IDENTITY` is set. Order: `Autoupdate` → `Updater.app` → `Sparkle.framework` → `Skitcho.app`
  6. verify: `codesign --verify --deep --strict`, then the arm64 `lipo -archs` loop over every Mach-O
- [ ] `test-bundle.sh` additionally asserts:
  - `otool -l Contents/MacOS/Skitcho` contains `@executable_path/../Frameworks`
  - no `XPCServices` directory
  - `build/Skitcho.app/Contents/MacOS/Skitcho --self-test` prints `ok` and exits 0, which proves Sparkle loads through the rpath
- [ ] `Package.swift`: add test target `SkitchoAppTests` depending on `Skitcho`
- [ ] write tests (`@testable import Skitcho`): empty key → `isEnabled == false`, the feed URL constant, the automatic-check toggle persists to Sparkle's `SUEnableAutomaticChecks` default
- [ ] run tests + test-bundle. Must pass before task 29.

### Task 29: App icon generator

**Files:**
- Create: `scripts/app-icon.swift`, `Resources/AppIcon.icns`
- Modify: `scripts/bundle.sh`, `Resources/Info.plist.template`, `scripts/test-bundle.sh`

- [ ] `app-icon.swift`: CoreGraphics `darkBlue` squircle with a blue→lavender gradient arrow (colors from the token values), rendered at every iconset size (16…1024 incl. @2x), then `iconutil -c icns`
- [ ] bundle.sh copies `AppIcon.icns`; Info.plist gets `CFBundleIconFile=AppIcon`
- [ ] write test: test-bundle asserts the icns exists in the bundle and `iconutil -c iconset` on it yields all 10 sizes
- [ ] run tests + test-bundle. Must pass before task 30.

### Task 30: Release script with dry-run test

**Files:**
- Create: `scripts/release.sh`
- Modify: `scripts/test-bundle.sh`

- [ ] `release.sh VERSION [--dry-run]`:
  - `set -euo pipefail` with **no `set -x`**
  - assert `VERSION` matches `^[0-9]+\.[0-9]+\.[0-9]+$`, and (in CI) that `GITHUB_REF_NAME` = `vVERSION`
  - `VERSION=… SIGN_IDENTITY=… scripts/bundle.sh`
  - zip with `ditto -c -k --sequesterRsrc --keepParent build/Skitcho.app dist/Skitcho-VERSION.zip`
- [ ] notarization (skipped in dry-run):
  - `xcrun notarytool submit dist/Skitcho-VERSION.zip --key "$ASC_KEY_PATH" --key-id "$AppleStoreAPIKey" --issuer "$AppleIssuerID" --wait --output-format json`
  - parse with `plutil`/python: if `status` ≠ `Accepted`, run `notarytool log <id>` and exit 1
  - `xcrun stapler staple` + `stapler validate`, then re-zip, then `spctl -a -t exec -vv build/Skitcho.app` shows "Notarized Developer ID"
- [ ] appcast:
  - `curl -fsSL https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml -o dist/appcast.xml || rm -f dist/appcast.xml` (a 404 on the first release is fine)
  - if the file exists, assert the new `CFBundleVersion` > the max `sparkle:version` in it
  - `dist/` holds only the new zip plus that appcast
  - `GA=.build/artifacts/sparkle/Sparkle/bin/generate_appcast` (assert it exists), then `printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$GA" --ed-key-file - --maximum-versions 0 --download-url-prefix "https://github.com/oleggohman/skitcho/releases/download/vVERSION/" dist/`
- [ ] dry-run test (`test-bundle.sh --release-dry-run`) with a key that is **never touched by the Keychain or `generate_keys`**:
  - `OPENSSL=$(brew --prefix openssl@3 2>/dev/null)/bin/openssl` if it exists, else `openssl`; assert `genpkey -algorithm ed25519` succeeds first (`/usr/bin/openssl` is LibreSSL)
  - generate the key in `$TMPDIR`; seed = `pkey -outform DER | tail -c 32 | base64` → `$TMPDIR/seed` and `SPARKLE_ED_PRIVATE_KEY`
  - public key = `pkey -pubout -outform DER | tail -c 32 | base64`, used **only** as `SPARKLE_PUBLIC_ED_KEY` for the dry-run bundle
  - assert the zip contains an arm64-only app
  - assert `appcast.xml` parses, has `sparkle:edSignature`, and the enclosure URL = prefix + `Skitcho-VERSION.zip`
  - extract that `sparkle:edSignature` as `$SIG`, then assert `sign_update --verify --ed-key-file "$TMPDIR/seed" dist/Skitcho-VERSION.zip "$SIG"` exits 0 (`sign_update` verifies with the private key file; it has no public-key option)
  - delete the temp key files
- [x] confirm Sparkle accepts the raw 32-byte seed format (verified by plan reviewer with Sparkle 2.10.1: `sign_update --ed-key-file <seed>` signs and `--verify` exits 0)
- [ ] run tests + dry-run. Must pass before task 31.

### Task 31: Release workflow and maintainer docs

**Files:**
- Create: `.github/workflows/release.yml`, `docs/RELEASING.md`

- [ ] `release.yml` setup:
  - trigger: tag `v*`; a single job with `environment: release` (protected: required reviewer)
  - top-level `permissions: contents: read`; the job gets `contents: write`
  - every third-party action pinned by commit SHA; `actions/checkout` with `fetch-depth: 0`
  - verify the tagged commit is on `main` (`git merge-base --is-ancestor "$GITHUB_SHA" origin/main`)
  - runner and toolchain: same arm64 runner, Xcode selection and version assert as `ci.yml`
- [ ] secrets (env only, `umask 077`):
  - decode the `.p12` and the `ApplePrivateKey` `.p8` into `$RUNNER_TEMP`; export the `.p8` path as `ASC_KEY_PATH` and `SIGN_IDENTITY="$AppleIDENTITY"` for release.sh
  - random `KC_PW`
  - `security create-keychain` → `set-keychain-settings -lut 21600` → `unlock-keychain` → `import cert.p12 -P … -T /usr/bin/codesign` → `set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PW"` → `list-keychains -d user -s build.keychain <existing>`
- [ ] steps: tests, then `scripts/release.sh "${GITHUB_REF_NAME#v}"`, then a single `gh release create "$GITHUB_REF_NAME" dist/Skitcho-*.zip dist/appcast.xml --generate-notes --verify-tag` (not a prerelease, so `latest` moves) with `GH_TOKEN: ${{ github.token }}`
- [ ] `if: always()` cleanup step deletes the keychain, the `.p12` and the `.p8`
- [ ] `docs/RELEASING.md`:
  - create the Sparkle key once with `generate_keys`; export it with `generate_keys -x` into secret `SPARKLE_ED_PRIVATE_KEY`; put the public key in repo variable `SPARKLE_PUBLIC_ED_KEY`
  - the other secrets, the protected `release` environment, tagging, and verifying with `spctl`
- [ ] write test: `actionlint` if available (otherwise a YAML parse via `python3 -c 'import yaml'` or `ruby -ryaml`) on both workflows; grep check that no workflow uses `set -x` or `echo` with a secret var, and that every `uses:` is SHA-pinned
- [ ] run tests. Must pass before task 32.

### Task 32: Verify acceptance criteria
- [ ] every Overview feature is wired: open (dialog/Dock drop/clipboard/blank), all tools including V/pan, properties, handles, undo/redo, arrange, crop/resize/expand/rotate/flip, pixelate, `.skitcho` save/reopen, export PNG/JPEG/TIFF/2×, copy, drag-out, Check for Updates
- [ ] there is no capture/sync/PDF code (`grep -ri 'capture\|evernote\|pdf' Sources` reviewed)
- [ ] arm64: `scripts/test-bundle.sh` passes; `file` and `codesign -dv` output recorded for `build/Skitcho.app/Contents/MacOS/Skitcho`
- [ ] theme: hex lint passes; there are no font files (`git ls-files | grep -iE '\.(ttf|otf)$'` is empty)
- [ ] repo hygiene: no secrets (`git ls-files | grep -iE '\.(p12|p8|key)$|\.env'` is empty), LICENSE present
- [ ] full `swift test --arch arm64 --no-parallel`, lint, coverage ≥ 80% for SkitchoCore (add tests if short)
- [ ] ask the user to run `open build/Skitcho.app` and confirm the main flows (the agent sandbox blocks `open`)

### Task 33: [Final] Update documentation
- [ ] `README.md`: features, install from Releases, build/test commands (arm64), shortcuts, file format, auto-update, clean-room statement
- [ ] `CONTRIBUTING.md` (branching, Conventional Commits, serial arm64 tests, sandbox note) and `SECURITY.md` (reporting, update signing model)
- [ ] `CLAUDE.md`: canonical commands, "run only via build/Skitcho.app", coordinate rule, document concurrency pattern, token rules, arm64-only rule
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion
*Items requiring manual intervention or external systems - no checkboxes, informational only*

**Maintainer setup (needs your accounts; each step confirmed with you first):**
- Create the public repo `oleggohman/skitcho`, push the branch, open a PR.
- Run Sparkle `generate_keys` locally. Store the private key as secret `SPARKLE_ED_PRIVATE_KEY` and the public key as repo variable `SPARKLE_PUBLIC_ED_KEY`.
- Add the Developer ID `.p12` and App Store Connect API key secrets.
- Tag `v0.1.0`, then `v0.1.1`, and confirm that 0.1.0 auto-updates.

**Manual verification:**
- UX walkthrough on Retina/non-Retina displays in light/dark mode: arrow taper, smoothing, text at different zoom levels, 8K image performance, no blocked content, readable font sizes, no needless dialogs.
- Gatekeeper opens the notarized download without warnings; Activity Monitor shows Kind = Apple.
