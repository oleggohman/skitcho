import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

/// Counts undo registrations, so a test can tell one step from several collapsed into one undo group.
final class CountingUndoManager: UndoManager {
  private(set) var registrations = 0

  override func __registerUndoWithTarget(_ target: Any, handler: @escaping @MainActor (Any) -> Void) {
    registrations += 1
    super.__registerUndoWithTarget(target, handler: handler)
  }
}

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
    let manager = CountingUndoManager()
    manager.groupsByEvent = false
    let editor = EditorModel(document: Document.blank(size: CGSize(width: 200, height: 100)), undoManager: manager)
    let element = rectElement()
    step(manager) { editor.add(element) }
    let original = editor.document

    // Live updates run outside any undo group: a registration there would raise, and the commit is counted.
    editor.beginInteractive()
    for _ in 0..<5 {
      editor.document.elements = editor.document.elements.map { $0.translated(by: CGPoint(x: 3, y: 0)) }
    }
    let before = manager.registrations
    step(manager) { editor.commitInteractive(name: "Move") }
    #expect(manager.registrations == before + 1)
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

  @Test func undoDuringGestureCancelsItAndKeepsHistoryIntact() {
    let manager = CountingUndoManager()
    manager.groupsByEvent = false
    let editor = EditorModel(document: Document.blank(size: CGSize(width: 200, height: 100)), undoManager: manager)
    let element = rectElement()
    step(manager) { editor.add(element) }

    // Cmd-Z while dragging: the gesture is dropped and the add is undone.
    editor.beginInteractive()
    editor.document.elements = editor.document.elements.map { $0.translated(by: CGPoint(x: 20, y: 0)) }
    manager.undo()
    #expect(editor.document.elements.isEmpty)
    #expect(!editor.isInteracting)
    #expect(!manager.canUndo)

    // Redo returns the committed element, not the half-dragged one.
    manager.redo()
    #expect(editor.document.elements == [element])

    // The late commit from the gesture's mouse-up registers nothing against the stale snapshot.
    let before = manager.registrations
    step(manager) { editor.commitInteractive(name: "Move") }
    #expect(manager.registrations == before)
    #expect(manager.undoActionName != "Move")
  }

  @Test func nonFiniteMoveIsIgnored() {
    let (editor, manager) = makeEditor()
    let element = rectElement()
    step(manager) { editor.add(element) }
    let before = editor.document
    for delta in [CGPoint(x: Double.nan, y: 0), CGPoint(x: 0, y: -Double.infinity)] {
      // No group: a registration here would raise, so this also proves nothing is registered.
      editor.moveSelection(by: delta)
      #expect(editor.document == before)
    }
    #expect(manager.undoActionName != "Move")
  }

  @Test func sizeStepKeepsRotatedTextAndStampsInPlace() {
    let (editor, manager) = makeEditor()
    let canvas = editor.document.canvasSize
    let textStyle = Style.make(tool: .text, sizeStep: .xs, imageSize: canvas)
    let text = Element(
      kind: .text(TextContent(string: "Rotated", origin: CGPoint(x: 40, y: 30))), style: textStyle,
      rotation: .pi / 2)
    let stamp = Element(
      kind: .stamp(.approve, center: CGPoint(x: 120, y: 50), tailAngle: 0.4, labelID: nil),
      style: Style.make(tool: .stamp, sizeStep: .xs, imageSize: canvas), rotation: .pi / 2)
    let plain = Element(kind: .text(TextContent(string: "Plain", origin: CGPoint(x: 10, y: 70))), style: textStyle)
    step(manager) { for element in [text, stamp, plain] { editor.add(element) } }

    /// Where the anchor (text origin, stamp center) is drawn once rotation is applied.
    func drawnAnchor(_ element: Element) -> CGPoint {
      let point: CGPoint
      switch element.kind {
      case .text(let content): point = content.origin
      case .stamp(_, let center, _, _): point = center
      default: fatalError("unexpected kind")
      }
      return GeometryMath.rotate(point, about: element.baseBounds.center, by: element.rotation)
    }
    let anchorsBefore = editor.document.elements.map(drawnAnchor)
    let boundsBefore = editor.document.elements.map(\.bounds)

    editor.selectAll()
    step(manager) { editor.applySizeStep(.xl) }
    let after = editor.document.elements
    // The sizes did change...
    for (old, new) in zip(boundsBefore, after.map(\.bounds)) { #expect(new.width > old.width) }
    // ...but every drawn anchor stayed put, and the unrotated text kept its origin.
    for (old, new) in zip(anchorsBefore, after.map(drawnAnchor)) {
      #expect(abs(old.x - new.x) < 1e-6 && abs(old.y - new.y) < 1e-6, "\(old) vs \(new)")
    }
    guard case .text(let content) = after[2].kind else { fatalError("expected text") }
    #expect(content.origin == CGPoint(x: 10, y: 70))
  }

  @Test func checkpointRegistersAStepAndContinuesTheGesture() {
    let (editor, manager) = makeEditor()
    let original = editor.document
    // No gesture, or a checkpoint equal to the start: nothing (no group is open, a registration would raise).
    #expect(!editor.checkpointInteractive(original, name: "Step"))
    editor.beginInteractive()
    #expect(!editor.checkpointInteractive(original, name: "Step"))
    editor.document.elements.append(rectElement(x: 10))
    let checkpoint = editor.document
    step(manager) { #expect(editor.checkpointInteractive(checkpoint, name: "Step")) }
    #expect(editor.isInteracting)
    #expect(editor.document == checkpoint)
    #expect(manager.undoActionName == "Step")

    // The gesture now starts at the checkpoint: cancel returns there, not to the original start.
    editor.document.elements.append(rectElement(x: 50))
    editor.cancelInteractive()
    #expect(editor.document == checkpoint)
    manager.undo()
    #expect(editor.document == original)
    #expect(!manager.canUndo)
    manager.redo()
    #expect(editor.document == checkpoint)
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
