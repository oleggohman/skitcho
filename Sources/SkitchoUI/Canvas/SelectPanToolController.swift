import AppKit
import CoreGraphics
import Foundation
import SkitchoCore

/// The V tool: click selects the top-most hit, drag moves the selection (one undo step), a drag on empty
/// space draws a marquee that selects every element it fully contains. Panning is handled by the canvas
/// (Space-drag), not here.
@MainActor
public final class SelectPanToolController: ToolController {
  /// View-space hit slop in points; converted to document units with the zoom.
  public static let hitSlop: Double = 6
  /// Drags shorter than this (view points) count as a click.
  public static let dragThreshold: Double = 3

  private enum Gesture {
    case none
    /// Press on an element; `originals` are the selected elements at gesture start.
    case moving(start: CGPoint, originals: [UUID: Element])
    case marquee(start: CGPoint, base: Set<UUID>)
  }

  private let editor: EditorModel
  private let zoom: () -> Double
  private var gesture: Gesture = .none
  private var didDrag = false
  /// The marquee rectangle in document space while one is being dragged.
  public private(set) var marqueeRect: CGRect?

  public var needsDisplay: (() -> Void)?

  public init(editor: EditorModel, zoom: @escaping () -> Double) {
    self.editor = editor
    self.zoom = zoom
  }

  public var cursor: NSCursor { .arrow }

  private var tolerance: Double { Self.hitSlop / max(zoom(), 0.0001) }

  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers) {
    didDrag = false
    if let hit = editor.topMostHit(at: point, tolerance: tolerance) {
      if modifiers.contains(.shift) {
        editor.toggleSelection(hit.id)
        gesture = .none
        return
      }
      if !editor.selection.contains(hit.id) { editor.select(hit.id) }
      let originals = Dictionary(uniqueKeysWithValues: editor.selectedElements.map { ($0.id, $0) })
      gesture = .moving(start: point, originals: originals)
    } else {
      let base = modifiers.contains(.shift) ? editor.selection : []
      if base.isEmpty { editor.deselect() }
      gesture = .marquee(start: point, base: base)
    }
  }

  public func mouseDragged(to point: CGPoint, modifiers: ToolModifiers) {
    switch gesture {
    case .none:
      return
    case .moving(let start, let originals):
      let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
      if !didDrag {
        guard hypot(delta.x, delta.y) * zoom() >= Self.dragThreshold else { return }
        didDrag = true
        editor.beginInteractive()
      }
      editor.document.elements = editor.document.elements.map { element in
        originals[element.id].map { $0.translated(by: delta) } ?? element
      }
    case .marquee(let start, let base):
      let rect = CGRect(
        x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x),
        height: abs(point.y - start.y))
      marqueeRect = rect
      let inside = editor.document.elements.filter { rect.contains($0.bounds) }.map(\.id)
      editor.select(ids: base.union(inside))
      needsDisplay?()
    }
  }

  public func mouseUp(at point: CGPoint, modifiers: ToolModifiers) {
    if case .moving = gesture, didDrag { editor.commitInteractive(name: "Move") }
    gesture = .none
    didDrag = false
    if marqueeRect != nil {
      marqueeRect = nil
      needsDisplay?()
    }
  }

  public func keyDown(_ key: ToolKey, modifiers: ToolModifiers) -> Bool {
    switch key {
    case .delete:
      guard !editor.selection.isEmpty else { return false }
      editor.removeSelection()
      return true
    case .escape:
      if editor.isInteracting {
        editor.cancelInteractive()
        gesture = .none
        didDrag = false
        marqueeRect = nil
        needsDisplay?()
        return true
      }
      guard !editor.selection.isEmpty else { return false }
      editor.deselect()
      return true
    case .arrow(let dx, let dy):
      guard !editor.selection.isEmpty else { return false }
      editor.nudgeSelection(dx: dx, dy: dy, large: modifiers.contains(.shift))
      return true
    case .character:
      return false
    }
  }

  public func overlay(in context: CGContext, zoom: Double) {
    SelectionOverlay.draw(elements: editor.selectedElements, marquee: marqueeRect, in: context, zoom: zoom)
  }
}

/// Draws selection outlines, handles and the marquee. Handles are blue with a white outline (CloudZone).
enum SelectionOverlay {
  static func draw(elements: [Element], marquee: CGRect?, in context: CGContext, zoom: Double) {
    let blue = BrandColor.blue.nsColor().cgColor
    let white = BrandColor.white.nsColor().cgColor
    let px = 1 / max(zoom, 0.0001)
    context.saveGState()
    defer { context.restoreGState() }

    for element in elements {
      context.setStrokeColor(blue)
      context.setLineWidth(1.5 * px)
      context.stroke(element.bounds)
    }
    if elements.count == 1, let box = elements.first?.bounds {
      let side = 8 * px
      let points = [
        CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.midX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
        CGPoint(x: box.minX, y: box.midY), CGPoint(x: box.maxX, y: box.midY),
        CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.midX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
      ]
      for point in points {
        let handle = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
        context.setFillColor(blue)
        context.fill(handle)
        context.setStrokeColor(white)
        context.setLineWidth(1.5 * px)
        context.stroke(handle)
      }
    }
    if let marquee {
      context.setFillColor(BrandColor.blue.nsColor(alpha: 0.12).cgColor)
      context.fill(marquee)
      context.setStrokeColor(blue)
      context.setLineWidth(1 * px)
      context.setLineDash(phase: 0, lengths: [4 * px, 3 * px])
      context.stroke(marquee)
    }
  }
}
