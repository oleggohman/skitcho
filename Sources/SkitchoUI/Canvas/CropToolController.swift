import AppKit
import CoreGraphics
import Foundation
import SkitchoCore

/// The C tool: a crop rectangle over the whole canvas (resize it by its handles, move it, or drag a new one),
/// with a rule-of-thirds grid, a dim outside and W×H fields kept in sync through `width`/`height`. Nothing
/// touches the document until Apply (Return), which runs `EditorModel.crop` once ("Crop Image" undo step).
/// `expand(_:)` grows the canvas by `expandAmount` on one edge ("Expand Canvas" undo step); the crop rect
/// follows so it keeps framing the same content. Leaving the tool discards the rectangle.
@MainActor
public final class CropToolController: ToolController {
  public static let supportedTools: [Tool] = [.crop]
  /// Pixels added per expand-edge click.
  public static let expandAmount = 64
  /// Smallest crop side in pixels.
  static let minimumSide: Double = 1

  private enum Drag {
    case move(start: CGPoint, original: CGRect)
    case resize(Handle, original: CGRect)
    case create(origin: CGPoint)
  }

  private let editor: EditorModel
  private let zoom: () -> Double
  private var drag: Drag?
  /// The user's rectangle, or nil while the crop covers the whole canvas.
  private var customRect: CGRect?

  /// Message of the last failed Apply or expand, cleared by the next gesture.
  public private(set) var errorMessage: String?

  public var needsDisplay: (() -> Void)?
  /// Called when the rectangle or error changed (the canvas refreshes the options bar).
  public var stateDidChange: (() -> Void)?

  public init(editor: EditorModel, zoom: @escaping () -> Double) {
    self.editor = editor
    self.zoom = zoom
  }

  public var cursor: NSCursor { ToolCursors.cursor(for: .crop) }

  // MARK: Rectangle

  /// The whole canvas in document space.
  public var canvasRect: CGRect { CGRect(origin: .zero, size: editor.document.canvasSize) }

  /// The crop rectangle in document space, always inside the canvas (the full canvas until the user changes it).
  public var rect: CGRect {
    guard let customRect else { return canvasRect }
    let clipped = customRect.intersection(canvasRect)
    guard !clipped.isNull, clipped.width >= Self.minimumSide, clipped.height >= Self.minimumSide else {
      return canvasRect
    }
    return clipped
  }

  public var width: Int { Int(rect.width.rounded()) }
  public var height: Int { Int(rect.height.rounded()) }

  /// True when Apply would change something (the rect is smaller than the canvas).
  public var canApply: Bool { drag == nil && rect != canvasRect }

  /// True when there is a user rectangle waiting for Apply or Cancel.
  public var hasPendingRect: Bool { customRect != nil }

  /// Sets the width in pixels from the field; clamped to 1...(canvas edge - left side).
  public func setWidth(_ value: Int) {
    var next = rect
    let limit = max(Int(canvasRect.maxX - next.minX), 1)
    next.size.width = Double(min(max(value, 1), limit))
    setRect(next)
  }

  /// Sets the height in pixels from the field; clamped to 1...(canvas edge - top side).
  public func setHeight(_ value: Int) {
    var next = rect
    let limit = max(Int(canvasRect.maxY - next.minY), 1)
    next.size.height = Double(min(max(value, 1), limit))
    setRect(next)
  }

  private func setRect(_ next: CGRect) {
    errorMessage = nil
    customRect = next == canvasRect ? nil : next
    stateDidChange?()
    needsDisplay?()
  }

  // MARK: Apply / cancel / expand

  /// Crops the canvas to `rect`. Returns false (document untouched, rect kept) when there is nothing to
  /// crop or the operation failed; the failure text is in `errorMessage`.
  @discardableResult
  public func apply() -> Bool {
    guard canApply else { return false }
    do {
      try editor.crop(to: rect)
    } catch {
      errorMessage = "Could not crop: \(error)"
      stateDidChange?()
      return false
    }
    reset()
    return true
  }

  /// Back to the full canvas.
  public func cancel() { reset() }

  private func reset() {
    drag = nil
    customRect = nil
    errorMessage = nil
    stateDidChange?()
    needsDisplay?()
  }

  /// Grows the canvas by `expandAmount` pixels on `edge`. A custom crop rect moves with the content.
  public func expand(_ edge: CanvasEdge) {
    errorMessage = nil
    let before = rect
    let wasCustom = canApply
    do {
      try editor.expandCanvas(edge: edge, amount: Self.expandAmount)
    } catch {
      errorMessage = "Could not expand: \(error)"
      stateDidChange?()
      return
    }
    if wasCustom {
      let amount = Double(Self.expandAmount)
      switch edge {
      case .left: customRect = before.offsetBy(dx: amount, dy: 0)
      case .top: customRect = before.offsetBy(dx: 0, dy: amount)
      case .right, .bottom: customRect = before
      }
    } else {
      customRect = nil
    }
    stateDidChange?()
    needsDisplay?()
  }

  // MARK: Pointer

  /// Handle centers of `rect`, corners first so they win when a small rect makes handles overlap.
  private func handlePoints(of rect: CGRect) -> [(Handle, CGPoint)] {
    [
      (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
      (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
      (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
      (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
      (.top, CGPoint(x: rect.midX, y: rect.minY)),
      (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
      (.left, CGPoint(x: rect.minX, y: rect.midY)),
      (.right, CGPoint(x: rect.maxX, y: rect.midY)),
    ]
  }

  /// The handle under `point`, if any.
  func handle(at point: CGPoint) -> Handle? {
    let radius = HandleLayout.hitRadius / max(zoom(), 0.0001)
    return handlePoints(of: rect).first { hypot($0.1.x - point.x, $0.1.y - point.y) <= radius }?.0
  }

  private func clamped(_ point: CGPoint) -> CGPoint {
    let canvas = canvasRect
    return CGPoint(
      x: min(max(point.x.rounded(), canvas.minX), canvas.maxX),
      y: min(max(point.y.rounded(), canvas.minY), canvas.maxY))
  }

  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers) {
    errorMessage = nil
    let current = rect
    if let handle = handle(at: point) {
      drag = .resize(handle, original: current)
    } else if current.contains(point) {
      drag = .move(start: point, original: current)
    } else {
      drag = .create(origin: clamped(point))
    }
    stateDidChange?()
  }

  public func mouseDragged(to point: CGPoint, modifiers: ToolModifiers) {
    guard let drag else { return }
    let canvas = canvasRect
    var next: CGRect
    switch drag {
    case .move(let start, let original):
      let dx = min(max((point.x - start.x).rounded(), canvas.minX - original.minX), canvas.maxX - original.maxX)
      let dy = min(max((point.y - start.y).rounded(), canvas.minY - original.minY), canvas.maxY - original.maxY)
      next = original.offsetBy(dx: dx, dy: dy)
    case .resize(let handle, let original):
      next = Self.resized(original, handle: handle, to: clamped(point))
    case .create(let origin):
      let end = clamped(point)
      next = CGRect(
        x: min(origin.x, end.x), y: min(origin.y, end.y), width: abs(end.x - origin.x),
        height: abs(end.y - origin.y))
      guard next.width >= Self.minimumSide, next.height >= Self.minimumSide else { return }
    }
    customRect = next == canvas ? nil : next
    stateDidChange?()
    needsDisplay?()
  }

  public func mouseUp(at point: CGPoint, modifiers: ToolModifiers) {
    guard drag != nil else { return }
    mouseDragged(to: point, modifiers: modifiers)
    drag = nil
    stateDidChange?()
    needsDisplay?()
  }

  /// `original` with the edges that `handle` moves set to `point`; the opposite edges stay fixed and a side
  /// never collapses below one pixel.
  static func resized(_ original: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
    var minX = original.minX
    var maxX = original.maxX
    var minY = original.minY
    var maxY = original.maxY
    switch handle {
    case .topLeft, .left, .bottomLeft: minX = min(point.x, maxX - minimumSide)
    case .topRight, .right, .bottomRight: maxX = max(point.x, minX + minimumSide)
    default: break
    }
    switch handle {
    case .topLeft, .top, .topRight: minY = min(point.y, maxY - minimumSide)
    case .bottomLeft, .bottom, .bottomRight: maxY = max(point.y, minY + minimumSide)
    default: break
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  public func keyDown(_ key: ToolKey, modifiers: ToolModifiers) -> Bool {
    switch key {
    case .escape:
      guard hasPendingRect else { return false }
      cancel()
      return true
    case .character(let character) where character == "\r" || character == "\n" || character == "\u{3}":
      guard canApply else { return false }
      apply()
      return true
    default:
      return false
    }
  }

  // MARK: Overlay

  public func overlay(in context: CGContext, zoom: Double) {
    let px = 1 / max(zoom, 0.0001)
    let crop = rect
    context.saveGState()
    defer { context.restoreGState() }

    // Dim everything on the canvas outside the crop.
    context.setFillColor(BrandColor.modalDim.cgColor)
    context.addRect(canvasRect)
    context.addRect(crop)
    context.fillPath(using: .evenOdd)

    // Rule-of-thirds grid.
    context.setLineWidth(1 * px)
    context.setStrokeColor(BrandColor.white.nsColor(alpha: 0.6).cgColor)
    for i in 1...2 {
      let fraction = Double(i) / 3
      let x = crop.minX + crop.width * fraction
      let y = crop.minY + crop.height * fraction
      context.move(to: CGPoint(x: x, y: crop.minY))
      context.addLine(to: CGPoint(x: x, y: crop.maxY))
      context.move(to: CGPoint(x: crop.minX, y: y))
      context.addLine(to: CGPoint(x: crop.maxX, y: y))
    }
    context.strokePath()

    // Border.
    context.setStrokeColor(BrandColor.white.nsColor().cgColor)
    context.stroke(crop)
    context.setStrokeColor(BrandColor.blue.nsColor().cgColor)
    context.setLineDash(phase: 0, lengths: [4 * px, 3 * px])
    context.stroke(crop)
    context.setLineDash(phase: 0, lengths: [])

    // Handles: blue squares with a white outline.
    let side = HandleLayout.handleSide * px
    for (_, center) in handlePoints(of: crop) {
      let square = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
      context.setFillColor(BrandColor.blue.nsColor().cgColor)
      context.fill(square)
      context.setStrokeColor(BrandColor.white.nsColor().cgColor)
      context.stroke(square)
    }
  }
}
