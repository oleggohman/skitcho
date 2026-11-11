import AppKit
import CoreGraphics
import Observation
import SkitchoCore
import SwiftUI

import struct SkitchoCore.Document

/// View <-> document mapping: `doc = (view - contentOrigin) / zoom` (the view is flipped, so both are y-down).
public struct CanvasGeometry: Equatable, Sendable {
  public var zoom: Double
  public var contentOrigin: CGPoint

  public init(zoom: Double, contentOrigin: CGPoint) {
    self.zoom = zoom
    self.contentOrigin = contentOrigin
  }

  public func documentPoint(fromView point: CGPoint) -> CGPoint {
    CGPoint(x: (point.x - contentOrigin.x) / zoom, y: (point.y - contentOrigin.y) / zoom)
  }

  public func viewPoint(fromDocument point: CGPoint) -> CGPoint {
    CGPoint(x: point.x * zoom + contentOrigin.x, y: point.y * zoom + contentOrigin.y)
  }

  /// The canvas rectangle in view coordinates.
  public func viewRect(canvasSize: CGSize) -> CGRect {
    CGRect(origin: contentOrigin, size: CGSize(width: canvasSize.width * zoom, height: canvasSize.height * zoom))
  }
}

/// The editing surface: renders the document with `DocumentRenderer` on a themed surround, maps pointer
/// input to document points and forwards it to the active `ToolController`. Meant to be the document view of
/// an `NSScrollView` (see `makeScrollView`); it sizes itself to the zoomed canvas plus a margin, or to the
/// viewport when that is larger (the canvas is then centered).
@MainActor
public final class CanvasView: NSView {
  public static let minZoom = 0.1
  public static let maxZoom = 16.0
  public static let zoomStep = 1.25
  /// Space around the canvas inside the surround (view points).
  public static let margin: CGFloat = Spacing.lg

  public let editor: EditorModel
  public private(set) var zoom: Double = 1
  /// Called after every zoom change so the shell can show the zoom level.
  public var onZoomChange: ((Double) -> Void)?
  /// Called before the canvas handles a mouse press or key, so the shell can end pending panel gestures
  /// (a debounced custom color) before a canvas gesture opens its own.
  public var willHandleInput: (() -> Void)?

  private var controllers: [Tool: any ToolController] = [:]
  private let selectController: SelectPanToolController
  private var textController: TextToolController?
  private var stampController: StampToolController?
  private var pixelateController: PixelateToolController?
  /// Options bar (block size, Apply/Cancel) shown below a pending pixelate region.
  private(set) var pixelateBar: NSHostingView<PixelateBar>?
  private var cropController: CropToolController?
  /// Options bar (W×H, expand edges, Apply/Cancel) shown below the canvas while the crop tool is active.
  private(set) var cropBar: NSHostingView<CropBar>?
  /// The NSTextView shown over the canvas while a text element is edited.
  private(set) var textOverlay: TextEditorOverlay?
  private var spaceDown = false
  private var panLast: CGPoint?
  private var lastCanvasSize: CGSize

  public init(editor: EditorModel) {
    self.editor = editor
    self.lastCanvasSize = editor.document.canvasSize
    // `zoom` is read lazily, after self exists, through the box below.
    let box = ZoomBox()
    self.zoomBox = box
    self.selectController = SelectPanToolController(editor: editor, zoom: { box.value })
    super.init(frame: .zero)
    controllers[.select] = selectController
    selectController.needsDisplay = { [weak self] in self?.needsDisplay = true }
    for tool in ShapeToolController.supportedTools {
      register(ShapeToolController(editor: editor, tool: tool, zoom: { box.value }), for: tool)
    }
    for tool in FreehandToolController.supportedTools {
      register(FreehandToolController(editor: editor, tool: tool, zoom: { box.value }), for: tool)
    }
    let text = TextToolController(editor: editor, zoom: { box.value })
    text.editingDidChange = { [weak self] in self?.syncTextOverlay() }
    textController = text
    register(text, for: .text)
    let stamp = StampToolController(editor: editor, zoom: { box.value }, labelEditor: text)
    stampController = stamp
    register(stamp, for: .stamp)
    let pixelate = PixelateToolController(editor: editor, zoom: { box.value })
    pixelate.stateDidChange = { [weak self] in self?.syncPixelateBar() }
    pixelateController = pixelate
    register(pixelate, for: .pixelate)
    let crop = CropToolController(editor: editor, zoom: { box.value })
    crop.stateDidChange = { [weak self] in self?.syncCropBar() }
    cropController = crop
    register(crop, for: .crop)
    updateFrameSize()
    observeEditor()
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Shares the current zoom with controllers created before `self` was available.
  private final class ZoomBox: @unchecked Sendable {
    var value: Double = 1
  }
  private let zoomBox: ZoomBox

  public override var isFlipped: Bool { true }
  public override var acceptsFirstResponder: Bool { true }

  // MARK: Accessibility

  // A group, so the option bars and the text editor inside it stay reachable.
  public override func isAccessibilityElement() -> Bool { true }
  public override func accessibilityRole() -> NSAccessibility.Role? { .group }
  public override func accessibilityLabel() -> String? { "Canvas" }
  public override func accessibilityValue() -> Any? {
    let size = editor.document.canvasSize
    let count = editor.document.elements.count
    return "\(Int(size.width.rounded())) by \(Int(size.height.rounded())) pixels, "
      + "\(count) \(count == 1 ? "annotation" : "annotations"), \(editor.selection.count) selected"
  }

  // MARK: Controllers

  /// Registers the controller used while `tool` is current. Tools without a controller use the V tool's.
  public func register(_ controller: some ToolController, for tool: Tool) {
    controller.needsDisplay = { [weak self] in self?.needsDisplay = true }
    controllers[tool] = controller
    window?.invalidateCursorRects(for: self)
  }

  /// Removes the controller of `tool`, so it falls back to the V tool's (test seam and tool teardown).
  public func unregister(_ tool: Tool) {
    controllers[tool] = nil
    window?.invalidateCursorRects(for: self)
  }

  /// Starts a label on the stamp `id` (the properties panel's "Attach Label"); false when not possible.
  @discardableResult
  public func attachLabel(to id: UUID) -> Bool {
    stampController?.attachLabel(to: id) ?? false
  }

  public var activeController: any ToolController { controllers[editor.currentTool] ?? selectController }

  // MARK: Geometry

  public var canvasGeometry: CanvasGeometry { CanvasGeometry(zoom: zoom, contentOrigin: contentOrigin()) }

  public func documentPoint(fromView point: CGPoint) -> CGPoint { canvasGeometry.documentPoint(fromView: point) }

  public func viewPoint(fromDocument point: CGPoint) -> CGPoint { canvasGeometry.viewPoint(fromDocument: point) }

  /// Visible size of the enclosing scroll view, or nil when not hosted in one.
  private var viewportSize: CGSize? { enclosingScrollView?.contentSize }

  /// Room kept below the canvas for the crop bar while it is shown, so the bar never covers the canvas edge
  /// where the crop handles are.
  var bottomReserve: CGFloat {
    guard let cropBar else { return 0 }
    return cropBar.fittingSize.height + Spacing.xs
  }

  private func contentOrigin() -> CGPoint {
    let canvas = editor.document.canvasSize
    return CGPoint(
      x: max(Self.margin, (frame.width - canvas.width * zoom) / 2),
      y: max(Self.margin, (frame.height - bottomReserve - canvas.height * zoom) / 2))
  }

  /// Resizes the view to the zoomed canvas plus margins and the bar reserve (or the viewport, when larger).
  public func updateFrameSize() {
    let canvas = editor.document.canvasSize
    let viewport = viewportSize ?? .zero
    let size = CGSize(
      width: max(canvas.width * zoom + 2 * Self.margin, viewport.width),
      height: max(canvas.height * zoom + 2 * Self.margin + bottomReserve, viewport.height))
    if frame.size != size { setFrameSize(size) }
    layoutTextOverlay()
    layoutPixelateBar()
    layoutCropBar()
    needsDisplay = true
  }

  // MARK: Zoom

  /// Sets the zoom and keeps the document point under `anchor` (view coordinates) where it is on screen; the
  /// anchor defaults to the center of the visible area.
  public func setZoom(_ value: Double, anchor: CGPoint? = nil) {
    let clip = enclosingScrollView?.contentView
    let anchorView = anchor ?? clip.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
    let anchorDocument = anchorView.map { documentPoint(fromView: $0) }
    zoom = min(max(value, Self.minZoom), Self.maxZoom)
    zoomBox.value = zoom
    updateFrameSize()
    if let scrollView = enclosingScrollView, let clip, let anchorView, let anchorDocument {
      // The clip view shares the canvas's (flipped) coordinates, so its origin moves with the anchor.
      let moved = viewPoint(fromDocument: anchorDocument)
      let origin = CGPoint(
        x: clip.bounds.minX + moved.x - anchorView.x, y: clip.bounds.minY + moved.y - anchorView.y)
      clip.scroll(to: clip.constrainBoundsRect(CGRect(origin: origin, size: clip.bounds.size)).origin)
      scrollView.reflectScrolledClipView(clip)
    }
    window?.invalidateCursorRects(for: self)
    onZoomChange?(zoom)
  }

  public func zoomIn() { setZoom(zoom * Self.zoomStep) }
  public func zoomOut() { setZoom(zoom / Self.zoomStep) }
  public func actualSize() { setZoom(1) }

  /// Fits the canvas into `viewport` (never above 100%). Uses the scroll view size when omitted.
  public func zoomToFit(viewport: CGSize? = nil) {
    guard let size = viewport ?? viewportSize else { return }
    let canvas = editor.document.canvasSize
    guard canvas.width > 0, canvas.height > 0 else { return }
    let fitX = (size.width - 2 * Self.margin) / canvas.width
    let fitY = (size.height - 2 * Self.margin - bottomReserve) / canvas.height
    setZoom(min(fitX, fitY, 1))
  }

  public override func magnify(with event: NSEvent) {
    setZoom(zoom * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil))
  }

  // MARK: Observation

  private func observeEditor() {
    withObservationTracking {
      _ = editor.document
      _ = editor.selection
      _ = editor.currentTool
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.editorDidChange()
        self?.observeEditor()
      }
    }
  }

  func editorDidChange() {
    let size = editor.document.canvasSize
    if size != lastCanvasSize {
      lastCanvasSize = size
      updateFrameSize()
    }
    if let textController, textController.isEditing {
      // An undo that ran during the edit ended its gesture; close the editor without applying it.
      if !editor.isInteracting {
        textController.cancel()
      } else if editor.currentTool != .text {
        textController.commit()
      }
    }
    if editor.currentTool != .pixelate, pixelateController?.region != nil { pixelateController?.cancel() }
    if editor.currentTool != .crop, cropController?.hasPendingRect == true { cropController?.cancel() }
    syncCropBar()
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  // MARK: Text editing overlay

  /// Creates, updates or removes the in-place text editor to match the text controller's session.
  private func syncTextOverlay() {
    guard let session = textController?.session else {
      removeTextOverlay()
      return
    }
    if textOverlay?.sessionID != session.id {
      removeTextOverlay()
      let overlay = TextEditorOverlay(sessionID: session.id, string: session.string)
      overlay.onTextChange = { [weak self] string in self?.textController?.update(text: string) }
      overlay.onCommit = { [weak self] string in self?.textController?.commit(text: string) }
      addSubview(overlay)
      textOverlay = overlay
      layoutTextOverlay()
      window?.makeFirstResponder(overlay)
      overlay.setSelectedRange(NSRange(location: (overlay.string as NSString).length, length: 0))
    }
    layoutTextOverlay()
    needsDisplay = true
  }

  private func removeTextOverlay() {
    guard let overlay = textOverlay else { return }
    textOverlay = nil
    // Detach first: removing the first responder triggers resignFirstResponder, which must not commit again.
    overlay.onCommit = nil
    overlay.onTextChange = nil
    overlay.removeFromSuperview()
    window?.makeFirstResponder(self)
  }

  /// Matches the overlay to the edited element at the current zoom.
  private func layoutTextOverlay() {
    guard let overlay = textOverlay, let session = textController?.session else { return }
    overlay.apply(session: session, geometry: canvasGeometry)
  }

  // MARK: Pixelate options bar

  /// Shows, updates or removes the options bar to match the pixelate controller's pending region.
  private func syncPixelateBar() {
    guard let controller = pixelateController, controller.hasPendingRegion else {
      pixelateBar?.removeFromSuperview()
      pixelateBar = nil
      return
    }
    let bar = PixelateBar(
      blockSize: controller.blockSize,
      canApply: true,
      errorMessage: controller.errorMessage,
      onBlockSize: { [weak controller] in controller?.blockSize = $0 },
      onApply: { [weak controller] in controller?.apply() },
      onCancel: { [weak controller] in controller?.cancel() })
    if let hosting = pixelateBar {
      hosting.rootView = bar
    } else {
      let hosting = NSHostingView(rootView: bar)
      addSubview(hosting)
      pixelateBar = hosting
    }
    layoutPixelateBar()
  }

  /// Places the bar centered below the region (above it when there is no room), inside the view.
  private func layoutPixelateBar() {
    guard let hosting = pixelateBar, let region = pixelateController?.clippedRegion else { return }
    let size = hosting.fittingSize
    let geometry = canvasGeometry
    let topLeft = geometry.viewPoint(fromDocument: region.origin)
    let bottomRight = geometry.viewPoint(fromDocument: CGPoint(x: region.maxX, y: region.maxY))
    var x = (topLeft.x + bottomRight.x) / 2 - size.width / 2
    var y = bottomRight.y + Spacing.xs
    if y + size.height > bounds.maxY { y = max(topLeft.y - size.height - Spacing.xs, bounds.minY) }
    x = min(max(x, bounds.minX), max(bounds.maxX - size.width, bounds.minX))
    hosting.frame = CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
  }

  // MARK: Crop options bar

  /// Shows, updates or removes the crop bar: it is present exactly while the crop tool is current.
  private func syncCropBar() {
    guard let controller = cropController, editor.currentTool == .crop else {
      guard let bar = cropBar else { return }
      bar.removeFromSuperview()
      cropBar = nil
      updateFrameSize()
      return
    }
    let bar = CropBar(
      width: controller.width, height: controller.height, canApply: controller.canApply,
      errorMessage: controller.errorMessage,
      onWidth: { [weak controller] in controller?.setWidth($0) },
      onHeight: { [weak controller] in controller?.setHeight($0) },
      onExpand: { [weak controller] in controller?.expand($0) },
      onApply: { [weak controller] in controller?.apply() },
      onCancel: { [weak controller] in controller?.cancel() })
    if let hosting = cropBar {
      hosting.rootView = bar
    } else {
      let hosting = NSHostingView(rootView: bar)
      addSubview(hosting)
      cropBar = hosting
    }
    // The bar's height is reserved below the canvas (it grows with an error line).
    updateFrameSize()
  }

  /// Centers the bar under the canvas (inside the view's bottom edge when there is no room below).
  private func layoutCropBar() {
    guard let hosting = cropBar else { return }
    let size = hosting.fittingSize
    let canvas = canvasGeometry.viewRect(canvasSize: editor.document.canvasSize)
    var y = canvas.maxY + Spacing.xs
    if y + size.height > bounds.maxY { y = max(bounds.maxY - size.height - Spacing.xs, bounds.minY) }
    let x = min(max(canvas.midX - size.width / 2, bounds.minX), max(bounds.maxX - size.width, bounds.minX))
    hosting.frame = CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
  }

  // MARK: Drawing

  public override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let geometry = canvasGeometry
    let canvas = editor.document.canvasSize

    // Themed surround (CloudZone: rounded panel behind the canvas).
    var surround = BrandColor.paleBlue.nsColor().cgColor
    effectiveAppearance.performAsCurrentDrawingAppearance {
      surround = BrandSemantic.canvasSurround.nsColor.cgColor
    }
    context.setFillColor(surround)
    context.addPath(
      CGPath(roundedRect: bounds, cornerWidth: Radius.large, cornerHeight: Radius.large, transform: nil))
    context.fillPath()

    // The view context is flipped (y-down). Undo that so DocumentRenderer, which expects a y-up context of
    // canvasSize * zoom pixels, draws upright at contentOrigin.
    let canvasRect = geometry.viewRect(canvasSize: canvas)
    context.saveGState()
    context.clip(to: canvasRect)
    context.translateBy(x: canvasRect.minX, y: canvasRect.maxY)
    context.scaleBy(x: 1, y: -1)
    DocumentRenderer.draw(editor.document, in: context, scale: zoom, shadows: true)
    context.restoreGState()

    // Overlay in document space (y-down, flipped view context as is).
    context.saveGState()
    context.translateBy(x: geometry.contentOrigin.x, y: geometry.contentOrigin.y)
    context.scaleBy(x: zoom, y: zoom)
    activeController.overlay(in: context, zoom: zoom)
    context.restoreGState()
  }

  // MARK: Cursor

  public override func resetCursorRects() {
    let cursor: NSCursor = spaceDown ? (panLast == nil ? .openHand : .closedHand) : activeController.cursor
    addCursorRect(visibleRect, cursor: cursor)
  }

  // MARK: Mouse

  private func docPoint(_ event: NSEvent) -> CGPoint {
    documentPoint(fromView: convert(event.locationInWindow, from: nil))
  }

  public override func mouseDown(with event: NSEvent) {
    willHandleInput?()
    // A press on the canvas while text is being edited only ends the edit.
    if let textController, textController.isEditing {
      textController.commit()
      window?.makeFirstResponder(self)
      return
    }
    window?.makeFirstResponder(self)
    if spaceDown {
      panLast = event.locationInWindow
      window?.invalidateCursorRects(for: self)
      return
    }
    activeController.mouseDown(
      at: docPoint(event), modifiers: ToolModifiers(event.modifierFlags), clickCount: event.clickCount)
  }

  public override func mouseDragged(with event: NSEvent) {
    if let last = panLast {
      pan(byWindowDelta: CGPoint(x: event.locationInWindow.x - last.x, y: event.locationInWindow.y - last.y))
      panLast = event.locationInWindow
      return
    }
    activeController.mouseDragged(to: docPoint(event), modifiers: ToolModifiers(event.modifierFlags))
  }

  public override func mouseUp(with event: NSEvent) {
    if panLast != nil {
      panLast = nil
      window?.invalidateCursorRects(for: self)
      return
    }
    activeController.mouseUp(at: docPoint(event), modifiers: ToolModifiers(event.modifierFlags))
  }

  /// Scrolls so the content follows the pointer (window y is up, the view is flipped).
  private func pan(byWindowDelta delta: CGPoint) {
    guard let scrollView = enclosingScrollView else { return }
    let clip = scrollView.contentView
    clip.scroll(to: CGPoint(x: clip.bounds.origin.x - delta.x, y: clip.bounds.origin.y + delta.y))
    scrollView.reflectScrolledClipView(clip)
  }

  // MARK: Keyboard

  public override func keyDown(with event: NSEvent) {
    willHandleInput?()
    let modifiers = ToolModifiers(event.modifierFlags)
    if event.keyCode == 49 && !event.isARepeat {  // Space: pan mode while held
      spaceDown = true
      window?.invalidateCursorRects(for: self)
      return
    }
    if let key = Self.toolKey(for: event), handleKey(key, modifiers: modifiers) { return }
    super.keyDown(with: event)
  }

  /// True while a text element is being edited (keys then belong to the text editor).
  public var isEditingText: Bool { textController?.isEditing ?? false }

  /// The document to save: like `editor.document`, but with a running text edit's live string in place.
  /// The text controller remembers it, so ending the edit on a different document marks it edited.
  public var savableDocument: Document { textController?.documentForSaving() ?? editor.document }

  /// Routes a key press: a tool shortcut switches the tool when `ToolShortcutRouter` allows it, otherwise the
  /// active controller gets the key (type-to-create, delete, arrows, Escape). Returns true when consumed.
  @discardableResult
  public func handleKey(_ key: ToolKey, modifiers: ToolModifiers) -> Bool {
    if let tool = ToolShortcutRouter.tool(
      for: key, modifiers: modifiers, currentTool: editor.currentTool, isEditingText: isEditingText)
    {
      editor.currentTool = tool
      return true
    }
    return activeController.keyDown(key, modifiers: modifiers)
  }

  public override func keyUp(with event: NSEvent) {
    if event.keyCode == 49 {
      spaceDown = false
      panLast = nil
      window?.invalidateCursorRects(for: self)
      return
    }
    super.keyUp(with: event)
  }

  private static func toolKey(for event: NSEvent) -> ToolKey? {
    switch event.keyCode {
    case 51, 117: return .delete
    case 53: return .escape
    case 123: return .arrow(dx: -1, dy: 0)
    case 124: return .arrow(dx: 1, dy: 0)
    case 125: return .arrow(dx: 0, dy: 1)
    case 126: return .arrow(dx: 0, dy: -1)
    default:
      // Shortcuts use the bare key; plain typing keeps the shifted character for type-to-create.
      let command = !event.modifierFlags.intersection([.command, .control]).isEmpty
      guard let first = (command ? event.charactersIgnoringModifiers : event.characters)?.first else { return nil }
      return .character(first)
    }
  }

  // MARK: Hosting

  /// A scroll view hosting a new canvas for `editor`; the canvas re-lays out when the viewport resizes.
  public static func makeScrollView(editor: EditorModel) -> (scrollView: NSScrollView, canvas: CanvasView) {
    let canvas = CanvasView(editor: editor)
    let scrollView = CanvasScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.drawsBackground = false
    scrollView.documentView = canvas
    return (scrollView, canvas)
  }
}

/// Scroll view that tells its canvas to re-size and re-center whenever the viewport changes.
@MainActor
final class CanvasScrollView: NSScrollView {
  /// The canvas is fitted to the viewport once, on the first layout that has a real size.
  private var didInitialFit = false

  override func layout() {
    super.layout()
    if !didInitialFit, contentSize.width > 0, contentSize.height > 0, let canvas = documentView as? CanvasView {
      didInitialFit = true
      canvas.zoomToFit()
    }
    (documentView as? CanvasView)?.updateFrameSize()
  }
}
