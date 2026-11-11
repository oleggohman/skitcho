import AppKit
import CoreGraphics
import Foundation
import SkitchoCore

/// The P tool: drag a region (shown with dashed "ants"), pick a block size, then Apply (Return) or Cancel (Esc).
/// Nothing touches the document until Apply, which runs `EditorModel.pixelate` once (one "Pixelate" undo step).
/// A new drag replaces the pending region; switching tools discards it.
@MainActor
public final class PixelateToolController: ToolController {
  public static let supportedTools: [Tool] = [.pixelate]
  public static let blockSizeRange = 2...64
  public static let defaultBlockSize = 12
  /// Drags smaller than this many view points (per side) are ignored.
  public static let minimumSide: Double = 3

  private let editor: EditorModel
  private let zoom: () -> Double
  private var origin: CGPoint?

  /// The pending region in document space (unclipped), or nil.
  public private(set) var region: CGRect?
  public private(set) var isDragging = false
  public var blockSize = PixelateToolController.defaultBlockSize {
    didSet {
      let clamped = min(max(blockSize, Self.blockSizeRange.lowerBound), Self.blockSizeRange.upperBound)
      if clamped != blockSize { blockSize = clamped }
      if blockSize != oldValue { stateDidChange?() }
    }
  }
  /// Message of the last failed Apply, cleared by the next gesture.
  public private(set) var errorMessage: String?

  public var needsDisplay: (() -> Void)?
  /// Called when the region, block size or error changed (the canvas updates the options bar).
  public var stateDidChange: (() -> Void)?

  public init(editor: EditorModel, zoom: @escaping () -> Double) {
    self.editor = editor
    self.zoom = zoom
  }

  public var cursor: NSCursor { ToolCursors.cursor(for: .pixelate) }

  /// True when a finished region is waiting for Apply or Cancel.
  public var hasPendingRegion: Bool { !isDragging && clippedRegion != nil }

  /// The pending region clipped to the base image and rounded outward to whole pixels, or nil when empty.
  public var clippedRegion: CGRect? {
    guard let region else { return nil }
    let document = editor.document
    let image = CGRect(
      x: document.imageOrigin.x, y: document.imageOrigin.y,
      width: Double(document.baseImage.width), height: Double(document.baseImage.height))
    let clipped = region.standardized.intersection(image)
    guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
    return clipped.integral.intersection(image)
  }

  // MARK: Apply / cancel

  /// Pixelates the clipped region. Returns false (document untouched, region kept) when there is nothing to
  /// apply or the operation failed; the failure text is in `errorMessage`.
  @discardableResult
  public func apply() -> Bool {
    guard !isDragging, let rect = clippedRegion else { return false }
    do {
      try editor.pixelate(rect: rect, blockSize: blockSize)
    } catch {
      errorMessage = "Could not pixelate: \(error)"
      stateDidChange?()
      return false
    }
    clear()
    return true
  }

  /// Discards the pending region.
  public func cancel() { clear() }

  private func clear() {
    origin = nil
    region = nil
    isDragging = false
    errorMessage = nil
    stateDidChange?()
    needsDisplay?()
  }

  // MARK: Pointer

  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers) {
    errorMessage = nil
    origin = point
    region = CGRect(origin: point, size: .zero)
    isDragging = true
    stateDidChange?()
    needsDisplay?()
  }

  public func mouseDragged(to point: CGPoint, modifiers: ToolModifiers) {
    guard isDragging, let origin else { return }
    region = CGRect(
      x: min(origin.x, point.x), y: min(origin.y, point.y),
      width: abs(point.x - origin.x), height: abs(point.y - origin.y))
    needsDisplay?()
  }

  public func mouseUp(at point: CGPoint, modifiers: ToolModifiers) {
    guard isDragging else { return }
    mouseDragged(to: point, modifiers: modifiers)
    isDragging = false
    origin = nil
    let minimum = Self.minimumSide / max(zoom(), 0.0001)
    if let region, region.width < minimum || region.height < minimum { self.region = nil }
    stateDidChange?()
    needsDisplay?()
  }

  public func keyDown(_ key: ToolKey, modifiers: ToolModifiers) -> Bool {
    switch key {
    case .escape:
      guard region != nil else { return false }
      cancel()
      return true
    case .character(let character) where character == "\r" || character == "\n" || character == "\u{3}":
      guard hasPendingRegion else { return false }
      apply()
      return true
    default:
      return false
    }
  }

  // MARK: Overlay

  public func overlay(in context: CGContext, zoom: Double) {
    guard let region, region.width > 0 || region.height > 0 else { return }
    let px = 1 / max(zoom, 0.0001)
    context.saveGState()
    defer { context.restoreGState() }
    context.setFillColor(BrandColor.blue.nsColor(alpha: 0.12).cgColor)
    context.fill(region)
    context.setLineWidth(1 * px)
    context.setStrokeColor(BrandColor.white.nsColor().cgColor)
    context.stroke(region)
    context.setStrokeColor(BrandColor.blue.nsColor().cgColor)
    context.setLineDash(phase: 0, lengths: [4 * px, 3 * px])
    context.stroke(region)
  }
}
