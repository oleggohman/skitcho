import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import SwiftUI
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct PixelateToolTests {
  /// A 40x20 opaque image whose pixel (x, y) is (x * 6, y * 10, 7), counted from the top-left.
  private static func gradientImage() -> CGImage {
    let width = 40
    let height = 20
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let i = (y * width + x) * 4
        bytes[i] = UInt8(x * 6)
        bytes[i + 1] = UInt8(y * 10)
        bytes[i + 2] = 7
        bytes[i + 3] = 255
      }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }

  /// RGBA of the pixel (x, y) from the top-left.
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

  private func makeEditor() -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    manager.groupsByEvent = false
    let editor = EditorModel(document: Document(baseImage: Self.gradientImage()), undoManager: manager)
    editor.currentTool = .pixelate
    return (editor, manager)
  }

  private func drag(_ tool: PixelateToolController, from a: CGPoint, to b: CGPoint) {
    tool.mouseDown(at: a, modifiers: [])
    tool.mouseDragged(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), modifiers: [])
    tool.mouseDragged(to: b, modifiers: [])
    tool.mouseUp(at: b, modifiers: [])
  }

  // MARK: Region

  @Test func dragDefinesRegionAndShowsNothingInTheDocument() {
    let (editor, manager) = makeEditor()
    let tool = PixelateToolController(editor: editor, zoom: { 1 })
    let before = editor.document.baseImage
    drag(tool, from: CGPoint(x: 30, y: 15), to: CGPoint(x: 10, y: 5))
    #expect(tool.region == CGRect(x: 10, y: 5, width: 20, height: 10))
    #expect(tool.hasPendingRegion)
    #expect(editor.document.baseImage === before)
    #expect(!manager.canUndo)
  }

  @Test func tinyDragIsDiscardedAndUsesZoomForTheThreshold() {
    let (editor, _) = makeEditor()
    let tool = PixelateToolController(editor: editor, zoom: { 4 })
    // 3 view points at zoom 4 = 0.75 document px.
    drag(tool, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5.5, y: 5.5))
    #expect(tool.region == nil)
    #expect(!tool.hasPendingRegion)
  }

  @Test func regionIsClippedToTheImage() {
    let (editor, _) = makeEditor()
    let tool = PixelateToolController(editor: editor, zoom: { 1 })
    drag(tool, from: CGPoint(x: -10, y: -10), to: CGPoint(x: 20, y: 25))
    #expect(tool.clippedRegion == CGRect(x: 0, y: 0, width: 20, height: 20))
    drag(tool, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 120, y: 120))
    #expect(tool.clippedRegion == nil)
    #expect(!tool.apply())
  }

  @Test func blockSizeIsClampedToTheSliderRange() {
    let (editor, _) = makeEditor()
    let tool = PixelateToolController(editor: editor, zoom: { 1 })
    tool.blockSize = 1000
    #expect(tool.blockSize == PixelateToolController.blockSizeRange.upperBound)
    tool.blockSize = -3
    #expect(tool.blockSize == PixelateToolController.blockSizeRange.lowerBound)
  }

  // MARK: Apply and cancel

  @Test func applyPixelatesTheClippedRectAsOneUndoStep() throws {
    let (editor, manager) = makeEditor()
    let tool = PixelateToolController(editor: editor, zoom: { 1 })
    let original = editor.document.baseImage
    tool.blockSize = 2
    drag(tool, from: CGPoint(x: -10, y: -10), to: CGPoint(x: 4, y: 4))
    #expect(tool.clippedRegion == CGRect(x: 0, y: 0, width: 4, height: 4))

    manager.beginUndoGrouping()
    #expect(tool.apply())
    manager.endUndoGrouping()

    let result = editor.document.baseImage
    // The 2x2 block at the origin averages x 0 and 6 (3), y 0 and 10 (5); rounding is exact here.
    #expect(pixel(result, 0, 0) == [3, 5, 7, 255])
    #expect(pixel(result, 1, 1) == [3, 5, 7, 255])
    #expect(pixel(result, 5, 5) == pixel(original, 5, 5))  // outside the region
    #expect(tool.region == nil)
    #expect(manager.undoActionName == "Pixelate")

    manager.undo()
    #expect(pixel(editor.document.baseImage, 0, 0) == pixel(original, 0, 0))
    #expect(!manager.canUndo)
  }

  @Test func cancelLeavesTheDocumentUnchanged() {
    let (editor, manager) = makeEditor()
    let tool = PixelateToolController(editor: editor, zoom: { 1 })
    let before = editor.document.baseImage
    drag(tool, from: CGPoint(x: 2, y: 2), to: CGPoint(x: 20, y: 18))
    tool.cancel()
    #expect(tool.region == nil)
    #expect(editor.document.baseImage === before)
    #expect(!manager.canUndo)
    #expect(!tool.apply())
  }

  @Test func returnAppliesAndEscapeCancels() {
    let (editor, manager) = makeEditor()
    let tool = PixelateToolController(editor: editor, zoom: { 1 })
    // No region: keys are not consumed.
    #expect(!tool.keyDown(.escape, modifiers: []))
    #expect(!tool.keyDown(.character("\r"), modifiers: []))

    drag(tool, from: CGPoint(x: 2, y: 2), to: CGPoint(x: 20, y: 18))
    #expect(tool.keyDown(.escape, modifiers: []))
    #expect(tool.region == nil)
    #expect(!manager.canUndo)

    drag(tool, from: CGPoint(x: 2, y: 2), to: CGPoint(x: 20, y: 18))
    manager.beginUndoGrouping()
    #expect(tool.keyDown(.character("\r"), modifiers: []))
    manager.endUndoGrouping()
    #expect(tool.region == nil)
    #expect(manager.undoActionName == "Pixelate")
  }

  @Test func newDragReplacesThePendingRegion() {
    let (editor, _) = makeEditor()
    let tool = PixelateToolController(editor: editor, zoom: { 1 })
    drag(tool, from: CGPoint(x: 2, y: 2), to: CGPoint(x: 10, y: 10))
    drag(tool, from: CGPoint(x: 20, y: 5), to: CGPoint(x: 30, y: 15))
    #expect(tool.region == CGRect(x: 20, y: 5, width: 10, height: 10))
  }

  @Test func overlayPaintsTheRegion() throws {
    let (editor, _) = makeEditor()
    let tool = PixelateToolController(editor: editor, zoom: { 1 })
    drag(tool, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 30, y: 15))
    let context = try #require(
      CGContext(
        data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    tool.overlay(in: context, zoom: 1)
    let image = try #require(context.makeImage())
    // The tinted fill covers the interior (y-up context, so any interior row works); outside stays clear.
    #expect(pixel(image, 15, 10)[3] > 0)
    #expect(pixel(image, 1, 1)[3] == 0)
  }

  // MARK: Canvas integration

  @Test func canvasRegistersTheToolAndShowsTheBarForAPendingRegion() throws {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
    let tool = try #require(canvas.activeController as? PixelateToolController)
    #expect(canvas.pixelateBar == nil)
    drag(tool, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 30, y: 15))
    let bar = try #require(canvas.pixelateBar)
    #expect(bar.superview === canvas)
    #expect(bar.frame.width > 0 && bar.frame.height > 0)
    tool.cancel()
    #expect(canvas.pixelateBar == nil)
  }

  @Test func leavingTheToolDiscardsThePendingRegion() throws {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    let tool = try #require(canvas.activeController as? PixelateToolController)
    drag(tool, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 30, y: 15))
    editor.currentTool = .select
    canvas.editorDidChange()
    #expect(tool.region == nil)
    #expect(canvas.pixelateBar == nil)
  }

  @Test func applyCancelBarIsGenericAndRenders() throws {
    var applied = 0
    var cancelled = 0
    let bar = ApplyCancelBar(
      applyTitle: "Crop", cancelTitle: "Back", onApply: { applied += 1 }, onCancel: { cancelled += 1 },
      content: { Text("Options") })
    bar.onApply()
    bar.onCancel()
    #expect(applied == 1 && cancelled == 1)
    #expect(bar.applyTitle == "Crop" && bar.cancelTitle == "Back")
    let hosting = NSHostingView(rootView: bar)
    #expect(hosting.fittingSize.width > 0)
    let plain = ApplyCancelBar(onApply: {}, onCancel: {})
    #expect(plain.applyTitle == "Apply" && plain.canApply)
  }
}
