import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

@MainActor
@Suite struct EditorUndoTests {
  private func makeEditor() -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    // Groups are opened explicitly by `step`; registering outside a group is an error with this setting.
    manager.groupsByEvent = false
    let editor = EditorModel(document: Document.blank(size: CGSize(width: 200, height: 100)), undoManager: manager)
    return (editor, manager)
  }

  private func rectElement(x: Double = 10) -> Element {
    Element(
      kind: .rect(CGRect(x: x, y: 10, width: 30, height: 20), rounded: false), style: testStyle(.red, stroke: 4))
  }

  /// Wraps one user action in its own undo group (the manager is not run-loop driven in tests).
  private func step(_ manager: UndoManager, _ body: () -> Void) {
    manager.beginUndoGrouping()
    body()
    manager.endUndoGrouping()
  }

  @Test func undoThenRedoRestoresEachState() {
    let (editor, manager) = makeEditor()
    let first = rectElement(x: 10)
    let second = rectElement(x: 60)
    step(manager) { editor.add(first) }
    step(manager) { editor.add(second) }
    #expect(editor.document.elements.map(\.id) == [first.id, second.id])

    manager.undo()
    #expect(editor.document.elements.map(\.id) == [first.id])
    manager.undo()
    #expect(editor.document.elements.isEmpty)
    #expect(!manager.canUndo)

    manager.redo()
    #expect(editor.document.elements.map(\.id) == [first.id])
    manager.redo()
    #expect(editor.document.elements.map(\.id) == [first.id, second.id])
    #expect(!manager.canRedo)

    manager.undo()
    #expect(editor.document.elements.map(\.id) == [first.id])
  }

  @Test func actionNamesSurviveUndoRedo() {
    let (editor, manager) = makeEditor()
    step(manager) { editor.perform("Draw Thing") { $0.elements.append(rectElement()) } }
    #expect(manager.undoActionName == "Draw Thing")
    manager.undo()
    #expect(manager.redoActionName == "Draw Thing")
    manager.redo()
    #expect(manager.undoActionName == "Draw Thing")
  }

  @Test func noOpChangeRegistersNothing() {
    let (editor, manager) = makeEditor()
    // No explicit undo group here: an empty group would itself make `canUndo` true.
    editor.perform("Nothing") { _ in }
    #expect(!manager.canUndo)
    editor.removeSelection()
    #expect(!manager.canUndo)
    editor.remove(ids: [UUID()])
    #expect(!manager.canUndo)
  }

  @Test func interactiveGestureIsOneUndoStep() {
    let (editor, manager) = makeEditor()
    let element = rectElement()
    step(manager) { editor.add(element) }
    let original = editor.document

    step(manager) {
      editor.beginInteractive()
      for _ in 0..<5 {
        editor.document.elements = editor.document.elements.map { $0.translated(by: CGPoint(x: 3, y: 0)) }
      }
      editor.commitInteractive(name: "Move")
    }
    #expect(manager.undoActionName == "Move")
    #expect(editor.document.elements[0].bounds.minX == element.bounds.minX + 15)

    manager.undo()
    #expect(editor.document == original)
    manager.redo()
    #expect(editor.document.elements[0].bounds.minX == element.bounds.minX + 15)
    manager.undo()
    manager.undo()  // the add
    #expect(editor.document.elements.isEmpty)
  }

  @Test func cancelInteractiveRevertsWithoutRegistering() {
    let (editor, manager) = makeEditor()
    let original = editor.document
    editor.beginInteractive()
    editor.document.elements.append(rectElement())
    #expect(editor.isInteracting)
    editor.cancelInteractive()
    #expect(editor.document == original)
    #expect(!editor.isInteracting)
    #expect(!manager.canUndo)
  }

  @Test func unchangedInteractiveGestureRegistersNothing() {
    let (editor, manager) = makeEditor()
    editor.beginInteractive()
    editor.commitInteractive(name: "Move")
    #expect(!manager.canUndo)
    // commit without begin is ignored
    editor.commitInteractive(name: "Move")
    #expect(!manager.canUndo)
  }

  @Test func worksWithoutUndoManager() {
    let editor = EditorModel(document: Document.blank(), undoManager: nil)
    editor.add(rectElement())
    #expect(editor.document.elements.count == 1)
  }

  // MARK: Selection

  @Test func selectionBasics() {
    let (editor, manager) = makeEditor()
    let a = rectElement(x: 10)
    let b = rectElement(x: 80)
    step(manager) {
      editor.add(a)
      editor.add(b)
    }
    #expect(editor.selection == [b.id])  // add selects the new element
    editor.select(a.id)
    #expect(editor.selection == [a.id])
    editor.toggleSelection(b.id)
    #expect(editor.selection == [a.id, b.id])
    editor.toggleSelection(a.id)
    #expect(editor.selection == [b.id])
    editor.toggleSelection(UUID())
    #expect(editor.selection == [b.id])
    editor.selectAll()
    #expect(editor.selection == [a.id, b.id])
    editor.deselect()
    #expect(editor.selection.isEmpty)
    editor.select(UUID())
    #expect(editor.selection.isEmpty)
  }

  @Test func topMostHitPicksLastDrawn() {
    let (editor, manager) = makeEditor()
    let below = rectElement(x: 10)
    var above = rectElement(x: 10)
    above.id = UUID()
    step(manager) {
      editor.add(below)
      editor.add(above)
    }
    #expect(editor.topMostHit(at: CGPoint(x: 10, y: 20), tolerance: 2)?.id == above.id)
    #expect(editor.topMostHit(at: CGPoint(x: 150, y: 80), tolerance: 2) == nil)
  }

  @Test func deleteKeepsSelectionConsistentAndUndoRestores() {
    let (editor, manager) = makeEditor()
    let a = rectElement(x: 10)
    step(manager) { editor.add(a) }
    step(manager) { editor.removeSelection() }
    #expect(editor.document.elements.isEmpty)
    #expect(editor.selection.isEmpty)
    #expect(manager.undoActionName == "Delete")
    manager.undo()
    #expect(editor.document.elements.map(\.id) == [a.id])
  }

  @Test func nudgeMovesByOneOrTen() {
    let (editor, manager) = makeEditor()
    let a = rectElement(x: 10)
    step(manager) { editor.add(a) }
    step(manager) { editor.nudgeSelection(dx: 1, dy: 0) }
    #expect(editor.document.elements[0].bounds.minX == 11)
    step(manager) { editor.nudgeSelection(dx: 0, dy: -1, large: true) }
    #expect(editor.document.elements[0].bounds.minY == 0)
    #expect(manager.undoActionName == "Nudge")
    manager.undo()
    #expect(editor.document.elements[0].bounds.minY == 10)
  }

  @Test func nudgeWithEmptySelectionIsNoOp() {
    let (editor, manager) = makeEditor()
    editor.nudgeSelection(dx: 1, dy: 1)
    #expect(!manager.canUndo)
  }

  @Test func reorderForwardAndBackward() {
    let (editor, manager) = makeEditor()
    let a = rectElement(x: 10)
    let b = rectElement(x: 40)
    let c = rectElement(x: 70)
    step(manager) { for element in [a, b, c] { editor.add(element) } }

    editor.select(a.id)
    step(manager) { editor.bringForward() }
    #expect(editor.document.elements.map(\.id) == [b.id, a.id, c.id])
    step(manager) { editor.bringForward() }
    #expect(editor.document.elements.map(\.id) == [b.id, c.id, a.id])
    editor.bringForward()  // already on top: no-op (no group, an empty group is itself an undo entry)
    #expect(editor.document.elements.map(\.id) == [b.id, c.id, a.id])

    editor.select(ids: [a.id, c.id])
    step(manager) { editor.sendBackward() }
    #expect(editor.document.elements.map(\.id) == [c.id, a.id, b.id])
    editor.sendBackward()  // both selected, already at the bottom: no-op
    #expect(editor.document.elements.map(\.id) == [c.id, a.id, b.id])

    manager.undo()
    #expect(editor.document.elements.map(\.id) == [b.id, c.id, a.id])
    #expect(manager.undoActionName == "Bring Forward")
  }

  // MARK: Tool

  @Test func toolShortcutsAreUniqueAndComplete() {
    let keys = Tool.allCases.map(\.shortcut)
    #expect(Set(keys).count == Tool.allCases.count)
    #expect(String(keys) == "vatmhruolspc")
    #expect(Tool.tool(forShortcut: "A") == .arrow)
    #expect(Tool.tool(forShortcut: "z") == nil)
  }

  @Test func toolDefaultStyles() {
    let size = CGSize(width: 800, height: 600)
    #expect(Tool.highlighter.defaultStyle(imageSize: size)?.color == .yellow)
    #expect(Tool.arrow.defaultStyle(imageSize: size)?.color == .red)
    #expect(Tool.select.defaultStyle(imageSize: size) == nil)
    #expect(Tool.crop.styleTool == nil)
    #expect(Tool.roundedRect.styleTool == .roundedRect)
  }
}
