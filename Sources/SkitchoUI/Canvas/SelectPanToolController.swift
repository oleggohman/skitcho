import AppKit
import CoreGraphics
import Foundation
import SkitchoCore

/// The V tool: click selects the top-most hit, drag moves the selection (one undo step), a drag on empty
/// space draws a marquee that selects every element it fully contains. A press on a handle of the single
/// selected element resizes, rotates or moves an endpoint (one undo step per drag). Panning is handled by the canvas
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
    /// Press on a handle of the single selected element; `original` is its state at gesture start.
    case handle(Handle, original: Element)
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

  /// The handle of the single selected element under `point`, if any.
  func handle(at point: CGPoint) -> Handle? {
    guard editor.selection.count == 1, let element = editor.selectedElements.first else { return nil }
    return HandleLayout.hit(element, at: point, zoom: zoom())
  }

  /// True when a press at `point` lands on a handle of the single selected element. Drawing tools use this for
  /// the selection rule: only handles manipulate the selection, a press on its body draws (V moves elements).
  func pressesHandle(at point: CGPoint) -> Bool {
    handle(at: point) != nil
  }

  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers) {
    didDrag = false
    if !modifiers.contains(.shift), let handle = handle(at: point), let element = editor.selectedElements.first {
      gesture = .handle(handle, original: element)
      return
    }
    if let hit = editor.topMostHit(at: point, tolerance: tolerance) {
      if modifiers.contains(.shift) {
        editor.toggleSelection(hit.id)
        gesture = .none
        return
      }
      if !editor.selection.contains(hit.id) { editor.select(hit.id) }
      let originals = Dictionary(uniqueKeysWithValues: editor.movingElements.map { ($0.id, $0) })
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
    case .handle(let handle, let original):
      if !didDrag {
        didDrag = true
        editor.beginInteractive()
      }
      let updated = HandleLayout.apply(handle, to: original, pointer: point, modifiers: modifiers)
      if let index = editor.document.elements.firstIndex(where: { $0.id == original.id }) {
        editor.document.elements[index] = updated
      }
      needsDisplay?()
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
    if didDrag {
      switch gesture {
      case .moving: editor.commitInteractive(name: "Move")
      case .handle(let handle, _): editor.commitInteractive(name: HandleLayout.undoName(for: handle))
      default: break
      }
      needsDisplay?()
    }
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
    case .character(let character):
      guard modifiers.contains(.command), !editor.selection.isEmpty else { return false }
      switch character {
      case "]": editor.bringForward()
      case "[": editor.sendBackward()
      default: return false
      }
      return true
    }
  }

  public func overlay(in context: CGContext, zoom: Double) {
    SelectionOverlay.draw(elements: editor.selectedElements, marquee: marqueeRect, in: context, zoom: zoom)
  }
}
