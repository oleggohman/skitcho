import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct HandleTests {
  private let style = Style(color: .red, sizeStep: .default, strokeWidth: 4, fontSize: 48)

  private func rect(_ r: CGRect, rotation: Double = 0) -> Element {
    Element(kind: .rect(r, rounded: false), style: style, rotation: rotation)
  }

  private func makeEditor(_ elements: [Element]) -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    manager.groupsByEvent = false
    var document = Document.blank(size: CGSize(width: 800, height: 600))
    document.elements = elements
    return (EditorModel(document: document, undoManager: manager), manager)
  }

  private func near(_ a: CGPoint, _ b: CGPoint, _ eps: Double = 1e-6) -> Bool {
    abs(a.x - b.x) < eps && abs(a.y - b.y) < eps
  }

  private func dragHandle(
    _ tool: ToolController, _ manager: UndoManager, from a: CGPoint, to b: CGPoint,
    modifiers: ToolModifiers = []
  ) {
    manager.beginUndoGrouping()
    tool.mouseDown(at: a, modifiers: modifiers)
    tool.mouseDragged(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), modifiers: modifiers)
    tool.mouseDragged(to: b, modifiers: modifiers)
    tool.mouseUp(at: b, modifiers: modifiers)
    manager.endUndoGrouping()
  }

  private func offset(_ p: CGPoint, dx: Double, dy: Double) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }

  // MARK: Layout

  @Test func handleCountsPerKind() {
    #expect(HandleLayout.available(for: rect(CGRect(x: 0, y: 0, width: 10, height: 10))).count == 9)
    let arrow = Element(kind: .arrow(start: .zero, end: CGPoint(x: 50, y: 0), doubleHeaded: false), style: style)
    #expect(HandleLayout.available(for: arrow) == [.start, .end])
    let stamp = Element(
      kind: .stamp(.approve, center: CGPoint(x: 50, y: 50), tailAngle: nil, labelID: nil), style: style)
    #expect(HandleLayout.available(for: stamp).count == 5)
    let segment = BezierSegment(.zero, .zero, CGPoint(x: 9, y: 9), CGPoint(x: 9, y: 9))
    let free = Element(kind: .freehand(segments: [segment], highlighter: false), style: style)
    #expect(HandleLayout.available(for: free).count == 8)
  }

  @Test func handlePositionsFollowRotation() {
    let element = rect(CGRect(x: 100, y: 100, width: 100, height: 50), rotation: .pi / 2)
    // Rotating 90 degrees clockwise about (150,125) moves top-left (100,100) to (175,75).
    let point = HandleLayout.position(of: .topLeft, on: element, zoom: 1)!
    #expect(near(point, CGPoint(x: 175, y: 75)))
    #expect(HandleLayout.hit(element, at: CGPoint(x: 176, y: 76), zoom: 1) == .topLeft)
    #expect(HandleLayout.hit(element, at: CGPoint(x: 400, y: 400), zoom: 1) == nil)
  }

  @Test func rotateHandleSitsAboveTopEdge() {
    let element = rect(CGRect(x: 100, y: 100, width: 100, height: 50))
    let at1 = HandleLayout.position(of: .rotate, on: element, zoom: 1)!
    #expect(near(at1, CGPoint(x: 150, y: 76)))
    let at2 = HandleLayout.position(of: .rotate, on: element, zoom: 2)!
    #expect(near(at2, CGPoint(x: 150, y: 88)))
  }

  // MARK: Resize

  @Test func resizeKeepsOppositeCornerFixed() {
    let original = rect(CGRect(x: 100, y: 100, width: 100, height: 50))
    let result = HandleLayout.apply(.bottomRight, to: original, pointer: CGPoint(x: 260, y: 210), modifiers: [])
    guard case .rect(let r, _) = result.kind else {
      Issue.record("rect expected")
      return
    }
    #expect(r == CGRect(x: 100, y: 100, width: 160, height: 110))
    let topLeft = HandleLayout.apply(.topLeft, to: original, pointer: CGPoint(x: 80, y: 90), modifiers: [])
    guard case .rect(let t, _) = topLeft.kind else {
      Issue.record("rect expected")
      return
    }
    #expect(t.maxX == 200 && t.maxY == 150 && t.minX == 80 && t.minY == 90)
  }

  @Test func edgeHandleChangesOneAxisOnly() {
    let original = rect(CGRect(x: 100, y: 100, width: 100, height: 50))
    let result = HandleLayout.apply(.right, to: original, pointer: CGPoint(x: 300, y: 400), modifiers: [])
    guard case .rect(let r, _) = result.kind else {
      Issue.record("rect expected")
      return
    }
    #expect(r == CGRect(x: 100, y: 100, width: 200, height: 50))
  }

  @Test func resizeRotatedKeepsOppositeCornerFixedOnScreen() {
    let original = rect(CGRect(x: 100, y: 100, width: 100, height: 50), rotation: .pi / 6)
    let fixed = HandleLayout.position(of: .topLeft, on: original, zoom: 1)!
    let corner = HandleLayout.position(of: .bottomRight, on: original, zoom: 1)!
    let result = HandleLayout.apply(
      .bottomRight, to: original, pointer: offset(corner, dx: 20, dy: 10), modifiers: [])
    #expect(near(HandleLayout.position(of: .topLeft, on: result, zoom: 1)!, fixed))
    #expect(result.rotation == original.rotation)
    #expect(result.baseBounds.width > 100)
  }

  @Test func shiftKeepsAspectOnCornerResize() {
    let original = rect(CGRect(x: 0, y: 0, width: 100, height: 50))
    let result = HandleLayout.apply(.bottomRight, to: original, pointer: CGPoint(x: 200, y: 60), modifiers: .shift)
    guard case .rect(let r, _) = result.kind else {
      Issue.record("rect expected")
      return
    }
    #expect(abs(r.width / r.height - 2) < 1e-9)
    #expect(r.minX == 0 && r.minY == 0)
  }

  @Test func dragPastOppositeEdgeFlipsInsteadOfCollapsing() {
    let original = rect(CGRect(x: 100, y: 100, width: 100, height: 50))
    let result = HandleLayout.apply(.right, to: original, pointer: CGPoint(x: 60, y: 120), modifiers: [])
    guard case .rect(let r, _) = result.kind else {
      Issue.record("rect expected")
      return
    }
    #expect(r == CGRect(x: 60, y: 100, width: 40, height: 50))
  }

  @Test func stampScalesUniformlyAboutOppositeCorner() {
    let original = Element(
      kind: .stamp(.approve, center: CGPoint(x: 200, y: 200), tailAngle: nil, labelID: nil), style: style)
    let base = original.baseBounds
    let pointer = CGPoint(x: base.maxX + base.width, y: base.maxY + base.height)
    let result = HandleLayout.apply(.bottomRight, to: original, pointer: pointer, modifiers: [])
    #expect(abs(result.baseBounds.width - 2 * base.width) < 1e-6)
    #expect(abs(result.baseBounds.minX - base.minX) < 1e-6)
    #expect(abs(result.baseBounds.minY - base.minY) < 1e-6)
    #expect(abs(result.style.strokeWidth - 2 * style.strokeWidth) < 1e-9)
  }

  @Test func freehandResizeMapsPointsIntoNewBounds() {
    let segment = BezierSegment(
      CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50), CGPoint(x: 100, y: 50))
    let original = Element(kind: .freehand(segments: [segment], highlighter: false), style: style)
    let base = original.baseBounds
    let result = HandleLayout.apply(
      .bottomRight, to: original, pointer: CGPoint(x: base.minX + 2 * base.width, y: base.maxY), modifiers: [])
    guard case .freehand(let segments, _) = result.kind else {
      Issue.record("freehand expected")
      return
    }
    #expect(near(segments[0].p3, CGPoint(x: 200, y: 50)))
    #expect(near(segments[0].p0, CGPoint(x: 0, y: 0)))
  }

  // MARK: Endpoints and rotation

  @Test func endpointDragChangesOnlyThatEnd() {
    let original = Element(
      kind: .arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 100, y: 10), doubleHeaded: true), style: style)
    let moved = HandleLayout.apply(.end, to: original, pointer: CGPoint(x: 120, y: 60), modifiers: [])
    guard case .arrow(let start, let end, let double) = moved.kind else {
      Issue.record("arrow expected")
      return
    }
    #expect(start == CGPoint(x: 10, y: 10) && end == CGPoint(x: 120, y: 60) && double)
    let line = Element(kind: .line(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 100, y: 10)), style: style)
    let movedStart = HandleLayout.apply(.start, to: line, pointer: CGPoint(x: 0, y: 40), modifiers: [])
    #expect(movedStart.kind == .line(start: CGPoint(x: 0, y: 40), end: CGPoint(x: 100, y: 10)))
  }

  @Test func shiftSnapsEndpointAndRotationTo15Degrees() {
    let line = Element(kind: .line(start: .zero, end: CGPoint(x: 100, y: 0)), style: style)
    let snapped = HandleLayout.apply(.end, to: line, pointer: CGPoint(x: 100, y: 12), modifiers: .shift)
    guard case .line(_, let end) = snapped.kind else {
      Issue.record("line expected")
      return
    }
    #expect(abs(end.y) < 1e-9)

    let box = rect(CGRect(x: 100, y: 100, width: 100, height: 100))
    // Pointer right of center and slightly below the horizontal: raw angle is just over pi/2.
    let raw = HandleLayout.apply(.rotate, to: box, pointer: CGPoint(x: 250, y: 160), modifiers: [])
    let snap = HandleLayout.apply(.rotate, to: box, pointer: CGPoint(x: 250, y: 160), modifiers: .shift)
    #expect(abs(raw.rotation - Double.pi / 2) > 0.05)
    #expect(abs(snap.rotation - Double.pi / 2) < 1e-9)
    let steps = snap.rotation / (Double.pi / 12)
    #expect(abs(steps - steps.rounded()) < 1e-9)
  }

  @Test func rotateHandleDragTracksPointerAngle() {
    let box = rect(CGRect(x: 100, y: 100, width: 100, height: 100))
    let up = HandleLayout.apply(.rotate, to: box, pointer: CGPoint(x: 150, y: 0), modifiers: [])
    #expect(abs(up.rotation) < 1e-9)
    let left = HandleLayout.apply(.rotate, to: box, pointer: CGPoint(x: 0, y: 150), modifiers: [])
    #expect(abs(abs(left.rotation) - Double.pi / 2) < 1e-9)
  }

  // MARK: Controllers and undo

  @Test func selectToolResizeIsOneUndoStep() {
    let element = rect(CGRect(x: 100, y: 100, width: 100, height: 50))
    let (editor, manager) = makeEditor([element])
    editor.select(element.id)
    let tool = SelectPanToolController(editor: editor, zoom: { 1 })
    dragHandle(tool, manager, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 260, y: 210))
    guard case .rect(let r, _) = editor.document.elements[0].kind else {
      Issue.record("rect expected")
      return
    }
    #expect(r == CGRect(x: 100, y: 100, width: 160, height: 110))
    #expect(manager.undoActionName == "Resize")
    manager.undo()
    #expect(editor.document.elements[0] == element)
    #expect(!manager.canUndo)
  }

  @Test func rotateAndEndpointDragsAreOneUndoStepEach() {
    let box = rect(CGRect(x: 100, y: 100, width: 100, height: 100))
    let line = Element(kind: .line(start: CGPoint(x: 400, y: 400), end: CGPoint(x: 500, y: 400)), style: style)
    let (editor, manager) = makeEditor([box, line])
    let tool = SelectPanToolController(editor: editor, zoom: { 1 })
    editor.select(box.id)
    dragHandle(tool, manager, from: CGPoint(x: 150, y: 76), to: CGPoint(x: 250, y: 150))
    #expect(abs(editor.document.elements[0].rotation - Double.pi / 2) < 1e-9)
    #expect(manager.undoActionName == "Rotate")
    editor.select(line.id)
    dragHandle(tool, manager, from: CGPoint(x: 500, y: 400), to: CGPoint(x: 520, y: 450))
    #expect(editor.document.elements[1].kind == .line(start: CGPoint(x: 400, y: 400), end: CGPoint(x: 520, y: 450)))
    #expect(manager.undoActionName == "Move Endpoint")
    manager.undo()
    #expect(editor.document.elements[1] == line)
    manager.undo()
    #expect(editor.document.elements[0] == box)
    #expect(!manager.canUndo)
  }

  @Test func clickOnHandleWithoutDragMakesNoChange() {
    let element = rect(CGRect(x: 100, y: 100, width: 100, height: 50))
    let (editor, manager) = makeEditor([element])
    editor.select(element.id)
    let tool = SelectPanToolController(editor: editor, zoom: { 1 })
    manager.beginUndoGrouping()
    tool.mouseDown(at: CGPoint(x: 200, y: 150), modifiers: [])
    tool.mouseUp(at: CGPoint(x: 200, y: 150), modifiers: [])
    manager.endUndoGrouping()
    #expect(editor.document.elements[0] == element)
  }

  @Test func escapeCancelsHandleDrag() {
    let element = rect(CGRect(x: 100, y: 100, width: 100, height: 50))
    let (editor, manager) = makeEditor([element])
    editor.select(element.id)
    let tool = SelectPanToolController(editor: editor, zoom: { 1 })
    manager.beginUndoGrouping()
    tool.mouseDown(at: CGPoint(x: 200, y: 150), modifiers: [])
    tool.mouseDragged(to: CGPoint(x: 300, y: 300), modifiers: [])
    #expect(tool.keyDown(.escape, modifiers: []))
    tool.mouseUp(at: CGPoint(x: 300, y: 300), modifiers: [])
    manager.endUndoGrouping()
    #expect(editor.document.elements[0] == element)
  }

  @Test func drawingToolsManipulateSelectedHandleInsteadOfDrawing() {
    let element = rect(CGRect(x: 100, y: 100, width: 100, height: 50))
    for tool in [Tool.rect, .arrow, .marker] {
      let (editor, manager) = makeEditor([element])
      editor.select(element.id)
      editor.currentTool = tool
      let controller: ToolController =
        tool == .marker
        ? FreehandToolController(editor: editor, tool: tool, zoom: { 1 })
        : ShapeToolController(editor: editor, tool: tool, zoom: { 1 })
      dragHandle(controller, manager, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 260, y: 210))
      #expect(editor.document.elements.count == 1)
      guard case .rect(let r, _) = editor.document.elements[0].kind else {
        Issue.record("rect expected")
        return
      }
      #expect(r == CGRect(x: 100, y: 100, width: 160, height: 110))
      #expect(manager.undoActionName == "Resize")
    }
  }

  @Test func handleOnUnselectedElementDoesNotManipulate() {
    let element = rect(CGRect(x: 100, y: 100, width: 100, height: 50))
    let (editor, manager) = makeEditor([element])
    editor.currentTool = .rect
    let controller = ShapeToolController(editor: editor, tool: .rect, zoom: { 1 })
    dragHandle(controller, manager, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 260, y: 210))
    #expect(editor.document.elements.count == 2)
  }

  // MARK: Keyboard

  @Test func commandBracketsReorderSelection() {
    let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
    let b = rect(CGRect(x: 20, y: 0, width: 10, height: 10))
    let (editor, manager) = makeEditor([a, b])
    editor.select(a.id)
    let tool = SelectPanToolController(editor: editor, zoom: { 1 })
    manager.beginUndoGrouping()
    #expect(tool.keyDown(.character("]"), modifiers: .command))
    manager.endUndoGrouping()
    #expect(editor.document.elements.map(\.id) == [b.id, a.id])
    manager.beginUndoGrouping()
    #expect(tool.keyDown(.character("["), modifiers: .command))
    manager.endUndoGrouping()
    #expect(editor.document.elements.map(\.id) == [a.id, b.id])
    #expect(!tool.keyDown(.character("]"), modifiers: []))
  }

  // MARK: Overlay

  @Test func overlayDrawsHandlesForSingleSelection() {
    let element = rect(CGRect(x: 20, y: 20, width: 60, height: 40), rotation: 0.3)
    let (editor, _) = makeEditor([element])
    editor.select(element.id)
    let tool = SelectPanToolController(editor: editor, zoom: { 1 })
    let context = CGContext(
      data: nil, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    tool.overlay(in: context, zoom: 1)
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    var painted = 0
    for i in stride(from: 3, to: context.bytesPerRow * 120, by: 4) where data[i] != 0 { painted += 1 }
    #expect(painted > 100)
  }
}
