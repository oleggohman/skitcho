import AppKit
import CoreGraphics
import SkitchoCore

/// Modifier keys passed to tool controllers (decoupled from NSEvent so tests can call controllers directly).
public struct ToolModifiers: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let shift = ToolModifiers(rawValue: 1 << 0)
  public static let option = ToolModifiers(rawValue: 1 << 1)
  public static let command = ToolModifiers(rawValue: 1 << 2)
  public static let control = ToolModifiers(rawValue: 1 << 3)

  public init(_ flags: NSEvent.ModifierFlags) {
    var result: ToolModifiers = []
    if flags.contains(.shift) { result.insert(.shift) }
    if flags.contains(.option) { result.insert(.option) }
    if flags.contains(.command) { result.insert(.command) }
    if flags.contains(.control) { result.insert(.control) }
    self = result
  }
}

/// A key press forwarded to the active tool controller.
public enum ToolKey: Equatable, Sendable {
  case delete
  case escape
  case arrow(dx: Int, dy: Int)
  case character(Character)
}

/// Handles pointer and key input for one tool. All points are in document space (top-left origin, y-down,
/// image pixels); the canvas converts view points before calling. Hit tolerances are derived from the zoom.
@MainActor
public protocol ToolController: AnyObject {
  /// Cursor shown over the canvas while this tool is active.
  var cursor: NSCursor { get }
  /// Set by the canvas; call it when `overlay` output changed.
  var needsDisplay: (() -> Void)? { get set }

  func mouseDown(at point: CGPoint, modifiers: ToolModifiers)
  /// Like `mouseDown(at:modifiers:)` with the event's click count (2 = double-click). Defaults to a plain press.
  func mouseDown(at point: CGPoint, modifiers: ToolModifiers, clickCount: Int)
  func mouseDragged(to point: CGPoint, modifiers: ToolModifiers)
  func mouseUp(at point: CGPoint, modifiers: ToolModifiers)
  /// Returns true when the key was consumed.
  func keyDown(_ key: ToolKey, modifiers: ToolModifiers) -> Bool
  /// Draws transient UI (selection handles, marquee, previews). `context` is in document space (y-down,
  /// 1 unit = 1 image pixel); `zoom` converts view points to document units (`points / zoom`).
  func overlay(in context: CGContext, zoom: Double)
}

extension ToolController {
  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers, clickCount: Int) {
    mouseDown(at: point, modifiers: modifiers)
  }
}
