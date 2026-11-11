import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct TextToolTests {
  private let style = Style(color: .red, sizeStep: .default, strokeWidth: 4, fontSize: 48)

  private func makeEditor(_ elements: [Element] = []) -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    manager.groupsByEvent = false
    var document = Document.blank(size: CGSize(width: 800, height: 600))
    document.elements = elements
    let editor = EditorModel(document: document, undoManager: manager)
    editor.currentTool = .text
    return (editor, manager)
  }

  private func makeController(_ editor: EditorModel, zoom: Double = 1) -> TextToolController {
    TextToolController(editor: editor, zoom: { zoom })
  }

  private func textElement(_ string: String, at origin: CGPoint = CGPoint(x: 100, y: 100)) -> Element {
    Element(kind: .text(TextContent(string: string, origin: origin, wrapWidth: nil, styled: true)), style: style)
  }

  private func string(of element: Element) -> String? {
    if case .text(let content) = element.kind { return content.string }
    return nil
  }

  /// Runs `body` as one explicit undo group.
  private func grouped(_ manager: UndoManager, _ body: () -> Void) {
    manager.beginUndoGrouping()
    body()
    manager.endUndoGrouping()
  }

  // MARK: State machine

  @Test func clickCreatesTextAndCommitIsOneUndoStep() {
    let (editor, manager) = makeEditor()
    let controller = makeController(editor)
    controller.mouseDown(at: CGPoint(x: 50, y: 60), modifiers: [])
    controller.mouseUp(at: CGPoint(x: 50, y: 60), modifiers: [])
    #expect(controller.isEditing)
    #expect(controller.session?.isNew == true)
    #expect(controller.session?.content.origin == CGPoint(x: 50, y: 60))
    #expect(editor.document.elements.count == 1)

    grouped(manager) { controller.commit(text: "Hello") }
    #expect(!controller.isEditing)
    #expect(editor.document.elements.count == 1)
    #expect(string(of: editor.document.elements[0]) == "Hello")
    #expect(editor.selection == [editor.document.elements[0].id])
    #expect(manager.undoActionName == "Add Text")

    manager.undo()
    #expect(editor.document.elements.isEmpty)
    #expect(!manager.canUndo)
    manager.redo()
    #expect(string(of: editor.document.elements[0]) == "Hello")
  }

  @Test func emptyCommitRemovesNewTextWithoutUndoEntry() {
    let (editor, manager) = makeEditor()
    let controller = makeController(editor)
    controller.beginCreating(at: CGPoint(x: 10, y: 10))
    #expect(editor.document.elements.count == 1)
    controller.commit(text: "")
    #expect(editor.document.elements.isEmpty)
    #expect(!manager.canUndo)
    #expect(!editor.isInteracting)
  }

  @Test func whitespaceOnlyCommitCountsAsEmpty() {
    let (editor, manager) = makeEditor()
    let controller = makeController(editor)
    controller.beginCreating(at: .zero)
    controller.commit(text: "  \n ")
    #expect(editor.document.elements.isEmpty)
    #expect(!manager.canUndo)
  }

  @Test func doubleClickEditsExistingTextAsOneUndoStep() {
    let existing = textElement("Old")
    let (editor, manager) = makeEditor([existing])
    let controller = makeController(editor)
    controller.mouseDown(at: CGPoint(x: 110, y: 110), modifiers: [], clickCount: 2)
    #expect(controller.isEditing)
    #expect(controller.session?.isNew == false)
    #expect(controller.session?.string == "Old")
    // The overlay draws the text while editing, so the document copy is hidden.
    #expect(string(of: editor.document.elements[0]) == "")

    controller.update(text: "Older")
    grouped(manager) { controller.commit(text: "Older text") }
    #expect(string(of: editor.document.elements[0]) == "Older text")
    #expect(editor.document.elements[0].id == existing.id)
    #expect(manager.undoActionName == "Edit Text")

    manager.undo()
    #expect(string(of: editor.document.elements[0]) == "Old")
    #expect(!manager.canUndo)
    manager.redo()
    #expect(string(of: editor.document.elements[0]) == "Older text")
  }

  @Test func unchangedEditRegistersNothing() {
    let (editor, manager) = makeEditor([textElement("Same")])
    let controller = makeController(editor)
    controller.beginEditing(editor.document.elements[0].id)
    controller.commit(text: "Same")
    #expect(!manager.canUndo)
    #expect(string(of: editor.document.elements[0]) == "Same")
  }

  @Test func emptyingExistingTextDeletesItAsOneUndoStep() {
    let (editor, manager) = makeEditor([textElement("Gone")])
    let controller = makeController(editor)
    controller.beginEditing(editor.document.elements[0].id)
    grouped(manager) { controller.commit(text: "") }
    #expect(editor.document.elements.isEmpty)
    #expect(manager.undoActionName == "Delete Text")
    manager.undo()
    #expect(string(of: editor.document.elements[0]) == "Gone")
  }

  @Test func cancelRestoresDocument() {
    let (editor, manager) = makeEditor([textElement("Keep")])
    let before = editor.document
    let controller = makeController(editor)
    controller.beginEditing(editor.document.elements[0].id)
    controller.cancel()
    #expect(editor.document == before)
    #expect(!manager.canUndo)
    #expect(!controller.isEditing)
  }

  @Test func clickWhileEditingJustCommits() {
    let (editor, manager) = makeEditor()
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    let controller = makeController(editor)
    controller.beginCreating(at: CGPoint(x: 10, y: 10))
    controller.update(text: "abc")
    controller.mouseDown(at: CGPoint(x: 300, y: 300), modifiers: [])
    #expect(!controller.isEditing)
    #expect(editor.document.elements.count == 1)
    #expect(string(of: editor.document.elements[0]) == "abc")
  }

  @Test func escapeWhileEditingCommits() {
    let (editor, manager) = makeEditor()
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    let controller = makeController(editor)
    controller.beginCreating(at: .zero)
    controller.update(text: "x")
    #expect(controller.keyDown(.escape, modifiers: []))
    #expect(string(of: editor.document.elements[0]) == "x")
  }

  @Test func singleClickOnTextSelectsInsteadOfEditing() {
    let (editor, _) = makeEditor([textElement("Pick")])
    let controller = makeController(editor)
    controller.mouseDown(at: CGPoint(x: 110, y: 110), modifiers: [])
    controller.mouseUp(at: CGPoint(x: 110, y: 110), modifiers: [])
    #expect(!controller.isEditing)
    #expect(editor.selection == [editor.document.elements[0].id])
    #expect(editor.document.elements.count == 1)
  }

  @Test func newTextUsesNextStyleAndTextStyling() {
    let (editor, manager) = makeEditor()
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    editor.nextTextStyled = false
    editor.nextColor = .blue
    let controller = makeController(editor)
    controller.beginCreating(at: .zero)
    controller.commit(text: "x")
    let element = editor.document.elements[0]
    #expect(element.style.color == .blue)
    if case .text(let content) = element.kind { #expect(!content.styled) }
  }

  // MARK: Type to create

  @Test func typingSeedsTheFirstCharacter() {
    let (editor, manager) = makeEditor()
    let controller = makeController(editor)
    controller.mouseDown(at: CGPoint(x: 70, y: 80), modifiers: [])
    controller.commit(text: "")
    #expect(controller.keyDown(.character("Q"), modifiers: [.shift]))
    #expect(controller.isEditing)
    #expect(controller.session?.string == "Q")
    #expect(controller.session?.content.origin == CGPoint(x: 70, y: 80))
    grouped(manager) { controller.commit(text: "Qu") }
    #expect(string(of: editor.document.elements[0]) == "Qu")
    #expect(manager.undoActionName == "Add Text")
  }

  @Test func typingWithoutPriorClickUsesDefaultOrigin() {
    let (editor, _) = makeEditor()
    let controller = makeController(editor)
    #expect(controller.keyDown(.character("a"), modifiers: []))
    #expect(controller.session?.content.origin == CGPoint(x: 80, y: 60))
  }

  @Test func shortcutsAndControlCharactersDoNotCreateText() {
    let (editor, _) = makeEditor()
    let controller = makeController(editor)
    #expect(!controller.keyDown(.character("c"), modifiers: [.command]))
    #expect(!controller.keyDown(.character("\r"), modifiers: []))
    #expect(!controller.keyDown(.character("\u{F700}"), modifiers: []))
    #expect(!controller.isEditing)
    #expect(editor.document.elements.isEmpty)
  }

  // MARK: Wrap-width handle

  @Test func textOffersWrapWidthHandleAtRightEdge() {
    let element = textElement("Wrap me")
    #expect(HandleLayout.available(for: element).contains(.wrapWidth))
    let base = element.baseBounds
    let point = HandleLayout.position(of: .wrapWidth, on: element, zoom: 1)!
    #expect(abs(point.x - base.maxX) < 1e-6 && abs(point.y - base.midY) < 1e-6)
    #expect(HandleLayout.hit(element, at: point, zoom: 1) == .wrapWidth)
  }

  @Test func draggingWrapHandleSetsWrapWidthAndKeepsLeftEdge() {
    let element = textElement("A fairly long line of text")
    let base = element.baseBounds
    let target = CGPoint(x: base.minX + 200, y: base.midY)
    let updated = HandleLayout.apply(.wrapWidth, to: element, pointer: target, modifiers: [])
    guard case .text(let content) = updated.kind else {
      Issue.record("not text")
      return
    }
    #expect(content.wrapWidth == 200)
    #expect(content.origin == element.baseBounds.origin)
    #expect(updated.baseBounds.minX == base.minX)
    // Narrower than the minimum clamps.
    let tiny = HandleLayout.apply(.wrapWidth, to: element, pointer: CGPoint(x: base.minX - 50, y: 0), modifiers: [])
    if case .text(let narrow) = tiny.kind { #expect(narrow.wrapWidth == 2 * style.fontSize) }
  }

  @Test func rotatedWrapDragKeepsTopLeftOnScreen() {
    var element = textElement("Rotate and wrap this text")
    element.rotation = .pi / 3
    let base = element.baseBounds
    let leftBefore = GeometryMath.rotate(
      CGPoint(x: base.minX, y: base.minY), about: CGPoint(x: base.midX, y: base.midY), by: element.rotation)
    let handle = HandleLayout.position(of: .wrapWidth, on: element, zoom: 1)!
    // Drag along the rotated x axis by 40 units.
    let pointer = CGPoint(x: handle.x + 40 * cos(element.rotation), y: handle.y + 40 * sin(element.rotation))
    let updated = HandleLayout.apply(.wrapWidth, to: element, pointer: pointer, modifiers: [])
    let newBase = updated.baseBounds
    let leftAfter = GeometryMath.rotate(
      CGPoint(x: newBase.minX, y: newBase.minY), about: CGPoint(x: newBase.midX, y: newBase.midY), by: updated.rotation)
    #expect(abs(leftBefore.x - leftAfter.x) < 1e-6 && abs(leftBefore.y - leftAfter.y) < 1e-6)
    if case .text(let content) = updated.kind { #expect(abs((content.wrapWidth ?? 0) - (base.width + 40)) < 1e-6) }
  }

  @Test func wrapHandleDragThroughTextToolIsOneUndoStep() {
    let element = textElement("Some wrapped text")
    let (editor, manager) = makeEditor([element])
    editor.select(element.id)
    let controller = makeController(editor)
    let handle = HandleLayout.position(of: .wrapWidth, on: element, zoom: 1)!
    let target = CGPoint(x: handle.x - 60, y: handle.y)
    grouped(manager) {
      controller.mouseDown(at: handle, modifiers: [])
      controller.mouseDragged(to: CGPoint(x: handle.x - 30, y: handle.y), modifiers: [])
      controller.mouseDragged(to: target, modifiers: [])
      controller.mouseUp(at: target, modifiers: [])
    }
    guard case .text(let content) = editor.document.elements[0].kind else {
      Issue.record("not text")
      return
    }
    #expect(content.wrapWidth != nil)
    #expect(!controller.isEditing)
    #expect(manager.undoActionName == "Change Text Width")
    manager.undo()
    if case .text(let restored) = editor.document.elements[0].kind { #expect(restored.wrapWidth == nil) }
    #expect(!manager.canUndo)
  }

  // MARK: Canvas overlay

  @Test func canvasShowsOverlayWhileEditingAndFollowsZoom() {
    let (editor, manager) = makeEditor()
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    let canvas = CanvasView(editor: editor)
    canvas.setFrameSize(CGSize(width: 1200, height: 1000))
    #expect(canvas.textOverlay == nil)
    let controller = canvas.activeController
    controller.mouseDown(at: CGPoint(x: 100, y: 100), modifiers: [])
    guard let overlay = canvas.textOverlay else {
      Issue.record("no overlay")
      return
    }
    #expect(overlay.superview === canvas)

    // Typing in the overlay flows back into the session and the overlay frame follows the text.
    let emptyWidth = overlay.frame.width
    overlay.string = "Hello world"
    overlay.didChangeText()
    #expect(overlay.frame.width > emptyWidth)
    let oneX = overlay.frame
    #expect(abs(oneX.minX - canvas.viewPoint(fromDocument: CGPoint(x: 100, y: 100)).x) < 1e-6)

    canvas.setZoom(2)
    let twoX = overlay.frame
    #expect(abs((twoX.height) - 2 * oneX.height) < 1e-6)
    #expect(abs(overlay.font!.pointSize - 2 * (editor.nextStyle(for: .text)?.fontSize ?? 0)) < 1e-6)

    overlay.onCommit?(overlay.string)
    #expect(canvas.textOverlay == nil)
    #expect(editor.document.elements.count == 1)
    if case .text(let content) = editor.document.elements[0].kind { #expect(content.string == "Hello world") }
  }

  @Test func switchingToolCommitsTheEdit() {
    let (editor, manager) = makeEditor()
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    let canvas = CanvasView(editor: editor)
    canvas.activeController.mouseDown(at: CGPoint(x: 20, y: 20), modifiers: [])
    canvas.textOverlay?.string = "kept"
    canvas.textOverlay?.didChangeText()
    editor.currentTool = .select
    // Observation delivers on the main actor; run it directly like the canvas does.
    canvas.editorDidChange()
    #expect(canvas.textOverlay == nil)
    #expect(editor.document.elements.count == 1)
  }

  // MARK: Save and undo during an edit

  /// A document wired like the app: saving reads the running edit through the canvas.
  @MainActor
  private struct SaveFixture {
    let document: SkitchoDocument
    let manager: UndoManager
    let canvas: CanvasView
    let controller: TextToolController
    var editor: EditorModel { document.editor }

    /// Saves outside any undo group: a registration would raise (the manager does not group by event).
    func save() throws -> Document { try document.snapshot(contentType: .skitchoDocument) }

    /// Saves inside one undo group, as the app does, and lets the checkpoint that `snapshot` schedules on the
    /// main actor run inside that group.
    func saveStep() async throws -> Document {
      manager.beginUndoGrouping()
      defer { manager.endUndoGrouping() }
      let saved = try save()
      for _ in 0..<3 { await Task.yield() }
      return saved
    }
  }

  private func makeSaveFixture(_ elements: [Element] = []) throws -> SaveFixture {
    var initial = Document.blank(size: CGSize(width: 800, height: 600))
    initial.elements = elements
    let document = SkitchoDocument(initial: initial)
    let manager = UndoManager()
    manager.groupsByEvent = false
    document.editor.undoManager = manager
    document.editor.currentTool = .text
    let canvas = CanvasView(editor: document.editor)
    document.canvasHandle.attach(canvas)
    let controller = try #require(canvas.activeController as? TextToolController)
    return SaveFixture(document: document, manager: manager, canvas: canvas, controller: controller)
  }

  /// A save while text is edited writes the live string (not the blank placeholder) and keeps the edit open.
  @Test func snapshotDuringEditContainsTheLiveText() async throws {
    let element = textElement("Hello")
    let f = try makeSaveFixture([element])
    #expect(f.controller.beginEditing(element.id))
    #expect(string(of: f.editor.document.elements[0]) == "")
    // Unchanged text: the file keeps "Hello" and the undo stack already holds it, so no step.
    #expect(string(of: try f.save().elements[0]) == "Hello")
    #expect(!f.manager.canUndo)

    f.controller.update(text: "Hello world")
    let saved = try await f.saveStep()
    #expect(string(of: saved.elements[0]) == "Hello world")
    #expect(f.manager.undoActionName == "Edit Text")
    // The edit goes on uninterrupted: same session, element still hidden behind the overlay.
    #expect(f.controller.isEditing)
    #expect(f.editor.isInteracting)
    #expect(f.controller.session?.string == "Hello world")
    #expect(string(of: f.editor.document.elements[0]) == "")

    // Emptied text would be deleted by the commit, so it is not saved either; that save is a delete step.
    f.controller.update(text: "  ")
    let savedEmpty = try await f.saveStep()
    #expect(savedEmpty.elements.isEmpty)
    #expect(f.manager.undoActionName == "Delete Text")
    // Retyping the start text brings the element back as one more step; undo walks through every save.
    f.controller.update(text: "Hello")
    grouped(f.manager) { f.controller.commit() }
    #expect(string(of: f.editor.document.elements[0]) == "Hello")
    #expect(try f.save() == f.editor.document)
    f.manager.undo()
    #expect(f.editor.document == savedEmpty)
    f.manager.undo()
    #expect(f.editor.document == saved)
    f.manager.undo()
    #expect(string(of: f.editor.document.elements[0]) == "Hello")
    #expect(!f.manager.canUndo)
  }

  /// Saved mid-edit, then committed with the saved text: the save's step is the only one.
  @Test func saveMidEditThenUnchangedCommitAddsNoStep() async throws {
    let element = textElement("A")
    let f = try makeSaveFixture([element])
    #expect(f.controller.beginEditing(element.id))
    f.controller.update(text: "B")
    let saved = try await f.saveStep()
    // No group is open: a second step would raise.
    f.controller.commit()
    #expect(f.editor.document == saved)
    #expect(!f.editor.isInteracting)
    #expect(f.editor.selection == [element.id])
    f.manager.undo()
    #expect(string(of: f.editor.document.elements[0]) == "A")
    #expect(!f.manager.canUndo)
  }

  /// Saved as B mid-edit, continued to C and committed: undo goes C, B, A and redo goes back A, B, C.
  @Test func saveMidEditThenContinueUndoesThroughTheSavedState() async throws {
    for isNew in [false, true] {
      let element = textElement("A")
      let f = try makeSaveFixture(isNew ? [] : [element])
      if isNew {
        #expect(f.controller.beginCreating(at: CGPoint(x: 100, y: 100)))
      } else {
        #expect(f.controller.beginEditing(element.id))
      }
      let start = f.document.initial
      let name = isNew ? "Add Text" : "Edit Text"
      f.controller.update(text: "B")
      let saved = try await f.saveStep()
      #expect(f.manager.undoActionName == name)
      f.controller.update(text: "C")
      grouped(f.manager) { f.controller.commit() }
      let committed = f.editor.document
      #expect(string(of: committed.elements[0]) == "C")
      #expect(f.manager.undoActionName == name)

      f.manager.undo()
      #expect(f.editor.document == saved, "isNew \(isNew): undo returns to the saved state")
      f.manager.undo()
      #expect(f.editor.document == start)
      #expect(!f.manager.canUndo)
      f.manager.redo()
      #expect(f.editor.document == saved)
      f.manager.redo()
      #expect(f.editor.document == committed)
      #expect(!f.manager.canRedo)
    }
  }

  /// Saved mid-edit, then cancelled: the document returns to the saved state (the file and the screen
  /// agree), and the save's step still leads back to the start.
  @Test func saveMidEditThenCancelKeepsTheSavedState() async throws {
    for isNew in [false, true] {
      let element = textElement("A")
      let f = try makeSaveFixture(isNew ? [] : [element])
      if isNew {
        #expect(f.controller.beginCreating(at: CGPoint(x: 100, y: 100)))
      } else {
        #expect(f.controller.beginEditing(element.id))
      }
      let start = f.document.initial
      f.controller.update(text: "B")
      let saved = try await f.saveStep()
      f.controller.update(text: "C")
      // No group is open: the cancel must not register anything.
      f.controller.cancel()
      #expect(!f.controller.isEditing)
      #expect(!f.editor.isInteracting)
      #expect(f.editor.document == saved, "isNew \(isNew): cancel keeps what was saved")
      #expect(try f.save() == saved)
      f.manager.undo()
      #expect(f.editor.document == start)
      #expect(!f.manager.canUndo)
      f.manager.redo()
      #expect(f.editor.document == saved)
    }
  }

  /// An empty new text equals the state before it, so saving it registers nothing.
  @Test func saveDuringEmptyNewTextRegistersNothing() throws {
    let f = try makeSaveFixture()
    #expect(f.controller.beginCreating(at: CGPoint(x: 10, y: 10)))
    // No group is open: a registration would raise.
    #expect(try f.save().elements.isEmpty)
    f.controller.update(text: " \n")
    #expect(try f.save().elements.isEmpty)
    f.controller.commit()
    #expect(f.editor.document.elements.isEmpty)
    #expect(!f.manager.canUndo)
  }

  /// A new label saved with text and then emptied is deleted together with its link as one step.
  @Test func savedNewLabelEmptiedIsDeletedAsOneStep() async throws {
    let stamp = Element(
      kind: .stamp(.approve, center: CGPoint(x: 200, y: 200), tailAngle: nil, labelID: nil), style: style)
    let f = try makeSaveFixture([stamp])
    f.editor.currentTool = .stamp
    #expect(f.canvas.attachLabel(to: stamp.id))
    let labelID = try #require(f.controller.session?.id)
    f.controller.update(text: "B")
    let saved = try await f.saveStep()
    #expect(saved.elements.count == 2)
    #expect(f.manager.undoActionName == "Add Text")

    f.controller.update(text: "")
    grouped(f.manager) { f.controller.commit() }
    #expect(f.editor.document == f.document.initial, "the label and its link are gone")
    #expect(f.manager.undoActionName == "Delete Text")
    f.manager.undo()
    #expect(f.editor.document == saved)
    guard case .stamp(_, _, _, let label) = f.editor.document.elements[0].kind else {
      Issue.record("expected the stamp first")
      return
    }
    #expect(label == labelID)
    f.manager.undo()
    #expect(f.editor.document == f.document.initial)
    #expect(!f.manager.canUndo)
  }

  /// Undo is disabled during an edit; if one still runs after a mid-edit save, it undoes the save's step and
  /// the editor closes without registering anything, so the redo stays available.
  @Test func undoDuringSavedEditRegistersNothing() async throws {
    let element = textElement("A")
    let f = try makeSaveFixture([element])
    #expect(f.controller.beginEditing(element.id))
    f.controller.update(text: "B")
    let saved = try await f.saveStep()
    f.controller.update(text: "C")
    f.manager.undo()
    #expect(!f.editor.isInteracting)
    #expect(f.editor.document == f.document.initial)
    // The canvas notices the ended gesture and cancels the edit. No group is open: a registration would raise.
    f.canvas.editorDidChange()
    #expect(!f.controller.isEditing)
    #expect(f.editor.document == f.document.initial)
    #expect(!f.manager.canUndo)
    #expect(f.manager.canRedo)
    f.manager.redo()
    #expect(f.editor.document == saved)
  }

  /// The checkpoint a save schedules is skipped when the edit ends before it runs: the commit already
  /// registers the one step, so nothing is added.
  @Test func scheduledCheckpointIsSkippedWhenTheEditEndedMeanwhile() async throws {
    let element = textElement("Hello")
    let f = try makeSaveFixture([element])
    #expect(f.controller.beginEditing(element.id))
    f.controller.update(text: "Hello world")
    let saved = try f.save()
    #expect(string(of: saved.elements[0]) == "Hello world")
    grouped(f.manager) { f.controller.commit() }
    for _ in 0..<3 { await Task.yield() }
    #expect(f.manager.undoActionName == "Edit Text")
    f.manager.undo()
    #expect(!f.manager.canUndo)
    #expect(f.editor.document == f.document.initial)
  }

  /// An empty new stamp label is not saved, and neither is its link.
  @Test func snapshotDuringEmptyNewLabelDropsTheLink() throws {
    let (editor, _) = makeEditor()
    editor.currentTool = .stamp
    let canvas = CanvasView(editor: editor)
    let stamp = Element(
      kind: .stamp(.approve, center: CGPoint(x: 200, y: 200), tailAngle: nil, labelID: nil), style: style)
    editor.document.elements = [stamp]
    #expect(canvas.attachLabel(to: stamp.id))
    #expect(canvas.isEditingText)
    let saved = canvas.savableDocument
    #expect(saved.elements.count == 1)
    guard case .stamp(_, _, _, let label) = saved.elements.first?.kind else {
      Issue.record("expected the stamp to be saved")
      return
    }
    #expect(label == nil)
  }

  /// Undo is unavailable while the overlay (the first responder during an edit) is up.
  @Test func overlayDisablesUndoAndRedo() {
    let overlay = TextEditorOverlay(sessionID: UUID(), string: "Hi")
    for name in ["undo:", "redo:"] {
      let item = NSMenuItem(title: name, action: Selector(name), keyEquivalent: "")
      #expect(overlay.responds(to: Selector(name)))
      #expect(!overlay.validateMenuItem(item))
      #expect(!overlay.validateUserInterfaceItem(item))
    }
    let copy = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
    #expect(overlay.validateMenuItem(copy))
  }

  /// If an undo still runs during an edit, the edit is dropped: no stray mutation, no bogus undo step.
  @Test func undoDuringEditDropsTheEditWithoutRegistering() {
    let element = textElement("Hello")
    let (editor, manager) = makeEditor([element])
    editor.select(element.id)
    grouped(manager) { editor.moveSelection(by: CGPoint(x: 10, y: 0)) }
    let canvas = CanvasView(editor: editor)
    guard let controller = canvas.activeController as? TextToolController else {
      Issue.record("expected the text controller")
      return
    }
    #expect(controller.beginEditing(element.id))
    controller.update(text: "World")
    manager.undo()
    let afterUndo = editor.document
    #expect(string(of: afterUndo.elements[0]) == "Hello")
    #expect(afterUndo.elements[0].bounds.minX == element.bounds.minX)

    // The canvas notices the ended gesture and closes the editor without applying it.
    canvas.editorDidChange()
    #expect(!controller.isEditing)
    #expect(canvas.textOverlay == nil)
    #expect(editor.document == afterUndo)
    #expect(manager.canRedo)
    #expect(!manager.canUndo)

    // A commit arriving late (overlay resigning) changes nothing either.
    editor.select(element.id)
    grouped(manager) { editor.moveSelection(by: CGPoint(x: 5, y: 0)) }
    #expect(controller.beginEditing(element.id))
    manager.undo()
    controller.commit(text: "Late")
    #expect(!controller.isEditing)
    #expect(string(of: editor.document.elements[0]) == "Hello")
    #expect(!manager.canUndo)
  }
}
