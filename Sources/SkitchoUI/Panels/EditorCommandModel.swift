import AppKit
import SkitchoCore
import SwiftUI

/// The menu commands that act on the key window's editor. The app's `Commands` read `isEnabled` and call
/// `perform`, so enablement and behaviour live here (testable) while the menu layout stays in the app target.
@MainActor @Observable
public final class EditorCommandModel {
  public enum Command: CaseIterable, Sendable {
    case cut, copy, paste, delete, selectAll
    case bringForward, sendBackward
    case cropTool, resize, rotateLeft, rotateRight, flipHorizontal, flipVertical, expandCanvas
    case copyImage, exportAs
    case zoomIn, zoomOut, actualSize, zoomToFit
  }

  /// Pixels added per Expand Canvas menu action.
  public static let expandAmount = 64

  private let editor: EditorModel
  private let handle: CanvasHandle
  private let bridge: PasteboardBridge
  /// Opens the resize panel (set by the window view).
  public var beginResize: () -> Void = {}
  /// Failure of the last image operation, shown by the window as an alert.
  public var errorMessage: String?
  /// Presents Export As… (replaced in tests).
  public var presentExport: () -> Void = {}

  public init(editor: EditorModel, handle: CanvasHandle, bridge: PasteboardBridge = PasteboardBridge()) {
    self.editor = editor
    self.handle = handle
    self.bridge = bridge
  }

  /// The editor's current tool (for the Tools menu check mark).
  public var currentTool: Tool { editor.currentTool }

  public func selectTool(_ tool: Tool) { editor.currentTool = tool }

  private var isEditingText: Bool { handle.canvas?.isEditingText ?? false }

  // MARK: Enablement

  /// Whether `command` is available for the current editor state. While text is edited, clipboard and
  /// select-all go to the text editor and the element/image commands are off.
  public func isEnabled(_ command: Command) -> Bool {
    let editing = isEditingText
    switch command {
    case .cut, .copy: return editing || !editor.selection.isEmpty
    case .delete: return !editing && !editor.selection.isEmpty
    case .selectAll: return editing || !editor.document.elements.isEmpty
    // Whether the pasteboard holds elements is checked when the command runs (menus cannot observe it).
    case .paste: return true
    case .bringForward, .sendBackward:
      return !editing && !editor.selection.isEmpty && editor.document.elements.count > 1
    case .cropTool, .resize, .rotateLeft, .rotateRight, .flipHorizontal, .flipVertical, .expandCanvas, .copyImage,
      .exportAs:
      return !editing && !editor.isInteracting
    case .zoomIn, .zoomOut, .actualSize, .zoomToFit: return handle.canvas != nil
    }
  }

  // MARK: Actions

  /// Runs `command` when enabled. Returns false when it was disabled or had nothing to do.
  @discardableResult
  public func perform(_ command: Command) -> Bool {
    guard isEnabled(command) else { return false }
    switch command {
    case .cut:
      if isEditingText { return forward(#selector(NSText.cut(_:))) }
      guard bridge.copyElements(from: editor) else { return false }
      editor.removeSelection()
    case .copy:
      if isEditingText { return forward(#selector(NSText.copy(_:))) }
      return bridge.copyElements(from: editor)
    case .paste:
      if isEditingText { return forward(#selector(NSText.paste(_:))) }
      return bridge.pasteElements(into: editor)
    case .delete: editor.removeSelection()
    case .selectAll:
      if isEditingText { return forward(#selector(NSText.selectAll(_:))) }
      editor.selectAll()
    case .bringForward: editor.bringForward()
    case .sendBackward: editor.sendBackward()
    case .cropTool: editor.currentTool = .crop
    case .resize: beginResize()
    case .rotateLeft: attempt { try editor.rotate90(clockwise: false) }
    case .rotateRight: attempt { try editor.rotate90(clockwise: true) }
    case .flipHorizontal: attempt { try editor.flip(axis: .horizontal) }
    case .flipVertical: attempt { try editor.flip(axis: .vertical) }
    case .expandCanvas: expandCanvas(.right)
    case .copyImage:
      return attempt { try bridge.writeImage(try DocumentRenderer.flatten(editor.document, scale: 1)) }
    case .exportAs: presentExport()
    case .zoomIn: handle.zoomIn()
    case .zoomOut: handle.zoomOut()
    case .actualSize: handle.actualSize()
    case .zoomToFit: handle.zoomToFit()
    }
    return true
  }

  /// Grows the canvas by `expandAmount` pixels on `edge`.
  @discardableResult
  public func expandCanvas(_ edge: CanvasEdge) -> Bool {
    guard isEnabled(.expandCanvas) else { return false }
    return attempt { try editor.expandCanvas(edge: edge, amount: Self.expandAmount) }
  }

  @discardableResult
  private func attempt(_ operation: () throws -> Void) -> Bool {
    do {
      try operation()
      errorMessage = nil
      return true
    } catch {
      errorMessage = "\(error)"
      return false
    }
  }

  /// Sends a standard text action to the first responder (the text overlay while editing).
  private func forward(_ action: Selector) -> Bool {
    NSApp.sendAction(action, to: nil, from: nil)
  }
}

extension FocusedValues {
  /// The editor commands of the key window's document.
  @Entry public var editorCommands: EditorCommandModel?
}
