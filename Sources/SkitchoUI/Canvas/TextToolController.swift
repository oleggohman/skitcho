import AppKit
import CoreGraphics
import Foundation
import SkitchoCore

/// State of one text edit, shared between the controller and the NSTextView overlay.
public struct TextEditSession: Equatable, Sendable {
  public let id: UUID
  /// True when the element was created by this edit (so an empty result removes it without an undo step).
  public let isNew: Bool
  /// Live content: the typed string plus the element's origin and wrap width.
  public var content: TextContent
  public let style: Style
  public let rotation: Double

  public var string: String { content.string }

  /// The laid-out text box in document space.
  public var frame: CGRect {
    CGRect(origin: content.origin, size: TextRenderer.size(for: content, fontSize: style.fontSize))
  }
}

/// The T tool: a click creates text and opens the in-place editor, a double-click edits existing text,
/// typing with no edit running starts a new text seeded with the typed character.
///
/// The state machine (idle -> editing -> committed) has no AppKit dependency: the canvas shows a
/// `TextEditorOverlay` for `session` and feeds `update(text:)` / `commit(text:)` back. While editing, the
/// element sits in the document with an empty string (the overlay draws the text) inside an interactive
/// gesture, so a commit registers exactly one undo step and an empty result registers none for new text.
/// A save during the edit adds one step up to the saved state (see `checkpointSavedEdit(_:)`).
@MainActor
public final class TextToolController: ToolController {
  public static let supportedTools: [Tool] = [.text]

  private let editor: EditorModel
  private let zoom: () -> Double
  /// Moves, selects and resizes existing text (handles, wrap width) outside of editing.
  private let manipulator: SelectPanToolController

  /// The running edit, nil when idle.
  public private(set) var session: TextEditSession?
  /// Where type-to-create puts new text: the last pressed point, else the top-left area of the canvas.
  private var lastPoint: CGPoint?
  private var manipulating = false

  /// Called whenever `session` starts, changes or ends.
  public var editingDidChange: (() -> Void)?
  public var needsDisplay: (() -> Void)? {
    didSet { manipulator.needsDisplay = needsDisplay }
  }

  public init(editor: EditorModel, zoom: @escaping () -> Double) {
    self.editor = editor
    self.zoom = zoom
    self.manipulator = SelectPanToolController(editor: editor, zoom: zoom)
  }

  public var cursor: NSCursor { ToolCursors.cursor(for: .text) }

  public var isEditing: Bool { session != nil }

  // MARK: State machine

  /// Creates an empty text element at `point` (the top-left of the text box) and starts editing it. `seed` is
  /// the first typed character(s). Returns false when text cannot be created.
  @discardableResult
  public func beginCreating(at point: CGPoint, seed: String = "") -> Bool {
    if isEditing { commit() }
    guard let style = editor.nextStyle(for: .text) else { return false }
    let content = TextContent(string: "", origin: point, wrapWidth: nil, styled: editor.nextTextStyled)
    editor.beginInteractive()
    let element = Element(kind: .text(content), style: style)
    editor.document.elements.append(element)
    var live = content
    live.string = seed
    session = TextEditSession(id: element.id, isNew: true, content: live, style: style, rotation: 0)
    editor.deselect()
    changed()
    return true
  }

  /// Starts editing the existing text element `id`. Returns false when it is not a text element.
  @discardableResult
  public func beginEditing(_ id: UUID) -> Bool {
    if isEditing { commit() }
    guard let index = editor.document.elements.firstIndex(where: { $0.id == id }),
      case .text(let content) = editor.document.elements[index].kind
    else { return false }
    let element = editor.document.elements[index]
    editor.beginInteractive()
    var hidden = content
    hidden.string = ""
    editor.document.elements[index].kind = .text(hidden)
    session = TextEditSession(
      id: id, isNew: false, content: content, style: element.style, rotation: element.rotation)
    editor.deselect()
    changed()
    return true
  }

  /// Records the live string (the overlay's current text) so the overlay frame can follow it.
  public func update(text: String) {
    guard session != nil, session?.content.string != text else { return }
    session?.content.string = text
    changed()
  }

  /// Ends the edit with the overlay's current text.
  public func commit() {
    commit(text: session?.string ?? "")
  }

  /// Ends the edit with `text`. Empty (or whitespace-only) text removes the element: a new element leaves no
  /// undo entry, an existing one is deleted as one undo step. Otherwise exactly one undo step is registered
  /// ("Add Text" or "Edit Text"; none when an existing text is unchanged) and the element is selected.
  /// A save during the edit moved the gesture start to the saved state (see `checkpointSavedEdit(_:)`), so the
  /// step then runs from that state; a saved new text that is emptied is deleted as one step.
  public func commit(text: String) {
    guard var current = session else { return }
    guard editor.isInteracting else {
      // The edit's gesture was ended elsewhere (an undo restored another state): the edit no longer applies.
      session = nil
      changed()
      return
    }
    current.content.string = text
    session = current
    // The live string in place, or the element (and a new label's link) removed when it is blank.
    editor.document = documentCommittingEdit
    session = nil
    editor.commitInteractive(name: Self.stepName(for: current))
    if !Self.isBlank(text) { editor.select(current.id) }
    changed()
  }

  /// Abandons the edit with no undo entry: the document returns to the gesture start, which is the state
  /// before the edit (new text disappears, existing text is restored) or the last state saved during it.
  /// When an undo already ended the gesture, nothing is changed or registered.
  public func cancel() {
    guard session != nil else { return }
    session = nil
    editor.cancelInteractive()
    changed()
  }

  /// Puts `saved` (a document a save served while an edit was running) on the undo stack as one step.
  ///
  /// A save writes a state the undo stack must hold, or undoing past it would return the change count to
  /// the save while the file differs from the screen. So one step from the gesture start to the saved state
  /// is registered and the gesture continues from the saved state: the edit stays open, commit and cancel
  /// compare against what was saved, and undo and redo pass through it. An unchanged edit, or an empty new
  /// text, equals the start and registers nothing.
  ///
  /// `SkitchoDocument.snapshot` runs off the main actor and cannot register this itself, so it schedules this
  /// call on the main actor afterwards. It does nothing when the edit ended meanwhile or the document moved
  /// on (the next save serves the newer state). SwiftUI owns the change count, so the document may stay
  /// edited after the save; the next save or autosave, with no new step, then marks it clean.
  public func checkpointSavedEdit(_ saved: Document) {
    guard let session, editor.isInteracting, documentCommittingEdit == saved else { return }
    editor.checkpointInteractive(saved, name: Self.stepName(for: session))
  }

  /// The undo name of the step that ending `session` now would register.
  private static func stepName(for session: TextEditSession) -> String {
    if isBlank(session.string) { return "Delete Text" }
    return session.isNew ? "Add Text" : "Edit Text"
  }

  private static func isBlank(_ string: String) -> Bool {
    string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// The document as committing the running edit would leave it: the live string in place of the hidden one,
  /// or without the element when the live text is empty. Saving uses this, so a save during an edit writes
  /// what the user sees and the edit stays open. Equals `editor.document` when idle.
  public var documentCommittingEdit: Document {
    var document = editor.document
    guard let session, editor.isInteracting,
      let index = document.elements.firstIndex(where: { $0.id == session.id }),
      case .text(var content) = document.elements[index].kind
    else { return document }
    if Self.isBlank(session.string) {
      document.elements.remove(at: index)
      if session.isNew {
        // A new label is linked inside the same gesture; an empty commit drops the link too.
        for (i, element) in document.elements.enumerated() {
          if case .stamp(let kind, let center, let tail, let label) = element.kind, label == session.id {
            document.elements[i].kind = .stamp(kind, center: center, tailAngle: tail, labelID: nil)
          }
        }
      }
    } else {
      content.string = session.string
      document.elements[index].kind = .text(content)
    }
    return document
  }

  private func changed() {
    editingDidChange?()
    needsDisplay?()
  }

  // MARK: Pointer

  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers) {
    mouseDown(at: point, modifiers: modifiers, clickCount: 1)
  }

  public func mouseDown(at point: CGPoint, modifiers: ToolModifiers, clickCount: Int) {
    manipulating = false
    lastPoint = point
    if isEditing {
      // A press elsewhere only ends the edit.
      commit()
      return
    }
    let tolerance = SelectPanToolController.hitSlop / max(zoom(), 0.0001)
    let hit = editor.topMostHit(at: point, tolerance: tolerance)
    var hitText = false
    if let hit, case .text = hit.kind { hitText = true }
    if let hit, hitText, clickCount >= 2 {
      beginEditing(hit.id)
      return
    }
    // Selection rule: a press on a handle of the selection manipulates it; so does a press on text.
    if hitText || manipulator.pressesHandle(at: point) {
      manipulating = true
      manipulator.mouseDown(at: point, modifiers: modifiers)
      return
    }
    beginCreating(at: point)
  }

  public func mouseDragged(to point: CGPoint, modifiers: ToolModifiers) {
    if manipulating { manipulator.mouseDragged(to: point, modifiers: modifiers) }
  }

  public func mouseUp(at point: CGPoint, modifiers: ToolModifiers) {
    if manipulating { manipulator.mouseUp(at: point, modifiers: modifiers) }
    manipulating = false
  }

  // MARK: Keyboard

  public func keyDown(_ key: ToolKey, modifiers: ToolModifiers) -> Bool {
    if isEditing {
      // Keys normally reach the overlay; Escape here still ends the edit.
      guard key == .escape else { return false }
      commit()
      return true
    }
    if case .character(let character) = key, Self.isTypeable(character, modifiers: modifiers) {
      // Type-to-create: nothing is being edited, so the typed character starts a new text.
      let canvas = editor.document.canvasSize
      let origin = lastPoint ?? CGPoint(x: canvas.width * 0.1, y: canvas.height * 0.1)
      return beginCreating(at: origin, seed: String(character))
    }
    return manipulator.keyDown(key, modifiers: modifiers)
  }

  /// A printable character typed without Command/Control.
  static func isTypeable(_ character: Character, modifiers: ToolModifiers) -> Bool {
    guard modifiers.isDisjoint(with: [.command, .control]), !character.isNewline else { return false }
    return character.unicodeScalars.allSatisfy { scalar in
      switch scalar.properties.generalCategory {
      case .control, .privateUse, .unassigned: false
      default: true
      }
    }
  }

  public func overlay(in context: CGContext, zoom: Double) {
    // While editing, the overlay view draws the text; the selection chrome only applies outside editing.
    guard !isEditing else { return }
    manipulator.overlay(in: context, zoom: zoom)
  }
}
