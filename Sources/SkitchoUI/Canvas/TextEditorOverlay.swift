import AppKit
import CoreGraphics
import Foundation
import SkitchoCore

/// The in-place text editor: a transparent NSTextView laid over the canvas, matched to the edited element at
/// the current zoom. It only reports typing and "done" events; all document changes happen in
/// `TextToolController`. Rotated text is edited upright; the rendered element turns again after the commit.
@MainActor
final class TextEditorOverlay: NSTextView {
  /// Extra width so the caret at the end of a line is not clipped (view points).
  static let caretPadding: CGFloat = 4

  let sessionID: UUID
  var onTextChange: ((String) -> Void)?
  var onCommit: ((String) -> Void)?

  init(sessionID: UUID, string: String) {
    self.sessionID = sessionID
    // Build the text system explicitly: a nil container would leave the view without storage.
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    let container = NSTextContainer(
      size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    super.init(frame: .zero, textContainer: container)
    isRichText = false
    allowsUndo = false
    drawsBackground = false
    isHorizontallyResizable = false
    isVerticallyResizable = false
    textContainerInset = .zero
    textContainer?.lineFragmentPadding = 0
    textContainer?.widthTracksTextView = false
    self.string = string
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Positions, sizes and styles the editor for `session` under `geometry`.
  func apply(session: TextEditSession, geometry: CanvasGeometry) {
    let size = session.frame.size
    setFrameSize(
      NSSize(width: size.width * geometry.zoom + Self.caretPadding, height: size.height * geometry.zoom))
    setFrameOrigin(geometry.viewPoint(fromDocument: session.content.origin))
    textContainer?.containerSize = NSSize(
      width: session.content.wrapWidth.map { $0 * geometry.zoom } ?? CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude)
    font = NSFont.systemFont(ofSize: max(1, session.style.fontSize * geometry.zoom))
    let color = NSColor(cgColor: session.style.color.cgColor) ?? .black
    textColor = color
    insertionPointColor = color
  }

  // The edit runs inside an open editor gesture, so the document's Undo/Redo must wait until it ends: an undo
  // now would swap the document under the edit. The overlay is the first responder while editing, so it
  // answers the Edit menu's undo:/redo: actions itself and keeps them disabled.
  @objc func undo(_ sender: Any?) {}
  @objc func redo(_ sender: Any?) {}

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(undo(_:)) || item.action == #selector(redo(_:)) { return false }
    return super.validateUserInterfaceItem(item)
  }

  override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(undo(_:)) || menuItem.action == #selector(redo(_:)) { return false }
    return super.validateMenuItem(menuItem)
  }

  override func didChangeText() {
    super.didChangeText()
    onTextChange?(string)
  }

  /// Escape finishes the edit and keeps the text.
  override func cancelOperation(_ sender: Any?) {
    onCommit?(string)
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { onCommit?(string) }
    return resigned
  }
}
