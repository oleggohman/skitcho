import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct ShapeToolTests {
  private func makeEditor(elements: [Element] = []) -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    manager.groupsByEvent = false
    var document = Document.blank(size: CGSize(width: 800, height: 600))
    document.elements = elements
    return (EditorModel(document: document, undoManager: manager), manager)
  }

  private func controller(_ editor: EditorModel, _ tool: Tool, zoom: Double = 1) -> ShapeToolController {
    editor.currentTool = tool
    return ShapeToolController(editor: editor, tool: tool, zoom: { zoom })
  }

  private func drag(
    _ tool: ShapeToolController, _ manager: UndoManager, from a: CGPoint, to b: CGPoint,
    modifiers: ToolModifiers = []
  ) {
    manager.beginUndoGrouping()
    tool.mouseDown(at: a, modifiers: modifiers)
    tool.mouseDragged(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), modifiers: modifiers)
    tool.mouseDragged(to: b, modifiers: modifiers)
    tool.mouseUp(at: b, modifiers: modifiers)
    manager.endUndoGrouping()
  }

  private func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6 }

  @Test func rectDragCreatesRectAndSelectsIt() {
    let (editor, manager) = makeEditor()
    let tool = controller(editor, .rect)
    drag(tool, manager, from: CGPoint(x: 100, y: 80), to: CGPoint(x: 220, y: 200))
    #expect(editor.document.elements.count == 1)
    guard case .rect(let rect, let rounded) = editor.document.elements[0].kind else {
      Issue.record("expected rect")
      return
    }
    #expect(rect == CGRect(x: 100, y: 80, width: 120, height: 120))
    #expect(!rounded)
    #expect(editor.selection == [editor.document.elements[0].id])
    #expect(editor.document.elements[0].style == editor.nextStyle(for: .rect))
  }

  @Test func dragUpLeftNormalizesRect() {
    let (editor, manager) = makeEditor()
    drag(controller(editor, .rect), manager, from: CGPoint(x: 220, y: 200), to: CGPoint(x: 100, y: 120))
    guard case .rect(let rect, _) = editor.document.elements[0].kind else {
      Issue.record("expected rect")
      return
    }
    #expect(rect == CGRect(x: 100, y: 120, width: 120, height: 80))
  }

  @Test func roundedRectAndEllipseKinds() {
    let (editor, manager) = makeEditor()
    drag(controller(editor, .roundedRect), manager, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 60))
    drag(controller(editor, .ellipse), manager, from: CGPoint(x: 10, y: 100), to: CGPoint(x: 90, y: 160))
    guard case .rect(let rect, let rounded) = editor.document.elements[0].kind,
      case .ellipse(let oval) = editor.document.elements[1].kind
    else {
      Issue.record("unexpected kinds")
      return
    }
    #expect(rounded && rect == CGRect(x: 10, y: 10, width: 80, height: 50))
    #expect(oval == CGRect(x: 10, y: 100, width: 80, height: 60))
  }

  @Test func lineDragCreatesLine() {
    let (editor, manager) = makeEditor()
    drag(controller(editor, .line), manager, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 60))
    guard case .line(let start, let end) = editor.document.elements[0].kind else {
      Issue.record("expected line")
      return
    }
    #expect(start == CGPoint(x: 10, y: 10) && end == CGPoint(x: 110, y: 60))
  }

  @Test func arrowDragCreatesArrowWithNextDoubleHeaded() {
    let (editor, manager) = makeEditor()
    editor.nextDoubleHeaded = true
    drag(controller(editor, .arrow), manager, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 450, y: 50))
    guard case .arrow(let start, let end, let double) = editor.document.elements[0].kind else {
      Issue.record("expected arrow")
      return
    }
    // The head (`end`) sits at the press point; the tail (`start`) follows the drag.
    #expect(end == CGPoint(x: 50, y: 50) && start == CGPoint(x: 450, y: 50) && double)
  }

  @Test func arrowShiftSnapIsMeasuredFromPressPoint() {
    let press = CGPoint(x: 100, y: 100)
    let drag = CGPoint(x: 100 + 200 * cos(10 * Double.pi / 180), y: 100 + 200 * sin(10 * Double.pi / 180))
    guard
      case .arrow(let start, let end, _) = ShapeToolController.kind(
        for: .arrow, from: press, to: drag, modifiers: .shift)
    else {
      Issue.record("expected arrow")
      return
    }
    #expect(end == press)
    let angle = atan2(start.y - end.y, start.x - end.x) * 180 / .pi
    #expect(abs(angle - 15) < 1e-6)
  }

  @Test func arrowOptionPutsHeadOppositeTheDrag() {
    let press = CGPoint(x: 200, y: 200)
    guard
      case .arrow(let start, let end, _) = ShapeToolController.kind(
        for: .arrow, from: press, to: CGPoint(x: 260, y: 200), modifiers: .option)
    else {
      Issue.record("expected arrow")
      return
    }
    #expect(near(start, CGPoint(x: 260, y: 200)) && near(end, CGPoint(x: 140, y: 200)))
  }

  @Test func arrowHeadHandleDragMovesEnd() throws {
    let (editor, manager) = makeEditor()
    let tool = controller(editor, .arrow)
    drag(tool, manager, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 450, y: 50))
    let element = editor.document.elements[0]
    let head = try #require(HandleLayout.position(of: .end, on: element, zoom: 1))
    #expect(near(head, CGPoint(x: 50, y: 50)))
    drag(tool, manager, from: head, to: CGPoint(x: 50, y: 150))
    guard case .arrow(let start, let end, _) = editor.document.elements[0].kind else {
      Issue.record("expected arrow")
      return
    }
    #expect(near(start, CGPoint(x: 450, y: 50)) && near(end, CGPoint(x: 50, y: 150)))
  }

  @Test func shiftMakesSquareAndCircle() {
    let (editor, manager) = makeEditor()
    drag(
      controller(editor, .rect), manager, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 40, y: 220),
      modifiers: .shift)
    drag(
      controller(editor, .ellipse), manager, from: CGPoint(x: 300, y: 300), to: CGPoint(x: 360, y: 340),
      modifiers: .shift)
    guard case .rect(let square, _) = editor.document.elements[0].kind,
      case .ellipse(let circle) = editor.document.elements[1].kind
    else {
      Issue.record("unexpected kinds")
      return
    }
    // Longest side wins; the quadrant of the drag is kept.
    #expect(square == CGRect(x: -20, y: 100, width: 120, height: 120))
    #expect(circle == CGRect(x: 300, y: 300, width: 60, height: 60))
  }

  @Test func shiftSnapsLineToFifteenDegrees() {
    // Dragging at about 10 degrees below horizontal snaps to 15 degrees.
    let start = CGPoint(x: 100, y: 100)
    let end = CGPoint(x: 100 + 200 * cos(10 * Double.pi / 180), y: 100 + 200 * sin(10 * Double.pi / 180))
    let kind = ShapeToolController.kind(for: .line, from: start, to: end, modifiers: .shift)
    guard case .line(let from, let to) = kind else {
      Issue.record("expected line")
      return
    }
    #expect(from == start)
    let angle = atan2(to.y - from.y, to.x - from.x) * 180 / .pi
    #expect(abs(angle - 15) < 1e-6)
    #expect(abs(hypot(to.x - from.x, to.y - from.y) - 200) < 1e-6)
  }

  @Test func optionDrawsFromCenter() {
    let rect = ShapeToolController.kind(
      for: .rect, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 140, y: 120), modifiers: .option)
    #expect(rect == .rect(CGRect(x: 60, y: 80, width: 80, height: 40), rounded: false))
    let line = ShapeToolController.kind(
      for: .line, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 140, y: 100), modifiers: .option)
    guard case .line(let from, let to) = line else {
      Issue.record("expected line")
      return
    }
    #expect(near(from, CGPoint(x: 60, y: 100)) && near(to, CGPoint(x: 140, y: 100)))
    let both = ShapeToolController.kind(
      for: .ellipse, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 130, y: 120), modifiers: [.option, .shift])
    #expect(both == .ellipse(CGRect(x: 70, y: 70, width: 60, height: 60)))
  }

  @Test func tinyClickCreatesNothing() {
    let (editor, manager) = makeEditor()
    for tool in ShapeToolController.supportedTools {
      let controller = controller(editor, tool)
      controller.mouseDown(at: CGPoint(x: 50, y: 50), modifiers: [])
      controller.mouseUp(at: CGPoint(x: 50, y: 50), modifiers: [])
      // A drag past the threshold but below the minimum size is cancelled on release.
      drag(controller, manager, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 52, y: 52))
      drag(controller, manager, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 53.5, y: 50))
    }
    #expect(editor.document.elements.isEmpty)
    #expect(!editor.isInteracting)
  }

  @Test func minimumSizeScalesWithZoom() {
    let (editor, manager) = makeEditor()
    // 6 doc units at zoom 0.5 is 3 view points: a click. 12 units at zoom 0.5 is 6 view points: a rect.
    drag(controller(editor, .rect, zoom: 0.5), manager, from: .zero, to: CGPoint(x: 6, y: 6))
    #expect(editor.document.elements.isEmpty)
    drag(controller(editor, .rect, zoom: 0.5), manager, from: .zero, to: CGPoint(x: 12, y: 12))
    #expect(editor.document.elements.count == 1)
  }

  @Test func shortArrowBelowMinimumLengthIsDiscarded() {
    let (editor, manager) = makeEditor()
    drag(controller(editor, .arrow), manager, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 60, y: 50))
    #expect(editor.document.elements.isEmpty)
  }

  @Test func dragIsOneUndoStepAndLivePreviewAppears() {
    let (editor, manager) = makeEditor()
    let tool = controller(editor, .rect)
    manager.beginUndoGrouping()
    tool.mouseDown(at: CGPoint(x: 10, y: 10), modifiers: [])
    tool.mouseDragged(to: CGPoint(x: 60, y: 60), modifiers: [])
    #expect(editor.document.elements.count == 1)
    tool.mouseDragged(to: CGPoint(x: 110, y: 90), modifiers: [])
    #expect(editor.document.elements.count == 1)
    guard case .rect(let live, _) = editor.document.elements[0].kind else {
      Issue.record("expected rect")
      return
    }
    #expect(live == CGRect(x: 10, y: 10, width: 100, height: 80))
    tool.mouseUp(at: CGPoint(x: 110, y: 90), modifiers: [])
    manager.endUndoGrouping()
    #expect(manager.undoActionName == "Add Rectangle")
    manager.undo()
    #expect(editor.document.elements.isEmpty)
    manager.redo()
    #expect(editor.document.elements.count == 1)
  }

  @Test func escapeCancelsDrawing() {
    let (editor, _) = makeEditor()
    let tool = controller(editor, .rect)
    tool.mouseDown(at: CGPoint(x: 10, y: 10), modifiers: [])
    tool.mouseDragged(to: CGPoint(x: 90, y: 90), modifiers: [])
    #expect(editor.document.elements.count == 1)
    #expect(tool.keyDown(.escape, modifiers: []))
    #expect(editor.document.elements.isEmpty)
    #expect(!editor.isInteracting)
    tool.mouseUp(at: CGPoint(x: 90, y: 90), modifiers: [])
    #expect(editor.document.elements.isEmpty)
  }

  @Test func dragStartingOnUnselectedElementDrawsNewOne() {
    let existing = Element(
      kind: .rect(CGRect(x: 100, y: 100, width: 100, height: 100), rounded: false),
      style: Style.make(tool: .rect, sizeStep: .default, color: .red, imageSize: CGSize(width: 800, height: 600)))
    let (editor, manager) = makeEditor(elements: [existing])
    #expect(editor.selection.isEmpty)
    drag(controller(editor, .ellipse), manager, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 260, y: 240))
    #expect(editor.document.elements.count == 2)
    #expect(editor.document.elements[0] == existing)
    guard case .ellipse = editor.document.elements[1].kind else {
      Issue.record("expected ellipse")
      return
    }
    #expect(editor.selection == [editor.document.elements[1].id])
  }

  /// Selection rule: the body of the selected (just drawn) element does not grab the press; a new element starts.
  @Test func dragStartingOnSelectedElementBodyDrawsNewOne() {
    let existing = Element(
      kind: .rect(CGRect(x: 100, y: 100, width: 100, height: 100), rounded: false),
      style: Style.make(tool: .rect, sizeStep: .default, color: .red, imageSize: CGSize(width: 800, height: 600)))
    let (editor, manager) = makeEditor(elements: [existing])
    editor.select(existing.id)
    drag(controller(editor, .arrow), manager, from: CGPoint(x: 125, y: 100), to: CGPoint(x: 265, y: 220))
    #expect(editor.document.elements.count == 2)
    #expect(editor.document.elements[0] == existing)
    guard case .arrow = editor.document.elements[1].kind else {
      Issue.record("expected arrow")
      return
    }
    #expect(manager.undoActionName == "Add Arrow")
  }

  /// Handles of the selection still work with a drawing tool.
  @Test func dragOnSelectedHandleResizesIt() throws {
    let existing = Element(
      kind: .rect(CGRect(x: 100, y: 100, width: 100, height: 100), rounded: false),
      style: Style.make(tool: .rect, sizeStep: .default, color: .red, imageSize: CGSize(width: 800, height: 600)))
    let (editor, manager) = makeEditor(elements: [existing])
    editor.select(existing.id)
    let corner = try #require(HandleLayout.position(of: .bottomRight, on: existing, zoom: 1))
    drag(
      controller(editor, .ellipse), manager, from: corner, to: CGPoint(x: corner.x + 40, y: corner.y + 20))
    #expect(editor.document.elements.count == 1)
    #expect(editor.document.elements[0].bounds.width > existing.bounds.width)
    #expect(manager.undoActionName != "Add Ellipse")
  }

  @Test func canvasRegistersShapeControllers() {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    for tool in ShapeToolController.supportedTools {
      editor.currentTool = tool
      #expect(canvas.activeController is ShapeToolController)
    }
    editor.currentTool = .select
    #expect(canvas.activeController is SelectPanToolController)
  }
}
