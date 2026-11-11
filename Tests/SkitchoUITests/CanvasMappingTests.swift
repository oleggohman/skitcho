import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct CanvasMappingTests {
  private func makeEditor(elements: [Element] = []) -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    // Groups are opened explicitly per gesture; there is no run loop in tests.
    manager.groupsByEvent = false
    var document = Document.blank(size: CGSize(width: 400, height: 300))
    document.elements = elements
    return (EditorModel(document: document, undoManager: manager), manager)
  }

  private func rect(_ x: Double, _ y: Double, _ w: Double = 40, _ h: Double = 30) -> Element {
    Element(
      kind: .rect(CGRect(x: x, y: y, width: w, height: h), rounded: false),
      style: Style.make(tool: .rect, sizeStep: .default, color: .red, imageSize: CGSize(width: 400, height: 300)))
  }

  private func controller(_ editor: EditorModel, zoom: Double = 1) -> SelectPanToolController {
    SelectPanToolController(editor: editor, zoom: { zoom })
  }

  /// Runs one gesture inside its own undo group.
  private func gesture(_ manager: UndoManager, _ body: () -> Void) {
    manager.beginUndoGrouping()
    body()
    manager.endUndoGrouping()
  }

  // MARK: Mapping

  @Test(arguments: [0.25, 1.0, 3.0])
  func viewDocumentMappingRoundTrips(zoom: Double) {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    canvas.setZoom(zoom)
    #expect(canvas.zoom == zoom)
    for point in [CGPoint.zero, CGPoint(x: 123.5, y: 77.25), CGPoint(x: 400, y: 300)] {
      let view = canvas.viewPoint(fromDocument: point)
      let back = canvas.documentPoint(fromView: view)
      #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9)
    }
    // doc = (view - contentOrigin) / zoom
    let geometry = canvas.canvasGeometry
    let view = CGPoint(x: geometry.contentOrigin.x + 10 * zoom, y: geometry.contentOrigin.y + 20 * zoom)
    let doc = canvas.documentPoint(fromView: view)
    #expect(abs(doc.x - 10) < 1e-9 && abs(doc.y - 20) < 1e-9)
  }

  @Test func frameFollowsZoomAndMargin() {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    canvas.setZoom(2)
    #expect(canvas.frame.size == CGSize(width: 800 + 2 * CanvasView.margin, height: 600 + 2 * CanvasView.margin))
    #expect(canvas.canvasGeometry.contentOrigin == CGPoint(x: CanvasView.margin, y: CanvasView.margin))
    #expect(canvas.isFlipped)
  }

  @Test func zoomClampsAndSteps() {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    canvas.setZoom(1000)
    #expect(canvas.zoom == CanvasView.maxZoom)
    canvas.setZoom(0.0001)
    #expect(canvas.zoom == CanvasView.minZoom)
    canvas.actualSize()
    #expect(canvas.zoom == 1)
    canvas.zoomIn()
    #expect(abs(canvas.zoom - CanvasView.zoomStep) < 1e-9)
    canvas.zoomOut()
    #expect(abs(canvas.zoom - 1) < 1e-9)
  }

  @Test func zoomToFitShrinksButNeverEnlarges() {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    canvas.zoomToFit(viewport: CGSize(width: 232, height: 1000))
    let expected = (232 - 2 * CanvasView.margin) / 400
    #expect(abs(canvas.zoom - expected) < 1e-9)
    canvas.zoomToFit(viewport: CGSize(width: 5000, height: 5000))
    #expect(canvas.zoom == 1)
  }

  // MARK: Fit mode

  /// A scroll view hosting a 400 x 300 canvas, laid out at `size` the way the window does.
  private func fittedScrollView(
    size: CGSize = CGSize(width: 232, height: 1000)
  ) -> (NSScrollView, CanvasView, EditorModel) {
    let (editor, _) = makeEditor()
    let (scrollView, canvas) = CanvasView.makeScrollView(editor: editor)
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    resize(scrollView, to: size)
    return (scrollView, canvas, editor)
  }

  private func resize(_ scrollView: NSScrollView, to size: CGSize) {
    scrollView.setFrameSize(size)
    scrollView.layoutSubtreeIfNeeded()
  }

  /// NSEvent cannot be built as a magnify event, so the pinch is faked through the two properties the canvas reads.
  private final class PinchEvent: NSEvent {
    override var magnification: CGFloat { 0.1 }
    override var locationInWindow: NSPoint { .zero }
  }

  private func fitted(_ viewportWidth: Double, canvasWidth: Double = 400) -> Double {
    min((viewportWidth - 2 * CanvasView.margin) / canvasWidth, 1)
  }

  @Test func resizingInFitModeRefitsAndNeverExceedsOne() {
    let (scrollView, canvas, _) = fittedScrollView()
    #expect(canvas.fitMode)
    #expect(abs(canvas.zoom - fitted(232)) < 1e-9)
    resize(scrollView, to: CGSize(width: 316, height: 1000))
    #expect(abs(canvas.zoom - fitted(316)) < 1e-9)
    resize(scrollView, to: CGSize(width: 5000, height: 5000))
    #expect(canvas.zoom == 1)
    #expect(canvas.fitMode)
  }

  @Test func manualZoomLeavesFitModeAndResizeKeepsTheZoom() {
    let (scrollView, canvas, _) = fittedScrollView()
    canvas.zoomIn()
    #expect(!canvas.fitMode)
    let zoomed = canvas.zoom
    resize(scrollView, to: CGSize(width: 500, height: 700))
    #expect(canvas.zoom == zoomed)

    canvas.actualSize()
    #expect(!canvas.fitMode)
    resize(scrollView, to: CGSize(width: 300, height: 700))
    #expect(canvas.zoom == 1)

    canvas.zoomOut()
    #expect(!canvas.fitMode)
    canvas.zoomToFit()
    #expect(canvas.fitMode)
  }

  @Test func zoomToFitReentersFitModeAndSetZoomDoesNotLeaveIt() {
    let (scrollView, canvas, _) = fittedScrollView()
    canvas.actualSize()
    #expect(!canvas.fitMode)
    canvas.zoomToFit()
    #expect(canvas.fitMode)
    #expect(abs(canvas.zoom - fitted(232)) < 1e-9)
    // setZoom is also the fit path itself, so it never changes the mode.
    canvas.setZoom(0.5)
    #expect(canvas.fitMode)
    resize(scrollView, to: CGSize(width: 316, height: 1000))
    #expect(abs(canvas.zoom - fitted(316)) < 1e-9)
  }

  @Test func pinchLeavesFitMode() {
    let (_, canvas, _) = fittedScrollView()
    canvas.magnify(with: PinchEvent())
    #expect(!canvas.fitMode)
  }

  @Test func layoutDoesNotCallBackWhenTheFitIsUnchanged() {
    let (scrollView, canvas, _) = fittedScrollView()
    var calls = 0
    canvas.onZoomChange = { _ in calls += 1 }
    scrollView.needsLayout = true
    scrollView.layoutSubtreeIfNeeded()
    // Same width, different height that does not bind the fit.
    resize(scrollView, to: CGSize(width: 232, height: 1200))
    #expect(calls == 0)
    resize(scrollView, to: CGSize(width: 316, height: 1200))
    #expect(calls == 1)
  }

  @Test func canvasSizeChangeRefitsInFitModeIncludingUndo() throws {
    let (editor, manager) = makeEditor()
    let (scrollView, canvas) = CanvasView.makeScrollView(editor: editor)
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    resize(scrollView, to: CGSize(width: 232, height: 1000))
    #expect(abs(canvas.zoom - fitted(232)) < 1e-9)

    manager.beginUndoGrouping()
    try editor.crop(to: CGRect(x: 0, y: 0, width: 200, height: 150))
    manager.endUndoGrouping()
    canvas.editorDidChange()
    #expect(abs(canvas.zoom - fitted(232, canvasWidth: 200)) < 1e-9)

    manager.undo()
    canvas.editorDidChange()
    #expect(abs(canvas.zoom - fitted(232)) < 1e-9)
  }

  @Test func canvasSizeChangeKeepsTheZoomOutsideFitMode() throws {
    let (editor, manager) = makeEditor()
    let (scrollView, canvas) = CanvasView.makeScrollView(editor: editor)
    resize(scrollView, to: CGSize(width: 232, height: 1000))
    canvas.actualSize()
    manager.beginUndoGrouping()
    try editor.crop(to: CGRect(x: 0, y: 0, width: 200, height: 150))
    manager.endUndoGrouping()
    canvas.editorDidChange()
    #expect(canvas.zoom == 1)
  }

  @Test func cropBarAppearingDoesNotChangeTheZoom() {
    let (editor, _) = makeEditor()
    let (scrollView, canvas) = CanvasView.makeScrollView(editor: editor)
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    resize(scrollView, to: CGSize(width: 232, height: 1000))
    let before = canvas.zoom
    editor.currentTool = .crop
    canvas.editorDidChange()
    #expect(canvas.cropBar != nil)
    #expect(canvas.bottomReserve > 0)
    #expect(canvas.zoom == before)
    scrollView.needsLayout = true
    scrollView.layoutSubtreeIfNeeded()
    // A later window resize does take the reserve into account.
    resize(scrollView, to: CGSize(width: 232, height: 280))
    let reserve = canvas.bottomReserve
    #expect(abs(canvas.zoom - min((280 - 2 * CanvasView.margin - reserve) / 300, before)) < 1e-9)
  }

  @Test func handleTracksFitMode() {
    let (_, canvas, _) = fittedScrollView()
    let handle = CanvasHandle()
    handle.attach(canvas)
    #expect(handle.isFit)
    handle.zoomIn()
    #expect(!handle.isFit)
    handle.zoomToFit()
    #expect(handle.isFit)
    handle.actualSize()
    #expect(!handle.isFit)
  }

  /// A scroll view of `viewport` hosting a canvas for a large document, laid out like the window does.
  private func scrolledCanvas(viewport: CGSize = CGSize(width: 400, height: 300)) -> (NSScrollView, CanvasView) {
    let editor = EditorModel(document: Document.blank(size: CGSize(width: 2000, height: 1500)), undoManager: nil)
    let (scrollView, canvas) = CanvasView.makeScrollView(editor: editor)
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.frame = CGRect(origin: .zero, size: viewport)
    canvas.setZoom(1)
    return (scrollView, canvas)
  }

  private func scroll(_ scrollView: NSScrollView, to origin: CGPoint) {
    scrollView.contentView.scroll(to: origin)
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }

  private func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: Double = 1) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
  }

  /// Zoom buttons keep the document point at the viewport center in place.
  @Test func zoomButtonsKeepTheViewportCenter() {
    let (scrollView, canvas) = scrolledCanvas()
    scroll(scrollView, to: CGPoint(x: 500, y: 400))
    let clip = scrollView.contentView
    let center = { canvas.documentPoint(fromView: CGPoint(x: clip.bounds.midX, y: clip.bounds.midY)) }
    let before = center()
    canvas.zoomIn()
    #expect(near(center(), before))
    canvas.zoomOut()
    canvas.zoomOut()
    #expect(near(center(), before))
  }

  /// A pinch keeps the document point under the pointer in place.
  @Test func pinchZoomKeepsThePointUnderThePointer() {
    let (scrollView, canvas) = scrolledCanvas()
    scroll(scrollView, to: CGPoint(x: 600, y: 300))
    let clip = scrollView.contentView
    let pointer = CGPoint(x: clip.bounds.minX + 50, y: clip.bounds.minY + 60)
    let under = canvas.documentPoint(fromView: pointer)
    canvas.setZoom(2, anchor: pointer)
    let after = canvas.viewPoint(fromDocument: under)
    #expect(near(CGPoint(x: after.x - clip.bounds.minX, y: after.y - clip.bounds.minY), CGPoint(x: 50, y: 60)))
  }

  @Test func canvasAndDragHandleDescribeThemselves() {
    let (editor, _) = makeEditor(elements: [rect(10, 10)])
    let canvas = CanvasView(editor: editor)
    #expect(canvas.isAccessibilityElement())
    #expect(canvas.accessibilityRole() == .group)
    #expect(canvas.accessibilityLabel() == "Canvas")
    #expect(canvas.accessibilityValue() as? String == "400 by 300 pixels, 1 annotation, 0 selected")
    let handle = DragOutHandleView()
    #expect(handle.isAccessibilityElement())
    #expect(handle.accessibilityLabel() == "Drag image out")
  }

  @Test func canvasSizeChangeResizesFrame() {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    editor.document = Document.blank(size: CGSize(width: 100, height: 50))
    canvas.updateFrameSize()
    #expect(canvas.frame.size == CGSize(width: 100 + 2 * CanvasView.margin, height: 50 + 2 * CanvasView.margin))
  }

  @Test func drawingRendersDocumentUprightAtContentOrigin() throws {
    // A red rect near the top of the document must show near the top of the view (flipped view, y-down).
    var document = Document.blank(size: CGSize(width: 100, height: 100))
    document.elements = [
      Element(
        kind: .rect(CGRect(x: 0, y: 0, width: 100, height: 20), rounded: false),
        style: Style.make(tool: .rect, sizeStep: .default, color: .red, imageSize: CGSize(width: 100, height: 100)))
    ]
    let editor = EditorModel(document: document, undoManager: nil)
    let canvas = CanvasView(editor: editor)
    canvas.setZoom(1)
    let window = NSWindow(
      contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = canvas
    let rep = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
    canvas.cacheDisplay(in: canvas.bounds, to: rep)
    let origin = canvas.canvasGeometry.contentOrigin
    let top = try #require(rep.colorAt(x: Int(origin.x) + 50, y: Int(origin.y) + 1)?.usingColorSpace(.sRGB))
    let bottom = try #require(rep.colorAt(x: Int(origin.x) + 50, y: Int(origin.y) + 98)?.usingColorSpace(.sRGB))
    // Stroke is red-ish at the top edge; the bottom edge stays white.
    #expect(top.redComponent > 0.8 && top.blueComponent < 0.7)
    #expect(bottom.redComponent > 0.95 && bottom.blueComponent > 0.95)
    window.contentView = nil
  }

  // MARK: Controller protocol and cursors

  @Test func canvasForwardsToRegisteredControllerElseSelect() {
    let (editor, _) = makeEditor()
    let canvas = CanvasView(editor: editor)
    #expect(canvas.activeController is SelectPanToolController)
    editor.currentTool = .crop
    // Every tool with a real controller is registered by default; drop crop's to exercise the fallback.
    canvas.unregister(.crop)
    #expect(canvas.activeController is SelectPanToolController)
    let custom = controller(editor)
    canvas.register(custom, for: .crop)
    #expect(canvas.activeController === custom)
  }

  @Test func everyToolHasValidCursorSymbol() {
    for tool in Tool.allCases {
      if let name = ToolCursors.symbolName(for: tool) {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(tool): \(name)")
        let cursor = ToolCursors.cursor(for: tool)
        #expect(cursor.image.size.width > 0)
      } else {
        #expect(tool == .select)
        #expect(ToolCursors.cursor(for: tool) == NSCursor.arrow)
      }
    }
  }

  @Test func modifiersMapFromEventFlags() {
    let mods = ToolModifiers([.shift, .command])
    #expect(mods.contains(.shift) && mods.contains(.command) && !mods.contains(.option))
  }

  // MARK: V tool

  @Test func clickSelectsTopMostHit() {
    let bottom = rect(10, 10)
    let top = rect(10, 10)  // identical outline, above
    let (editor, _) = makeEditor(elements: [bottom, top])
    let tool = controller(editor)
    tool.mouseDown(at: CGPoint(x: 10, y: 25), modifiers: [])  // on the left edge
    tool.mouseUp(at: CGPoint(x: 10, y: 25), modifiers: [])
    #expect(editor.selection == [top.id])
  }

  @Test func clickOnEmptySpaceDeselects() {
    let element = rect(10, 10)
    let (editor, _) = makeEditor(elements: [element])
    editor.select(element.id)
    let tool = controller(editor)
    tool.mouseDown(at: CGPoint(x: 300, y: 250), modifiers: [])
    tool.mouseUp(at: CGPoint(x: 300, y: 250), modifiers: [])
    #expect(editor.selection.isEmpty)
  }

  @Test func hitToleranceShrinksWithZoom() {
    let element = rect(100, 100)
    let (editor, _) = makeEditor(elements: [element])
    // 10 document units off the left edge: inside slop at 0.25 (24 units), outside at 3 (2 units).
    let point = CGPoint(x: 90, y: 115)
    let far = controller(editor, zoom: 3)
    far.mouseDown(at: point, modifiers: [])
    far.mouseUp(at: point, modifiers: [])
    #expect(editor.selection.isEmpty)
    let near = controller(editor, zoom: 0.25)
    near.mouseDown(at: point, modifiers: [])
    near.mouseUp(at: point, modifiers: [])
    #expect(editor.selection == [element.id])
  }

  @Test func shiftClickTogglesSelection() {
    let a = rect(10, 10)
    let b = rect(200, 10)
    let (editor, _) = makeEditor(elements: [a, b])
    let tool = controller(editor)
    tool.mouseDown(at: CGPoint(x: 10, y: 25), modifiers: [])
    tool.mouseUp(at: CGPoint(x: 10, y: 25), modifiers: [])
    tool.mouseDown(at: CGPoint(x: 200, y: 25), modifiers: .shift)
    tool.mouseUp(at: CGPoint(x: 200, y: 25), modifiers: .shift)
    #expect(editor.selection == [a.id, b.id])
    tool.mouseDown(at: CGPoint(x: 200, y: 25), modifiers: .shift)
    tool.mouseUp(at: CGPoint(x: 200, y: 25), modifiers: .shift)
    #expect(editor.selection == [a.id])
  }

  @Test func dragMovesWithOneUndoStep() {
    let element = rect(10, 10)
    let (editor, manager) = makeEditor(elements: [element])
    let tool = controller(editor)
    gesture(manager) {
      tool.mouseDown(at: CGPoint(x: 10, y: 25), modifiers: [])
      tool.mouseDragged(to: CGPoint(x: 30, y: 35), modifiers: [])
      tool.mouseDragged(to: CGPoint(x: 60, y: 75), modifiers: [])
      tool.mouseUp(at: CGPoint(x: 60, y: 75), modifiers: [])
    }
    #expect(editor.document.elements[0].baseBounds.origin == CGPoint(x: 60, y: 60))
    #expect(editor.selection == [element.id])
    #expect(manager.undoActionName == "Move")
    manager.undo()
    #expect(editor.document.elements[0].baseBounds.origin == CGPoint(x: 10, y: 10))
    #expect(!manager.canUndo)
    manager.redo()
    #expect(editor.document.elements[0].baseBounds.origin == CGPoint(x: 60, y: 60))
  }

  @Test func clickWithoutDragRegistersNoUndo() {
    let element = rect(10, 10)
    let (editor, manager) = makeEditor(elements: [element])
    let tool = controller(editor, zoom: 1)
    tool.mouseDown(at: CGPoint(x: 10, y: 25), modifiers: [])
    tool.mouseDragged(to: CGPoint(x: 11, y: 25), modifiers: [])  // below the drag threshold
    tool.mouseUp(at: CGPoint(x: 11, y: 25), modifiers: [])
    #expect(editor.document.elements[0].baseBounds.origin == CGPoint(x: 10, y: 10))
    #expect(!manager.canUndo)
  }

  @Test func dragMovesAllSelectedElements() {
    let a = rect(10, 10)
    let b = rect(200, 10)
    let (editor, manager) = makeEditor(elements: [a, b])
    editor.select(ids: [a.id, b.id])
    let tool = controller(editor)
    gesture(manager) {
      tool.mouseDown(at: CGPoint(x: 10, y: 25), modifiers: [])
      tool.mouseDragged(to: CGPoint(x: 10, y: 55), modifiers: [])
      tool.mouseUp(at: CGPoint(x: 10, y: 55), modifiers: [])
    }
    #expect(editor.document.elements.map { $0.baseBounds.origin.y } == [40, 40])
    #expect(editor.selection == [a.id, b.id])
  }

  @Test func marqueeSelectsContainedElements() {
    let inside = rect(20, 20)
    let straddling = rect(90, 20)
    let outside = rect(300, 200)
    let (editor, manager) = makeEditor(elements: [inside, straddling, outside])
    let tool = controller(editor)
    var sawMarquee = false
    tool.mouseDown(at: CGPoint(x: 5, y: 5), modifiers: [])
    tool.mouseDragged(to: CGPoint(x: 100, y: 80), modifiers: [])
    sawMarquee = tool.marqueeRect == CGRect(x: 5, y: 5, width: 95, height: 75)
    tool.mouseUp(at: CGPoint(x: 100, y: 80), modifiers: [])
    #expect(sawMarquee)
    #expect(tool.marqueeRect == nil)
    #expect(editor.selection == [inside.id])
    #expect(!manager.canUndo)
  }

  @Test func marqueeWorksFromAnyCorner() {
    let element = rect(20, 20)
    let (editor, _) = makeEditor(elements: [element])
    let tool = controller(editor)
    tool.mouseDown(at: CGPoint(x: 100, y: 80), modifiers: [])
    tool.mouseDragged(to: CGPoint(x: 5, y: 5), modifiers: [])
    tool.mouseUp(at: CGPoint(x: 5, y: 5), modifiers: [])
    #expect(editor.selection == [element.id])
  }

  @Test func shiftMarqueeExtendsSelection() {
    let a = rect(20, 20)
    let b = rect(250, 200)
    let (editor, _) = makeEditor(elements: [a, b])
    editor.select(b.id)
    let tool = controller(editor)
    tool.mouseDown(at: CGPoint(x: 5, y: 5), modifiers: .shift)
    tool.mouseDragged(to: CGPoint(x: 100, y: 80), modifiers: .shift)
    tool.mouseUp(at: CGPoint(x: 100, y: 80), modifiers: .shift)
    #expect(editor.selection == [a.id, b.id])
  }

  @Test func keysDeleteNudgeAndDeselect() {
    let element = rect(10, 10)
    let (editor, manager) = makeEditor(elements: [element])
    let tool = controller(editor)
    #expect(!tool.keyDown(.delete, modifiers: []))
    #expect(!tool.keyDown(.arrow(dx: 1, dy: 0), modifiers: []))
    editor.select(element.id)
    gesture(manager) { #expect(tool.keyDown(.arrow(dx: 1, dy: 0), modifiers: [])) }
    gesture(manager) { #expect(tool.keyDown(.arrow(dx: 0, dy: 1), modifiers: .shift)) }
    #expect(editor.document.elements[0].baseBounds.origin == CGPoint(x: 11, y: 20))
    #expect(tool.keyDown(.escape, modifiers: []))
    #expect(editor.selection.isEmpty)
    #expect(!tool.keyDown(.escape, modifiers: []))
    editor.select(element.id)
    gesture(manager) { #expect(tool.keyDown(.delete, modifiers: [])) }
    #expect(editor.document.elements.isEmpty)
    #expect(!tool.keyDown(.character("x"), modifiers: []))
  }

  @Test func escapeDuringDragCancelsTheMove() {
    let element = rect(10, 10)
    let (editor, manager) = makeEditor(elements: [element])
    let tool = controller(editor)
    tool.mouseDown(at: CGPoint(x: 10, y: 25), modifiers: [])
    tool.mouseDragged(to: CGPoint(x: 50, y: 25), modifiers: [])
    #expect(tool.keyDown(.escape, modifiers: []))
    tool.mouseUp(at: CGPoint(x: 50, y: 25), modifiers: [])
    #expect(editor.document.elements[0].baseBounds.origin == CGPoint(x: 10, y: 10))
    #expect(!manager.canUndo)
  }

  @Test func overlayDrawsHandlesForSingleSelection() throws {
    let element = rect(20, 20, 60, 40)
    let (editor, _) = makeEditor(elements: [element])
    editor.select(element.id)
    let tool = controller(editor)
    let context = try #require(
      CGContext(
        data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    // Document space is y-down: flip the y-up bitmap context like the canvas does.
    context.translateBy(x: 0, y: 300)
    context.scaleBy(x: 1, y: -1)
    tool.overlay(in: context, zoom: 1)
    let image = try #require(context.makeImage())
    let data = try #require(image.dataProvider?.data)
    let bytes = CFDataGetBytePtr(data)!
    // The element's top-left corner handle (20,20) is filled blue; bitmap row 0 is the top row.
    let offset = 20 * image.bytesPerRow + 20 * 4
    #expect(bytes[offset + 3] > 200)
    #expect(bytes[offset + 2] > bytes[offset])  // blue channel dominates red
  }
}
