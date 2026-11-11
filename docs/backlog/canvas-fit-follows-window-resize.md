---
worth: yes
where: Sources/SkitchoUI/Canvas/CanvasView.swift
added: 2026-11-11
---
# opened picture should scale with the window

Requested by the maintainer as a roadmap item (2026-11-11): the opened picture must scale with the
application window — resizing the window should grow or shrink the picture to fit, like a viewer.

Today `CanvasScrollView` fits the canvas to the viewport only once, on its first real-size layout; after that
the zoom is fixed, so resizing the window just adds empty space or scroll bars.

Proposed behaviour:
- A "fit" mode that is on by default for a newly opened picture: on every viewport size change (window resize,
  full screen, sidebar/bar layout change) the zoom is recomputed to fit the whole canvas, centred, with the
  usual margin and the crop-bar reserve.
- Any manual zoom (⌘+/⌘−/⌘0, pinch) leaves fit mode; Zoom to Fit (⌘9) re-enters it. The zoom indicator in the
  bottom bar shows when fit mode is on.
- Open detail to settle when implementing: today fit never exceeds 100% (small images are not upscaled, to
  avoid blur). Decide with the maintainer whether a small picture should also grow past 100% with the window.

Likely work: observe the clip view's frame/bounds changes in `CanvasScrollView`/`CanvasView`, a `fitMode` flag
toggled by the zoom commands, reuse `zoomToFit`'s maths; keep pointer/centre anchoring for manual zoom. Tests:
fit recomputed on viewport resize while in fit mode, unchanged after a manual zoom, re-entered by ⌘9.
