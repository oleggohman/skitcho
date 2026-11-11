import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct StampToolTests {
  private func makeEditor(elements: [Element] = []) -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    manager.groupsByEvent = false
    var document = Document.blank(size: CGSize(width: 800, height: 600))
    document.elements = elements
    let editor = EditorModel(document: document, undoManager: manager)
    editor.currentTool = .stamp
    return (editor, manager)
  }

  private func makeTools(_ editor: EditorModel) -> (StampToolController, TextToolController) {
    let text = TextToolController(editor: editor, zoom: { 1 })
    return (StampToolController(editor: editor, zoom: { 1 }, labelEditor: text), text)
  }

  private func press(
    _ tool: StampToolController, _ manager: UndoManager, from a: CGPoint, to b: CGPoint? = nil
  ) {
    manager.beginUndoGrouping()
    tool.mouseDown(at: a, modifiers: [])
    if let b {
      tool.mouseDragged(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), modifiers: [])
      tool.mouseDragged(to: b, modifiers: [])
    }
    tool.mouseUp(at: b ?? a, modifiers: [])
    manager.endUndoGrouping()
  }

  /// Commits the label text inside an explicit undo group (the manager does not group by event).
  private func commit(_ text: TextToolController, _ manager: UndoManager, _ string: String) {
    manager.beginUndoGrouping()
    text.commit(text: string)
    manager.endUndoGrouping()
  }

  private func stamp(_ editor: EditorModel) -> (StampKind, CGPoint, Double?, UUID?)? {
    for element in editor.document.elements {
      if case .stamp(let kind, let center, let tail, let label) = element.kind {
        return (kind, center, tail, label)
      }
    }
    return nil
  }

  private func stampAngle(_ editor: EditorModel, index: Int) -> Double? {
    if case .stamp(_, _, let tail, _) = editor.document.elements[index].kind { return tail }
    return nil
  }

  @Test func clickPlacesStampWithoutTail() {
    let (editor, manager) = makeEditor()
    let (tool, _) = makeTools(editor)
    press(tool, manager, from: CGPoint(x: 200, y: 150))
    #expect(editor.document.elements.count == 1)
    let placed = stamp(editor)
    #expect(placed?.0 == .approve)
    #expect(placed?.1 == CGPoint(x: 200, y: 150))
    #expect(placed?.2 == nil)
    #expect(editor.selection == [editor.document.elements[0].id])
    #expect(editor.document.elements[0].style.color == .green)
    #expect(manager.undoActionName == "Add Stamp")
  }

  @Test func usesCurrentStampKindAndColorChoice() {
    let (editor, manager) = makeEditor()
    editor.nextStampKind = .reject
    let (tool, _) = makeTools(editor)
    press(tool, manager, from: CGPoint(x: 50, y: 50))
    #expect(stamp(editor)?.0 == .reject)
    #expect(editor.document.elements[0].style.color == StampKind.reject.defaultColor)
    editor.deselect()
    editor.nextColor = .navy
    press(tool, manager, from: CGPoint(x: 300, y: 300))
    #expect(editor.document.elements[1].style.color == .navy)
  }

  @Test func dragSetsTailAngleFromDragVector() {
    let (editor, manager) = makeEditor()
    let (tool, _) = makeTools(editor)
    // Down and to the right by equal amounts: 45 degrees in y-down space.
    press(tool, manager, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 160))
    let angle = stamp(editor)?.2
    #expect(angle != nil)
    #expect(abs((angle ?? 0) - .pi / 4) < 1e-9)
    #expect(stamp(editor)?.1 == CGPoint(x: 100, y: 100))
    // Straight up.
    editor.deselect()
    press(tool, manager, from: CGPoint(x: 400, y: 300), to: CGPoint(x: 400, y: 240))
    #expect(abs((stampAngle(editor, index: 1) ?? 0) + .pi / 2) < 1e-9)
  }

  @Test func tinyDragBelowThresholdHasNoTail() {
    let (editor, manager) = makeEditor()
    let (tool, _) = makeTools(editor)
    press(tool, manager, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 101, y: 101))
    #expect(stamp(editor)?.2 == nil)
  }

  @Test func placementIsOneUndoStep() {
    let (editor, manager) = makeEditor()
    let (tool, _) = makeTools(editor)
    press(tool, manager, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 100))
    #expect(editor.document.elements.count == 1)
    manager.undo()
    #expect(editor.document.elements.isEmpty)
    manager.redo()
    #expect(editor.document.elements.count == 1)
  }

  @Test func escapeCancelsPlacement() {
    let (editor, manager) = makeEditor()
    let (tool, _) = makeTools(editor)
    tool.mouseDown(at: CGPoint(x: 100, y: 100), modifiers: [])
    #expect(editor.document.elements.count == 1)
    #expect(tool.keyDown(.escape, modifiers: []))
    #expect(editor.document.elements.isEmpty)
    #expect(!manager.canUndo)
  }

  /// Selection rule: the just placed (selected) stamp does not grab the next press; a new stamp is placed.
  @Test func pressOnSelectedStampPlacesAnotherOne() {
    let (editor, manager) = makeEditor()
    let (tool, _) = makeTools(editor)
    press(tool, manager, from: CGPoint(x: 200, y: 200))
    let first = editor.document.elements[0]
    press(tool, manager, from: CGPoint(x: 205, y: 205), to: CGPoint(x: 260, y: 230))
    #expect(editor.document.elements.count == 2)
    #expect(editor.document.elements[0] == first)
    #expect(editor.selection == [editor.document.elements[1].id])
  }

  @Test func attachLabelCreatesLinkedTextBesideStampInOneUndoStep() {
    let (editor, manager) = makeEditor()
    let (tool, text) = makeTools(editor)
    press(tool, manager, from: CGPoint(x: 200, y: 200))
    let stampID = editor.document.elements[0].id
    #expect(tool.attachLabel(to: stampID))
    #expect(text.isEditing)
    #expect(editor.currentTool == .text)
    commit(text, manager, "Looks good")
    #expect(editor.document.elements.count == 2)
    guard case .text(let content) = editor.document.elements[1].kind else {
      Issue.record("expected text")
      return
    }
    #expect(content.string == "Looks good")
    #expect(stamp(editor)?.3 == editor.document.elements[1].id)
    // Beside the badge: right of it, vertically centered on it.
    let badge = editor.document.elements[0]
    #expect(content.origin.x > badge.bounds.maxX - 1)
    #expect(abs(editor.document.elements[1].bounds.midY - 200) < 1)
    // One undo removes both the label and the link.
    manager.undo()
    #expect(editor.document.elements.count == 1)
    #expect(stamp(editor)?.3 == nil)
  }

  @Test func emptyLabelLeavesNoTraceAndNoLink() {
    let (editor, manager) = makeEditor()
    let (tool, text) = makeTools(editor)
    press(tool, manager, from: CGPoint(x: 200, y: 200))
    #expect(tool.attachLabel(to: editor.document.elements[0].id))
    text.commit(text: "  ")  // registers nothing, so no undo group is needed
    #expect(editor.document.elements.count == 1)
    #expect(stamp(editor)?.3 == nil)
    // The only undo step left is the stamp placement.
    manager.undo()
    #expect(editor.document.elements.isEmpty)
    #expect(!manager.canUndo)
  }

  @Test func labelGoesBelowWhenTailPointsRight() {
    let (editor, manager) = makeEditor()
    let (tool, text) = makeTools(editor)
    press(tool, manager, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 280, y: 200))
    #expect(tool.attachLabel(to: editor.document.elements[0].id))
    commit(text, manager, "Tail right")
    guard case .text(let content) = editor.document.elements[1].kind else {
      Issue.record("expected text")
      return
    }
    #expect(content.origin.y > 200)
  }

  @Test func attachLabelRejectsNonStampsAndDuplicates() {
    let rect = Element(
      kind: .rect(CGRect(x: 10, y: 10, width: 50, height: 50), rounded: false),
      style: Style.make(tool: .rect, imageSize: CGSize(width: 800, height: 600)))
    let (editor, manager) = makeEditor(elements: [rect])
    let (tool, text) = makeTools(editor)
    #expect(!tool.attachLabel(to: rect.id))
    #expect(!tool.attachLabel(to: UUID()))
    editor.deselect()
    press(tool, manager, from: CGPoint(x: 400, y: 300))
    let stampID = editor.document.elements[1].id
    #expect(tool.attachLabel(to: stampID))
    commit(text, manager, "One")
    #expect(!tool.attachLabel(to: stampID))
  }

  @Test func labelLinkSurvivesStampMove() {
    let (editor, manager) = makeEditor()
    let (tool, text) = makeTools(editor)
    press(tool, manager, from: CGPoint(x: 200, y: 200))
    #expect(tool.attachLabel(to: editor.document.elements[0].id))
    commit(text, manager, "Label")
    let labelID = editor.document.elements[1].id
    editor.select(editor.document.elements[0].id)
    manager.beginUndoGrouping()
    editor.moveSelection(by: CGPoint(x: 40, y: 25))
    manager.endUndoGrouping()
    let moved = stamp(editor)
    #expect(moved?.1 == CGPoint(x: 240, y: 225))
    #expect(moved?.3 == labelID)
    // Moving through the tool (drag on the selected stamp) keeps the link too.
    editor.currentTool = .stamp
    manager.beginUndoGrouping()
    tool.mouseDown(at: CGPoint(x: 240, y: 225), modifiers: [])
    tool.mouseDragged(to: CGPoint(x: 300, y: 260), modifiers: [])
    tool.mouseUp(at: CGPoint(x: 300, y: 260), modifiers: [])
    manager.endUndoGrouping()
    #expect(stamp(editor)?.3 == labelID)
  }

  @Test func doubleClickOnStampAttachesThenEditsLabel() {
    let (editor, manager) = makeEditor()
    let (tool, text) = makeTools(editor)
    press(tool, manager, from: CGPoint(x: 200, y: 200))
    tool.mouseDown(at: CGPoint(x: 200, y: 200), modifiers: [], clickCount: 2)
    #expect(text.isEditing)
    commit(text, manager, "First")
    let labelID = stamp(editor)?.3
    #expect(labelID != nil)
    editor.currentTool = .stamp
    tool.mouseDown(at: CGPoint(x: 200, y: 200), modifiers: [], clickCount: 2)
    #expect(text.session?.id == labelID)
    text.cancel()
    #expect(editor.document.elements.count == 2)
  }

  @Test func canvasRegistersStampController() {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    #expect(canvas.activeController is StampToolController)
  }
}
