---
worth: yes
where: Sources/SkitchoCore/Geometry/ArrowPath.swift
added: 2026-11-11
---
# arrow should look like the classic bold, outlined callout arrow

Requested by the maintainer as a roadmap item (reference screenshot from 2026-11-11, kept privately, not
committed). The target look, as seen in the reference:

- **Bold and chunky**: a wide triangular head and a thick shaft, readable at a glance on any picture.
- **Strong taper**: the shaft widens steadily from a fairly narrow, rounded tail to the head base; the head is
  much wider than the shaft and has sharp, slightly swept-back barbs.
- **Saturated fill**: solid red by default (current `AnnotationColor.red`), no gradient.
- **White outline**: a thin white stroke around the whole arrow so it stands out on dark and busy backgrounds.
- **Soft drop shadow**: a subtle dark shadow offset down-right under the arrow.

Today's arrow (`ArrowPath.make`, `DocumentRenderer`) already tapers and has a soft shadow, but no white
outline, and its proportions (head = 3× stroke width, head half-width = 0.6× head length, shaft half-width at
head base = max(0.25× width, tail)) look thinner than the reference. Likely work: add an outline pass in the
renderer (white, width scaled with stroke, drawn under the fill), retune the head/shaft proportions, and
compare against the reference at small, medium and large size steps. Rendering tests and the existing
geometry tests (head cap at 0.4·L, symmetry) need updating with the new proportions.
