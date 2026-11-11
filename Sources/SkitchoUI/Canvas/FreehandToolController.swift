import AppKit
import CoreGraphics
import Foundation
import SkitchoCore

/// Draws freehand marks with the marker or the highlighter.
///
/// While dragging, raw points go through a live low-pass filter and the element is updated inside an
/// interactive gesture as a straight-segment polyline, so the canvas shows the preview with the normal
/// renderer. Mouse-up fits cubic beziers to the filtered stream, commits one undo step and selects the new
/// element. A click without movement creates nothing. Selection rule matches the shape tools: a press on a handle or an
/// already selected element manipulates the selection, anywhere else starts a stroke.
@MainActor
public final class FreehandToolController: ToolController {
  /// Drags shorter than this many view points count as a click.
  public static let dragThreshold: Double = 3
  /// Maximum bezier fitting error in view points (converted to document units by the zoom).
  public static let fitError: Double = 1.5

  public static let supportedTools: [Tool] = [.marker, .highlighter]

  private let editor: EditorModel
  private let tool: Tool
  private let zoom: () -> Double
  private let manipulator: SelectPanToolController

  private var filter = LowPassFilter()
  private var origin: CGPoint?
  private var points: [CGPoint] = []
  private var elementID: UUID?
  private var manipulating = false

  public var needsDisplay: (() -> Void)? {
    didSet { manipulator.needsDisplay = needsDisplay }
  }

  /// `tool` must be one of `supportedTools`.
  public init(editor: EditorModel, tool: Tool, zoom: @escaping () -> Double) {
    precondition(Self.supportedTools.contains(tool), "FreehandToolController does not support \(tool)")
    self.editor = editor
    self.tool = tool
    self.zoom = zoom
    self.manipulator = SelectPanToolController(editor: editor, zoom: zoom)
  }

  public var cursor: NSCursor { ToolCursors.cursor(for: tool) }

  private var highlighter: Bool { tool == .highlighter }

  /// Straight cubic segments through `points`, used for the live preview.
  static func polyline(_ points: [CGPoint]) -> [BezierSegment] {
    zip(points, points.dropFirst()).map { BezierSegment($0, $0, $1, $1) }
  }

  // MARK: Pointer

  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers) {
    origin = nil
    points = []
    elementID = nil
    manipulating = false
    if manipulator.pressesSelection(at: point) {
      manipulating = true
      manipulator.mouseDown(at: point, modifiers: modifiers)
      return
    }
    origin = point
    filter = LowPassFilter()
    points = [filter.add(point)].compactMap { $0 }
  }

  public func mouseDragged(to point: CGPoint, modifiers: ToolModifiers) {
    if manipulating {
      manipulator.mouseDragged(to: point, modifiers: modifiers)
      return
    }
    guard let origin else { return }
    if let filtered = filter.add(point) { points.append(filtered) }
    guard let id = elementID else {
      guard hypot(point.x - origin.x, point.y - origin.y) * zoom() >= Self.dragThreshold else { return }
      guard let style = editor.nextStyle(for: tool) else { return }
      editor.beginInteractive()
      let element = Element(
        kind: .freehand(segments: Self.polyline(points), highlighter: highlighter), style: style)
      editor.document.elements.append(element)
      elementID = element.id
      needsDisplay?()
      return
    }
    update(id, segments: Self.polyline(points))
  }

  public func mouseUp(at point: CGPoint, modifiers: ToolModifiers) {
    defer {
      origin = nil
      points = []
      elementID = nil
      manipulating = false
    }
    if manipulating {
      manipulator.mouseUp(at: point, modifiers: modifiers)
      return
    }
    guard let id = elementID else { return }
    if let filtered = filter.add(point) { points.append(filtered) }
    if points.count > 1, points.last != point { points[points.count - 1] = point }
    let segments = BezierFitter.fit(points, maxError: Self.fitError / max(zoom(), 0.0001))
    if segments.isEmpty {
      editor.cancelInteractive()
    } else {
      update(id, segments: segments)
      editor.commitInteractive(name: highlighter ? "Add Highlight" : "Add Drawing")
      editor.select(id)
    }
    needsDisplay?()
  }

  public func keyDown(_ key: ToolKey, modifiers: ToolModifiers) -> Bool {
    if key == .escape, editor.isInteracting, !manipulating {
      editor.cancelInteractive()
      origin = nil
      points = []
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

  private func update(_ id: UUID, segments: [BezierSegment]) {
    guard let index = editor.document.elements.firstIndex(where: { $0.id == id }) else { return }
    editor.document.elements[index].kind = .freehand(segments: segments, highlighter: highlighter)
    needsDisplay?()
  }
}
