import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import SwiftUI
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct CropToolTests {
  private func makeEditor(elements: [Element] = []) -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    manager.groupsByEvent = false
    var document = Document.blank(size: CGSize(width: 200, height: 100))
    document.elements = elements
    let editor = EditorModel(document: document, undoManager: manager)
    editor.currentTool = .crop
    return (editor, manager)
  }

  private func drag(_ tool: CropToolController, from a: CGPoint, to b: CGPoint) {
    tool.mouseDown(at: a, modifiers: [])
    tool.mouseDragged(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), modifiers: [])
    tool.mouseDragged(to: b, modifiers: [])
    tool.mouseUp(at: b, modifiers: [])
  }

  private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let i = (y * image.width + x) * 4
    return Array(bytes[i..<i + 4])
  }

  // MARK: Rect and fields

  @Test func startsAsTheFullCanvasAndCannotApply() {
    let (editor, manager) = makeEditor()
    let tool = CropToolController(editor: editor, zoom: { 1 })
    #expect(tool.rect == CGRect(x: 0, y: 0, width: 200, height: 100))
    #expect(tool.width == 200 && tool.height == 100)
    #expect(!tool.canApply)
    #expect(!tool.apply())
    #expect(!manager.canUndo)
  }

  @Test func newDragDefinesTheRectAndFieldsFollow() {
    let (editor, _) = makeEditor()
    let tool = CropToolController(editor: editor, zoom: { 1 })
    // Press outside any handle but inside the (full) rect would move, so start a fresh rect after shrinking.
    tool.setWidth(100)
    tool.setHeight(50)
    drag(tool, from: CGPoint(x: 150, y: 80), to: CGPoint(x: 110, y: 60))
    #expect(tool.rect == CGRect(x: 110, y: 60, width: 40, height: 20))
    #expect(tool.width == 40 && tool.height == 20)
  }

  @Test func fieldsEditTheRectAndAreClamped() {
    let (editor, _) = makeEditor()
    let tool = CropToolController(editor: editor, zoom: { 1 })
    tool.setWidth(120)
    tool.setHeight(30)
    #expect(tool.rect == CGRect(x: 0, y: 0, width: 120, height: 30))
    #expect(tool.canApply)
    tool.setWidth(9999)
    #expect(tool.width == 200)
    tool.setHeight(0)
    #expect(tool.height == 1)
    // Moving the rect right shrinks what the width field may reach.
    tool.setHeight(50)
    tool.setWidth(100)
    drag(tool, from: CGPoint(x: 50, y: 25), to: CGPoint(x: 100, y: 25))
    #expect(tool.rect.minX == 50)
    tool.setWidth(9999)
    #expect(tool.rect.maxX == 200)
  }

  @Test func resizeHandleKeepsTheOppositeEdgeAndClampsToTheCanvas() {
    let (editor, _) = makeEditor()
    let tool = CropToolController(editor: editor, zoom: { 1 })
    tool.setWidth(100)
    tool.setHeight(50)
    #expect(tool.handle(at: CGPoint(x: 100, y: 50)) == .bottomRight)
    drag(tool, from: CGPoint(x: 100, y: 50), to: CGPoint(x: 300, y: 70))
    #expect(tool.rect == CGRect(x: 0, y: 0, width: 200, height: 70))
    // Dragging the left handle past the right edge stops one pixel short instead of flipping.
    drag(tool, from: CGPoint(x: 0, y: 35), to: CGPoint(x: 500, y: 35))
    #expect(tool.rect.width == 1 && tool.rect.maxX == 200)
  }

  @Test func moveKeepsTheSizeInsideTheCanvas() {
    let (editor, _) = makeEditor()
    let tool = CropToolController(editor: editor, zoom: { 1 })
    tool.setWidth(100)
    tool.setHeight(50)
    drag(tool, from: CGPoint(x: 50, y: 25), to: CGPoint(x: 400, y: 400))
    #expect(tool.rect == CGRect(x: 100, y: 50, width: 100, height: 50))
    drag(tool, from: CGPoint(x: 150, y: 75), to: CGPoint(x: -400, y: -400))
    #expect(tool.rect == CGRect(x: 0, y: 0, width: 100, height: 50))
  }

  @Test func handleHitRadiusShrinksWithZoom() {
    let (editor, _) = makeEditor()
    let tool = CropToolController(editor: editor, zoom: { 4 })
    #expect(tool.handle(at: CGPoint(x: 1, y: 1)) == .topLeft)
    #expect(tool.handle(at: CGPoint(x: 5, y: 5)) == nil)
  }

  // MARK: Apply and cancel

  @Test func applyCropsAsOneUndoStepAndTranslatesElements() throws {
    let arrow = Element(
      kind: .rect(CGRect(x: 60, y: 30, width: 20, height: 10), rounded: false),
      style: Style.make(tool: .rect, sizeStep: .default, color: .red, imageSize: CGSize(width: 200, height: 100)))
    let (editor, manager) = makeEditor(elements: [arrow])
    let tool = CropToolController(editor: editor, zoom: { 1 })
    tool.setWidth(100)
    tool.setHeight(50)
    drag(tool, from: CGPoint(x: 50, y: 25), to: CGPoint(x: 90, y: 45))  // moves the rect to (40, 20)
    #expect(tool.rect == CGRect(x: 40, y: 20, width: 100, height: 50))

    manager.beginUndoGrouping()
    #expect(tool.apply())
    manager.endUndoGrouping()

    #expect(editor.document.canvasSize == CGSize(width: 100, height: 50))
    #expect(editor.document.elements.first?.kind == .rect(CGRect(x: 20, y: 10, width: 20, height: 10), rounded: false))
    #expect(manager.undoActionName == "Crop Image")
    #expect(tool.rect == tool.canvasRect && !tool.canApply)

    manager.undo()
    #expect(editor.document.canvasSize == CGSize(width: 200, height: 100))
    #expect(editor.document.elements.first?.kind == arrow.kind)
    #expect(!manager.canUndo)
  }

  @Test func cancelLeavesTheDocumentUnchanged() {
    let (editor, manager) = makeEditor()
    let tool = CropToolController(editor: editor, zoom: { 1 })
    let before = editor.document
    tool.setWidth(50)
    tool.cancel()
    #expect(tool.rect == tool.canvasRect)
    #expect(editor.document == before)
    #expect(!manager.canUndo)
  }

  @Test func returnAppliesAndEscapeCancels() {
    let (editor, manager) = makeEditor()
    let tool = CropToolController(editor: editor, zoom: { 1 })
    #expect(!tool.keyDown(.escape, modifiers: []))
    #expect(!tool.keyDown(.character("\r"), modifiers: []))

    tool.setWidth(50)
    #expect(tool.keyDown(.escape, modifiers: []))
    #expect(tool.rect == tool.canvasRect)
    #expect(!manager.canUndo)

    tool.setWidth(50)
    manager.beginUndoGrouping()
    #expect(tool.keyDown(.character("\r"), modifiers: []))
    manager.endUndoGrouping()
    #expect(editor.document.canvasSize.width == 50)
    #expect(manager.undoActionName == "Crop Image")
  }

  // MARK: Expand

  @Test func expandGrowsTheCanvasOnTheChosenEdge() {
    let marker = Element(
      kind: .rect(CGRect(x: 10, y: 10, width: 20, height: 10), rounded: false),
      style: Style.make(tool: .rect, sizeStep: .default, color: .red, imageSize: CGSize(width: 200, height: 100)))
    for edge in CanvasEdge.allCases {
      let (editor, manager) = makeEditor(elements: [marker])
      let tool = CropToolController(editor: editor, zoom: { 1 })
      manager.beginUndoGrouping()
      tool.expand(edge)
      manager.endUndoGrouping()

      let horizontal = edge == .left || edge == .right
      let canvas = editor.document.canvasSize
      let expected = CGSize(width: horizontal ? 264 : 200, height: horizontal ? 100 : 164)
      #expect(canvas == expected, "\(edge)")
      #expect(tool.rect == tool.canvasRect, "\(edge)")
      #expect(manager.undoActionName == "Expand Canvas")
      // Space added above or to the left pushes the elements; the other edges leave them in place.
      guard case .rect(let moved, _) = editor.document.elements[0].kind else {
        Issue.record("element kind changed")
        continue
      }
      #expect(moved.minX == (edge == .left ? 74 : 10), "\(edge)")
      #expect(moved.minY == (edge == .top ? 74 : 10), "\(edge)")
      manager.undo()
      #expect(editor.document.canvasSize == CGSize(width: 200, height: 100))
    }
  }

  @Test func expandKeepsACustomRectOnTheSameContent() {
    let (editor, manager) = makeEditor()
    let tool = CropToolController(editor: editor, zoom: { 1 })
    tool.setWidth(100)
    tool.setHeight(50)
    manager.beginUndoGrouping()
    tool.expand(.left)
    manager.endUndoGrouping()
    #expect(tool.rect == CGRect(x: 64, y: 0, width: 100, height: 50))
    manager.beginUndoGrouping()
    tool.expand(.bottom)
    manager.endUndoGrouping()
    #expect(tool.rect == CGRect(x: 64, y: 0, width: 100, height: 50))
    #expect(editor.document.canvasSize == CGSize(width: 264, height: 164))
  }

  @Test func expandBeyondTheSizeGuardSetsAnErrorAndLeavesTheDocument() {
    var document = Document.blank(size: CGSize(width: 16380, height: 10))
    document.elements = []
    let manager = UndoManager()
    manager.groupsByEvent = false
    let editor = EditorModel(document: document, undoManager: manager)
    editor.currentTool = .crop
    let tool = CropToolController(editor: editor, zoom: { 1 })
    tool.expand(.right)
    #expect(tool.errorMessage != nil)
    #expect(editor.document.canvasSize == CGSize(width: 16380, height: 10))
    #expect(!manager.canUndo)
  }

  // MARK: Overlay

  @Test func overlayDimsOutsideAndKeepsTheCropClear() throws {
    let (editor, _) = makeEditor()
    let tool = CropToolController(editor: editor, zoom: { 1 })
    tool.setWidth(100)
    tool.setHeight(50)
    let context = try #require(
      CGContext(
        data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    tool.overlay(in: context, zoom: 1)
    let image = try #require(context.makeImage())
    // The context is y-up while the overlay draws y-down, so bitmap row r (from the top) is document
    // y = 100 - r: row 90 is document y 10 (inside the crop, off the grid lines), row 10 is y 90 (outside).
    #expect(pixel(image, 10, 90)[3] == 0)
    #expect(pixel(image, 10, 10)[3] > 0)
    #expect(pixel(image, 190, 5)[3] > 0)
  }

  // MARK: Canvas integration

  @Test func canvasRegistersTheToolAndShowsTheBarOnlyInCropMode() throws {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
    #expect(canvas.cropBar == nil)
    canvas.editorDidChange()
    let tool = try #require(canvas.activeController as? CropToolController)
    let bar = try #require(canvas.cropBar)
    #expect(bar.superview === canvas)
    #expect(bar.rootView.width == 200 && bar.rootView.height == 100)
    tool.setWidth(80)
    #expect(canvas.cropBar?.rootView.width == 80)
    #expect(canvas.cropBar?.rootView.canApply == true)

    editor.currentTool = .select
    canvas.editorDidChange()
    #expect(canvas.cropBar == nil)
    #expect(tool.rect == tool.canvasRect)
  }

  @Test func barCallbacksDriveTheController() throws {
    let (editor, manager) = makeEditor()
    let canvas = CanvasView(editor: editor)
    canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
    canvas.editorDidChange()
    var bar = try #require(canvas.cropBar).rootView
    bar.onWidth(60)
    bar = try #require(canvas.cropBar).rootView
    #expect(bar.width == 60)
    manager.beginUndoGrouping()
    bar.onExpand(.top)
    manager.endUndoGrouping()
    canvas.editorDidChange()
    #expect(editor.document.canvasSize.height == 164)
    bar = try #require(canvas.cropBar).rootView
    #expect(bar.height == 100)  // custom rect followed the content
    bar.onCancel()
    #expect(try #require(canvas.cropBar).rootView.width == 200)
  }

  @Test func cropBarRenders() throws {
    let bar = CropBar(
      width: 10, height: 20, canApply: true, errorMessage: "Oops", onWidth: { _ in }, onHeight: { _ in },
      onExpand: { _ in }, onApply: {}, onCancel: {})
    #expect(NSHostingView(rootView: bar).fittingSize.width > 0)
  }
}
