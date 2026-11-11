---
worth: yes
where: Sources/SkitchoUI/Canvas/CanvasView.swift
added: 2026-11-11
---
# Esc should switch back to the Select (cursor) tool

Requested by the maintainer as a roadmap item (2026-11-11, with a screenshot of the tool palette showing the
Select/cursor tool highlighted): pressing **Esc** should return to the Select tool (V), the arrow-cursor button
at the top of the palette, from any other tool.

Today Esc only cancels the current operation per tool — it cancels an in-progress drag, cancels a pending
pixelate or crop, commits/ends a text edit, or clears the selection — and the current tool stays active.

Desired order of one Esc press, so nothing in progress is lost or applied by surprise:
1. While editing text: end the edit the way Esc does today (commit non-empty text, drop empty text), then
   switch to Select.
2. During a drag gesture: cancel the gesture (as today), then switch to Select.
3. With a pending pixelate region or crop rectangle: cancel it (as today), then switch to Select.
4. Otherwise: switch to Select; if already on Select, Esc keeps clearing the selection as now.

Likely work: route Esc centrally in `CanvasView.handleKey` / `ToolShortcutRouter` after the active
controller's own cancel, set `EditorModel.currentTool = .select`, and keep the palette highlight in sync
(`ToolPaletteModel`). Tests: one per case above (tool after Esc == .select, document unchanged where the old
behaviour cancelled), plus the README shortcuts table ("Esc — cancel and return to Select").
