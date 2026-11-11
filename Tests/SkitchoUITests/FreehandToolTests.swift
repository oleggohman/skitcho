import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct FreehandToolTests {
  private func makeEditor() -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    manager.groupsByEvent = false
    let document = Document.blank(size: CGSize(width: 800, height: 600))
    return (EditorModel(document: document, undoManager: manager), manager)
  }

  private func controller(_ editor: EditorModel, _ tool: Tool, zoom: Double = 1) -> FreehandToolController {
    editor.currentTool = tool
    return FreehandToolController(editor: editor, tool: tool, zoom: { zoom })
  }

  private var wave: [CGPoint] {
    (0...40).map { CGPoint(x: 50 + Double($0) * 8, y: 200 + 40 * sin(Double($0) / 5)) }
  }

  private func stroke(_ tool: FreehandToolController, _ manager: UndoManager, points: [CGPoint]) {
    manager.beginUndoGrouping()
    tool.mouseDown(at: points[0], modifiers: [])
    for point in points.dropFirst() { tool.mouseDragged(to: point, modifiers: []) }
    tool.mouseUp(at: points[points.count - 1], modifiers: [])
    manager.endUndoGrouping()
  }

  @Test func pointStreamProducesOneFreehandElement() {
    let (editor, manager) = makeEditor()
    stroke(controller(editor, .marker), manager, points: wave)
    #expect(editor.document.elements.count == 1)
    guard case .freehand(let segments, let highlighter) = editor.document.elements[0].kind else {
      Issue.record("expected freehand")
      return
    }
    #expect(segments.count >= 1)
    #expect(!highlighter)
    #expect(editor.selection == [editor.document.elements[0].id])
    #expect(editor.document.elements[0].style == editor.nextStyle(for: .marker))
    // The stroke ends where the pointer was released.
    #expect(segments.last?.p3 == wave.last)
  }

  @Test func highlighterIsYellowAndFlagged() {
    let (editor, manager) = makeEditor()
    stroke(controller(editor, .highlighter), manager, points: wave)
    #expect(editor.document.elements.count == 1)
    guard case .freehand(_, let highlighter) = editor.document.elements[0].kind else {
      Issue.record("expected freehand")
      return
    }
    #expect(highlighter)
    #expect(editor.document.elements[0].style.color == .yellow)
  }

  @Test func singlePointIsNoOp() {
    let (editor, manager) = makeEditor()
    let tool = controller(editor, .marker)
    manager.beginUndoGrouping()
    tool.mouseDown(at: CGPoint(x: 100, y: 100), modifiers: [])
    tool.mouseUp(at: CGPoint(x: 100, y: 100), modifiers: [])
    manager.endUndoGrouping()
    #expect(editor.document.elements.isEmpty)
    #expect(!editor.isInteracting)
  }

  @Test func tinyJitterBelowThresholdIsNoOp() {
    let (editor, manager) = makeEditor()
    stroke(
      controller(editor, .marker), manager,
      points: [CGPoint(x: 100, y: 100), CGPoint(x: 101, y: 100), CGPoint(x: 101, y: 101)])
    #expect(editor.document.elements.isEmpty)
  }

  @Test func livePreviewIsInDocumentDuringDrag() {
    let (editor, manager) = makeEditor()
    let tool = controller(editor, .marker)
    manager.beginUndoGrouping()
    tool.mouseDown(at: wave[0], modifiers: [])
    for point in wave[1...10] { tool.mouseDragged(to: point, modifiers: []) }
    #expect(editor.isInteracting)
    #expect(editor.document.elements.count == 1)
    tool.mouseUp(at: wave[10], modifiers: [])
    manager.endUndoGrouping()
    #expect(!editor.isInteracting)
  }

  @Test func strokeIsOneUndoStep() {
    let (editor, manager) = makeEditor()
    stroke(controller(editor, .marker), manager, points: wave)
    manager.undo()
    #expect(editor.document.elements.isEmpty)
    manager.redo()
    #expect(editor.document.elements.count == 1)
  }

  @Test func escapeCancelsStroke() {
    let (editor, _) = makeEditor()
    let tool = controller(editor, .marker)
    tool.mouseDown(at: wave[0], modifiers: [])
    for point in wave[1...10] { tool.mouseDragged(to: point, modifiers: []) }
    #expect(tool.keyDown(.escape, modifiers: []))
    #expect(editor.document.elements.isEmpty)
    #expect(!editor.isInteracting)
  }

  @Test func canvasRegistersFreehandTools() {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    editor.currentTool = .marker
    #expect(canvas.activeController is FreehandToolController)
    editor.currentTool = .highlighter
    #expect(canvas.activeController is FreehandToolController)
  }
}
