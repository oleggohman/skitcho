import AppKit
import CoreGraphics
import Foundation
import SkitchoCore

/// The S tool: a click places the current stamp kind, dragging sets the tail angle (the tail points from the
/// badge toward the pointer). The stamp is a real element in the document during the gesture, so the canvas
/// previews it with the normal renderer; mouse-up commits one "Add Stamp" step and selects it.
///
/// "Attach Label" (`attachLabel(to:)`, or a double-click on a stamp without a label) creates a text element
/// linked through the stamp's `labelID`, placed beside the badge, and opens the in-place text editor.
/// Selection rule: a press on a handle of the selection manipulates it; anywhere else (also on the selected
/// stamp's badge) places a new stamp. Moving is the V tool's job.
@MainActor
public final class StampToolController: ToolController {
  /// Drags shorter than this many view points count as a click (no tail).
  public static let dragThreshold: Double = 3
  /// Gap between the badge (or its tail) and an attached label, in badge radii.
  static let labelGap = 0.4

  public static let supportedTools: [Tool] = [.stamp]

  private let editor: EditorModel
  private let zoom: () -> Double
  /// Creates and edits attached labels.
  private let labelEditor: TextToolController
  private let manipulator: SelectPanToolController

  private var origin: CGPoint?
  private var elementID: UUID?
  private var manipulating = false

  public var needsDisplay: (() -> Void)? {
    didSet { manipulator.needsDisplay = needsDisplay }
  }

  public init(editor: EditorModel, zoom: @escaping () -> Double, labelEditor: TextToolController) {
    self.editor = editor
    self.zoom = zoom
    self.labelEditor = labelEditor
    self.manipulator = SelectPanToolController(editor: editor, zoom: zoom)
  }

  public var cursor: NSCursor { ToolCursors.cursor(for: .stamp) }

  // MARK: Geometry

  /// Tail angle (radians, document space, y-down) for a drag from `start` to `end`.
  static func tailAngle(from start: CGPoint, to end: CGPoint) -> Double {
    atan2(end.y - start.y, end.x - start.x)
  }

  /// Top-left origin for a label attached to `stamp`: right of the badge, vertically centered. When the tail
  /// points to the right the label goes below the badge instead, so it does not cover the tail.
  static func labelOrigin(for stamp: Element, textHeight: Double) -> CGPoint {
    guard case .stamp(_, let center, let tailAngle, _) = stamp.kind else { return stamp.bounds.origin }
    let radius = StampKind.radius(strokeWidth: stamp.style.strokeWidth)
    let gap = radius * labelGap
    if let tailAngle, cos(tailAngle) > 0.5 {
      return CGPoint(x: center.x - radius, y: center.y + radius * (1 + StampKind.tailExtension) + gap)
    }
    return CGPoint(x: center.x + radius + gap, y: center.y - textHeight / 2)
  }

  // MARK: Attach label

  /// Creates an empty text element linked to the stamp `id` and starts editing it. The link and the text are
  /// one undo step ("Add Text"); leaving the text empty removes both again. Switches to the text tool, which
  /// owns the editor session. Returns false when `id` is not a stamp, already has a label, or text is unavailable.
  @discardableResult
  public func attachLabel(to id: UUID) -> Bool {
    guard !editor.isInteracting,
      let stamp = editor.document.elements.first(where: { $0.id == id }),
      case .stamp(let kind, let center, let tail, let existing) = stamp.kind, existing == nil,
      let textStyle = editor.nextStyle(for: .text)
    else { return false }
    let probe = TextContent(string: "", origin: .zero, wrapWidth: nil, styled: editor.nextTextStyled)
    let height = TextRenderer.size(for: probe, fontSize: textStyle.fontSize).height
    let origin = Self.labelOrigin(for: stamp, textHeight: height)
    editor.currentTool = .text
    guard labelEditor.beginCreating(at: origin), let session = labelEditor.session else { return false }
    // beginCreating opened the gesture; linking inside it keeps the label and the link one undo step.
    if let index = editor.document.elements.firstIndex(where: { $0.id == id }) {
      editor.document.elements[index].kind = .stamp(kind, center: center, tailAngle: tail, labelID: session.id)
    }
    return true
  }

  // MARK: Pointer

  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers) {
    mouseDown(at: point, modifiers: modifiers, clickCount: 1)
  }

  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers, clickCount: Int) {
    origin = nil
    elementID = nil
    manipulating = false
    if clickCount >= 2 {
      let tolerance = SelectPanToolController.hitSlop / max(zoom(), 0.0001)
      if let hit = editor.topMostHit(at: point, tolerance: tolerance), case .stamp(_, _, _, let label) = hit.kind {
        if let label, labelEditor.beginEditing(label) {
          editor.currentTool = .text
        } else if label == nil {
          attachLabel(to: hit.id)
        }
        return
      }
    }
    if manipulator.pressesHandle(at: point) {
      manipulating = true
      manipulator.mouseDown(at: point, modifiers: modifiers)
      return
    }
    guard let style = editor.nextStyle(for: .stamp) else { return }
    var stampStyle = style
    if editor.nextColor == nil { stampStyle.color = editor.nextStampKind.defaultColor }
    origin = point
    editor.beginInteractive()
    let element = Element(
      kind: .stamp(editor.nextStampKind, center: point, tailAngle: nil, labelID: nil), style: stampStyle)
    editor.document.elements.append(element)
    elementID = element.id
    needsDisplay?()
  }

  public func mouseDragged(to point: CGPoint, modifiers: ToolModifiers) {
    if manipulating {
      manipulator.mouseDragged(to: point, modifiers: modifiers)
      return
    }
    guard let origin, let id = elementID,
      let index = editor.document.elements.firstIndex(where: { $0.id == id }),
      case .stamp(let kind, let center, _, let label) = editor.document.elements[index].kind
    else { return }
    let moved = hypot(point.x - origin.x, point.y - origin.y) * zoom() >= Self.dragThreshold
    let angle = moved ? Self.tailAngle(from: origin, to: point) : nil
    editor.document.elements[index].kind = .stamp(kind, center: center, tailAngle: angle, labelID: label)
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
    guard let id = elementID, editor.isInteracting else { return }
    editor.commitInteractive(name: "Add Stamp")
    editor.select(id)
    needsDisplay?()
  }

  public func keyDown(_ key: ToolKey, modifiers: ToolModifiers) -> Bool {
    if key == .escape, editor.isInteracting, !manipulating, elementID != nil {
      editor.cancelInteractive()
      origin = nil
      elementID = nil
      needsDisplay?()
      return true
    }
    return manipulator.keyDown(key, modifiers: modifiers)
  }

  public func overlay(in context: CGContext, zoom: Double) {
    manipulator.overlay(in: context, zoom: zoom)
  }
}
