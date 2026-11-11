import AppKit
import CoreGraphics
import Foundation
import SkitchoCore

/// Draws arrows, lines, rectangles, rounded rectangles and ellipses by dragging.
///
/// The element is created on the first drag past the threshold and updated live in the document (inside an
/// interactive gesture), so the canvas renders the preview with the normal renderer. Mouse-up commits one
/// undo step and selects the new element; a drag that stays below the minimum size creates nothing.
/// Selection rule: a press on an already selected element manipulates the selection (move); anywhere else
/// starts a new element, even on top of an unselected element.
@MainActor
public final class ShapeToolController: ToolController {
  /// Drags shorter than this many view points count as a click.
  public static let dragThreshold: Double = 3
  /// Smallest box side (view points) a rectangle or ellipse needs to be created.
  public static let minimumSide: Double = 4

  public static let supportedTools: [Tool] = [.arrow, .line, .rect, .roundedRect, .ellipse]

  private let editor: EditorModel
  private let tool: Tool
  private let zoom: () -> Double
  /// Moves the selection when the press lands on a selected element.
  private let manipulator: SelectPanToolController

  private var origin: CGPoint?
  private var elementID: UUID?
  private var manipulating = false

  public var needsDisplay: (() -> Void)? {
    didSet { manipulator.needsDisplay = needsDisplay }
  }

  /// `tool` must be one of `supportedTools`.
  public init(editor: EditorModel, tool: Tool, zoom: @escaping () -> Double) {
    precondition(Self.supportedTools.contains(tool), "ShapeToolController does not support \(tool)")
    self.editor = editor
    self.tool = tool
    self.zoom = zoom
    self.manipulator = SelectPanToolController(editor: editor, zoom: zoom)
  }

  public var cursor: NSCursor { ToolCursors.cursor(for: tool) }

  private var tolerance: Double { SelectPanToolController.hitSlop / max(zoom(), 0.0001) }

  // MARK: Geometry

  /// The element kind for a drag from `start` to `end`, with Shift (square/circle/15 degrees) and Option
  /// (start is the center) applied. Pure, so tests can call it directly.
  static func kind(
    for tool: Tool, from start: CGPoint, to end: CGPoint, modifiers: ToolModifiers, doubleHeaded: Bool = false
  ) -> ElementKind {
    switch tool {
    case .arrow, .line:
      var delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
      if modifiers.contains(.shift) {
        let snapped = GeometryMath.snapped(end, from: start)
        delta = CGPoint(x: snapped.x - start.x, y: snapped.y - start.y)
      }
      let from = modifiers.contains(.option) ? CGPoint(x: start.x - delta.x, y: start.y - delta.y) : start
      let to = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
      return tool == .arrow ? .arrow(start: from, end: to, doubleHeaded: doubleHeaded) : .line(start: from, end: to)
    default:
      var dx = end.x - start.x
      var dy = end.y - start.y
      if modifiers.contains(.shift) {
        let side = max(abs(dx), abs(dy))
        dx = dx < 0 ? -side : side
        dy = dy < 0 ? -side : side
      }
      let rect: CGRect
      if modifiers.contains(.option) {
        rect = CGRect(x: start.x - abs(dx), y: start.y - abs(dy), width: 2 * abs(dx), height: 2 * abs(dy))
      } else {
        rect = CGRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy))
      }
      return tool == .ellipse ? .ellipse(rect) : .rect(rect, rounded: tool == .roundedRect)
    }
  }

  /// Whether `kind` is big enough to keep, given the current zoom and the element's frozen stroke width.
  private func isLargeEnough(_ kind: ElementKind, strokeWidth: Double) -> Bool {
    let minimum = Self.minimumSide / max(zoom(), 0.0001)
    switch kind {
    case .arrow(let start, let end, _):
      return hypot(end.x - start.x, end.y - start.y) >= ArrowPath.minimumLength(width: strokeWidth)
    case .line(let start, let end):
      return hypot(end.x - start.x, end.y - start.y) >= minimum
    case .rect(let rect, _), .ellipse(let rect):
      return rect.width >= minimum && rect.height >= minimum
    default:
      return false
    }
  }

  // MARK: Pointer

  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers) {
    origin = nil
    elementID = nil
    manipulating = false
    let selectedHit = editor.selectedElements.contains { $0.hitTest(point: point, tolerance: tolerance) }
    if selectedHit {
      manipulating = true
      manipulator.mouseDown(at: point, modifiers: modifiers)
      return
    }
    origin = point
  }

  public func mouseDragged(to point: CGPoint, modifiers: ToolModifiers) {
    if manipulating {
      manipulator.mouseDragged(to: point, modifiers: modifiers)
      return
    }
    guard let origin else { return }
    let kind = Self.kind(
      for: tool, from: origin, to: point, modifiers: modifiers, doubleHeaded: editor.nextDoubleHeaded)
    guard let id = elementID else {
      guard hypot(point.x - origin.x, point.y - origin.y) * zoom() >= Self.dragThreshold else { return }
      guard let style = editor.nextStyle(for: tool) else { return }
      editor.beginInteractive()
      let element = Element(kind: kind, style: style)
      editor.document.elements.append(element)
      elementID = element.id
      needsDisplay?()
      return
    }
    guard let index = editor.document.elements.firstIndex(where: { $0.id == id }) else { return }
    editor.document.elements[index].kind = kind
    needsDisplay?()
  }

  public func mouseUp(at point: CGPoint, modifiers: ToolModifiers) {
    defer {
      origin = nil
      elementID = nil
      manipulating = false
    }
    if manipulating {
      manipulator.mouseUp(at: point, modifiers: modifiers)
      return
    }
    guard let id = elementID, let element = editor.document.elements.first(where: { $0.id == id }) else {
      return
    }
    if isLargeEnough(element.kind, strokeWidth: element.style.strokeWidth) {
      editor.commitInteractive(name: "Add \(Self.displayName(for: tool))")
      editor.select(id)
    } else {
      editor.cancelInteractive()
    }
    needsDisplay?()
  }

  public func keyDown(_ key: ToolKey, modifiers: ToolModifiers) -> Bool {
    if key == .escape, editor.isInteracting, !manipulating {
      editor.cancelInteractive()
      origin = nil
      elementID = nil
      needsDisplay?()
      return true
    }
    return manipulator.keyDown(key, modifiers: modifiers)
  }

  public func overlay(in context: CGContext, zoom: Double) {
    // The preview is a real element in the document; only the selection chrome is drawn here.
    manipulator.overlay(in: context, zoom: zoom)
  }

  private static func displayName(for tool: Tool) -> String {
    switch tool {
    case .arrow: "Arrow"
    case .line: "Line"
    case .rect: "Rectangle"
    case .roundedRect: "Rounded Rectangle"
    case .ellipse: "Ellipse"
    default: "Shape"
    }
  }
}
