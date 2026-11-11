import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

/// Esc ends whatever is in progress and then returns to the Select tool, through the real canvas paths.
@MainActor
@Suite struct EscapeTests {
  private let style = Style(color: .red, sizeStep: .default, strokeWidth: 4, fontSize: 48)

  private func makeCanvas(
    tool: Tool, elements: [Element] = [], image: CGImage? = nil
  ) -> (EditorModel, CanvasView, UndoManager) {
    let manager = UndoManager()
    manager.groupsByEvent = false
    var document = image.map { Document(baseImage: $0) } ?? Document.blank(size: CGSize(width: 400, height: 300))
    document.elements = elements
    let editor = EditorModel(document: document, undoManager: manager)
    editor.currentTool = tool
    let canvas = CanvasView(editor: editor)
    canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
    return (editor, canvas, manager)
  }

  private func solidImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  private func rect(_ r: CGRect) -> Element { Element(kind: .rect(r, rounded: false), style: style) }

  private func textString(_ element: Element) -> String? {
    if case .text(let content) = element.kind { return content.string }
    return nil
  }

  // MARK: Text overlay

  @Test func escapeInTheTextOverlayCommitsAndSelectsTheSelectTool() throws {
    let (editor, canvas, manager) = makeCanvas(tool: .text)
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    canvas.activeController.mouseDown(at: CGPoint(x: 40, y: 40), modifiers: [])
    let overlay = try #require(canvas.textOverlay)
    overlay.string = "kept"
    overlay.didChangeText()

    overlay.cancelOperation(nil)

    #expect(canvas.textOverlay == nil)
    #expect(!canvas.isEditingText)
    #expect(editor.currentTool == .select)
    #expect(editor.document.elements.count == 1)
    #expect(textString(editor.document.elements[0]) == "kept")
  }

  @Test func escapeInAStampLabelOverlayCommitsAndSelectsTheSelectTool() throws {
    let stamp = Element(
      kind: .stamp(.approve, center: CGPoint(x: 100, y: 100), tailAngle: nil, labelID: nil), style: style)
    let (editor, canvas, manager) = makeCanvas(tool: .stamp, elements: [stamp])
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    #expect(canvas.attachLabel(to: stamp.id))
    let overlay = try #require(canvas.textOverlay)
    overlay.string = "note"
    overlay.didChangeText()

    overlay.cancelOperation(nil)

    #expect(canvas.textOverlay == nil)
    #expect(editor.currentTool == .select)
    #expect(editor.document.elements.count == 2)
    #expect(editor.document.elements.contains { textString($0) == "note" })
  }

  @Test func escapeKeyWhileEditingTextCommitsAndSelects() {
    let (editor, canvas, manager) = makeCanvas(tool: .text)
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    canvas.activeController.mouseDown(at: CGPoint(x: 40, y: 40), modifiers: [])
    canvas.textOverlay?.string = "x"
    canvas.textOverlay?.didChangeText()
    #expect(canvas.handleKey(.escape, modifiers: []))
    #expect(!canvas.isEditingText)
    #expect(editor.currentTool == .select)
    #expect(editor.document.elements.count == 1)
    // The committed text stays selected.
    #expect(editor.selection == [editor.document.elements[0].id])
  }

  // MARK: Canvas keys

  @Test func escapeMidDragCancelsTheShapeAndSelectsTheSelectTool() {
    let (editor, canvas, manager) = makeCanvas(tool: .rect)
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    let tool = canvas.activeController
    tool.mouseDown(at: CGPoint(x: 10, y: 10), modifiers: [], clickCount: 1)
    tool.mouseDragged(to: CGPoint(x: 80, y: 60), modifiers: [])
    #expect(editor.document.elements.count == 1)

    #expect(canvas.handleKey(.escape, modifiers: []))
    #expect(editor.document.elements.isEmpty)
    #expect(editor.currentTool == .select)

    // The rest of the gesture now reaches the Select tool: nothing is created and nothing crashes.
    canvas.activeController.mouseDragged(to: CGPoint(x: 120, y: 90), modifiers: [])
    canvas.activeController.mouseUp(at: CGPoint(x: 120, y: 90), modifiers: [])
    // The shape controller itself also ignores stray events after the cancel.
    tool.mouseDragged(to: CGPoint(x: 130, y: 95), modifiers: [])
    tool.mouseUp(at: CGPoint(x: 130, y: 95), modifiers: [])
    #expect(editor.document.elements.isEmpty)
    #expect(editor.currentTool == .select)
  }

  @Test func escapeCancelsAPendingPixelateRegionAndSelectsTheSelectTool() throws {
    let (editor, canvas, _) = makeCanvas(tool: .pixelate, image: solidImage(width: 40, height: 20))
    let tool = try #require(canvas.activeController as? PixelateToolController)
    tool.mouseDown(at: CGPoint(x: 5, y: 5), modifiers: [])
    tool.mouseDragged(to: CGPoint(x: 20, y: 10), modifiers: [])
    tool.mouseUp(at: CGPoint(x: 30, y: 15), modifiers: [])
    #expect(tool.hasPendingRegion)

    #expect(canvas.handleKey(.escape, modifiers: []))
    #expect(tool.region == nil)
    #expect(editor.currentTool == .select)
  }

  @Test func escapeCancelsAPendingCropAndSelectsTheSelectTool() throws {
    let (editor, canvas, manager) = makeCanvas(tool: .crop)
    canvas.editorDidChange()
    let tool = try #require(canvas.activeController as? CropToolController)
    tool.setWidth(50)
    #expect(tool.hasPendingRect)

    #expect(canvas.handleKey(.escape, modifiers: []))
    #expect(!tool.hasPendingRect)
    #expect(editor.currentTool == .select)
    #expect(editor.document.canvasSize == CGSize(width: 400, height: 300))
    #expect(!manager.canUndo)
  }

  @Test func escapeOnSelectClearsTheSelectionAndStaysOnSelect() {
    let element = rect(CGRect(x: 10, y: 10, width: 50, height: 40))
    let (editor, canvas, _) = makeCanvas(tool: .select, elements: [element])
    editor.select(element.id)
    #expect(!editor.selection.isEmpty)

    #expect(canvas.handleKey(.escape, modifiers: []))
    #expect(editor.selection.isEmpty)
    #expect(editor.currentTool == .select)
  }

  @Test func escapeOnAnotherToolKeepsTheSelection() {
    let element = rect(CGRect(x: 10, y: 10, width: 50, height: 40))
    let (editor, canvas, _) = makeCanvas(tool: .arrow, elements: [element])
    editor.select(element.id)

    #expect(canvas.handleKey(.escape, modifiers: []))
    #expect(editor.currentTool == .select)
    #expect(editor.selection == [element.id])
  }
}
