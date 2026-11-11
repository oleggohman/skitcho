import AppKit
import CoreGraphics
import Observation
import SkitchoCore

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

  private var controllers: [Tool: any ToolController] = [:]
  private let selectController: SelectPanToolController
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

  // MARK: Controllers

  /// Registers the controller used while `tool` is current. Tools without a controller use the V tool's.
  public func register(_ controller: some ToolController, for tool: Tool) {
    controller.needsDisplay = { [weak self] in self?.needsDisplay = true }
    controllers[tool] = controller
    window?.invalidateCursorRects(for: self)
  }

  public var activeController: any ToolController { controllers[editor.currentTool] ?? selectController }

  // MARK: Geometry

  public var canvasGeometry: CanvasGeometry { CanvasGeometry(zoom: zoom, contentOrigin: contentOrigin()) }

  public func documentPoint(fromView point: CGPoint) -> CGPoint { canvasGeometry.documentPoint(fromView: point) }

  public func viewPoint(fromDocument point: CGPoint) -> CGPoint { canvasGeometry.viewPoint(fromDocument: point) }

  /// Visible size of the enclosing scroll view, or nil when not hosted in one.
  private var viewportSize: CGSize? { enclosingScrollView?.contentSize }

  private func contentOrigin() -> CGPoint {
    let canvas = editor.document.canvasSize
    return CGPoint(
      x: max(Self.margin, (frame.width - canvas.width * zoom) / 2),
      y: max(Self.margin, (frame.height - canvas.height * zoom) / 2))
  }

  /// Resizes the view to the zoomed canvas plus margins (or the viewport, when larger).
  public func updateFrameSize() {
    let canvas = editor.document.canvasSize
    let viewport = viewportSize ?? .zero
    let size = CGSize(
      width: max(canvas.width * zoom + 2 * Self.margin, viewport.width),
      height: max(canvas.height * zoom + 2 * Self.margin, viewport.height))
    if frame.size != size { setFrameSize(size) }
    needsDisplay = true
  }

  // MARK: Zoom

  public func setZoom(_ value: Double) {
    zoom = min(max(value, Self.minZoom), Self.maxZoom)
    zoomBox.value = zoom
    updateFrameSize()
    window?.invalidateCursorRects(for: self)
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
    let fitY = (size.height - 2 * Self.margin) / canvas.height
    setZoom(min(fitX, fitY, 1))
  }

  public override func magnify(with event: NSEvent) {
    setZoom(zoom * (1 + event.magnification))
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

  private func editorDidChange() {
    let size = editor.document.canvasSize
    if size != lastCanvasSize {
      lastCanvasSize = size
      updateFrameSize()
    }
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
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
    window?.makeFirstResponder(self)
    if spaceDown {
      panLast = event.locationInWindow
      window?.invalidateCursorRects(for: self)
      return
    }
    activeController.mouseDown(at: docPoint(event), modifiers: ToolModifiers(event.modifierFlags))
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
    let modifiers = ToolModifiers(event.modifierFlags)
    if event.keyCode == 49 && !event.isARepeat {  // Space: pan mode while held
      spaceDown = true
      window?.invalidateCursorRects(for: self)
      return
    }
    if let key = Self.toolKey(for: event), activeController.keyDown(key, modifiers: modifiers) { return }
    super.keyDown(with: event)
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
      guard let first = event.charactersIgnoringModifiers?.first else { return nil }
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
  override func layout() {
    super.layout()
    (documentView as? CanvasView)?.updateFrameSize()
  }
}
