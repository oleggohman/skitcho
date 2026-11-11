---
worth: yes
where: Sources/SkitchoUI/Canvas/ShapeToolController.swift
added: 2026-11-11
---
# arrow head should be where the drag starts

Requested by the maintainer as a roadmap item (2026-11-11): when drawing an arrow, the point where the mouse
is pressed is the thing being pointed at, so the **arrowhead goes at the press point** and the tail follows the
drag. Today the arrow tool creates `.arrow(start: press, end: current)` and draws the head at `end`, i.e. at the
release point — the opposite of what the maintainer expects.

Likely work: in the arrow branch of `ShapeToolController`, swap the roles so the head sits at the press point
(either create `.arrow(start: current, end: press)` or keep the geometry and flip which end gets the head).
Keep the rest consistent with it: Shift 15° snapping and the minimum-length check measured from the press
point, Option-from-center, the endpoint handles in `HandleLayout` (dragging the head end vs the tail end), the
double-headed toggle, and the stamp-style "point at something" mental model. Update `ShapeToolTests`
(arrow drag geometry) and the README quick-start wording ("drag from the target outward").
