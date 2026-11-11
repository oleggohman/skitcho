import CoreGraphics
import Foundation
import Observation

/// Editor state: the document, selection, current tool and undoable commands.
///
/// All mutations go through `perform` (one undo step) or the interactive trio
/// `beginInteractive` / `commitInteractive` / `cancelInteractive` (one undo step per gesture).
@MainActor @Observable
public final class EditorModel {
  public var document: Document
  public var undoManager: UndoManager?
  public var currentTool: Tool = .select
  /// Selected element IDs (z-order is always taken from `document.elements`).
  public private(set) var selection: Set<UUID> = []

  /// Snapshot taken by `beginInteractive`; nil when no gesture is running.
  private var interactiveStart: Document?

  public init(document: Document, undoManager: UndoManager?) {
    self.document = document
    self.undoManager = undoManager
  }

  // MARK: Undo

  /// Applies `change` as one undoable step named `name`. A change that leaves the document equal registers nothing.
  public func perform(_ name: String, _ change: (inout Document) -> Void) {
    let old = document
    var updated = old
    change(&updated)
    guard updated != old else { return }
    document = updated
    pruneSelection()
    registerUndo(restoring: old, name: name)
  }

  /// Replaces the document with `snapshot` and registers the inverse, so undo and redo alternate.
  public func restore(_ snapshot: Document, _ name: String) {
    let current = document
    document = snapshot
    pruneSelection()
    registerUndo(restoring: current, name: name)
  }

  private func registerUndo(restoring snapshot: Document, name: String) {
    guard let undoManager else { return }
    undoManager.registerUndo(withTarget: self) { $0.restore(snapshot, name) }
    // While undoing/redoing the manager keeps the name of the original action.
    if !undoManager.isUndoing && !undoManager.isRedoing { undoManager.setActionName(name) }
  }

  /// Starts a gesture: snapshots the document. Live updates then edit `document` directly without registering.
  public func beginInteractive() {
    if interactiveStart == nil { interactiveStart = document }
  }

  /// Ends the gesture and registers exactly one undo step (nothing when the document did not change).
  public func commitInteractive(name: String) {
    guard let start = interactiveStart else { return }
    interactiveStart = nil
    guard document != start else { return }
    registerUndo(restoring: start, name: name)
  }

  /// Ends the gesture and reverts to the snapshot without registering anything.
  public func cancelInteractive() {
    guard let start = interactiveStart else { return }
    interactiveStart = nil
    document = start
    pruneSelection()
  }

  public var isInteracting: Bool { interactiveStart != nil }

  // MARK: Selection

  public var selectedElements: [Element] { document.elements.filter { selection.contains($0.id) } }

  public func select(_ id: UUID) {
    selection = document.elements.contains { $0.id == id } ? [id] : []
  }

  public func select(ids: some Sequence<UUID>) {
    let known = Set(document.elements.map(\.id))
    selection = Set(ids).intersection(known)
  }

  public func toggleSelection(_ id: UUID) {
    if selection.contains(id) {
      selection.remove(id)
    } else if document.elements.contains(where: { $0.id == id }) {
      selection.insert(id)
    }
  }

  public func selectAll() { selection = Set(document.elements.map(\.id)) }

  public func deselect() { selection = [] }

  /// The top-most element hit at `point` (`tolerance` in document units), or nil.
  public func topMostHit(at point: CGPoint, tolerance: Double) -> Element? {
    document.elements.last { $0.hitTest(point: point, tolerance: tolerance) }
  }

  private func pruneSelection() {
    let known = Set(document.elements.map(\.id))
    if !selection.isSubset(of: known) { selection.formIntersection(known) }
  }

  // MARK: Element commands

  /// Appends `element` on top and selects it.
  public func add(_ element: Element, name: String = "Add Element") {
    perform(name) { $0.elements.append(element) }
    selection = [element.id]
  }

  /// Removes the elements with `ids` (unknown IDs are ignored; nothing to remove registers no undo step).
  public func remove(ids: Set<UUID>, name: String = "Delete") {
    perform(name) { $0.elements.removeAll { ids.contains($0.id) } }
  }

  public func removeSelection() { remove(ids: selection) }

  /// Moves the selection by `delta` as one undo step.
  public func moveSelection(by delta: CGPoint, name: String = "Move") {
    guard delta != .zero else { return }
    let ids = selection
    perform(name) { document in
      document.elements = document.elements.map { ids.contains($0.id) ? $0.translated(by: delta) : $0 }
    }
  }

  /// Nudges the selection by 1 document unit, or 10 with `large` (Shift).
  public func nudgeSelection(dx: Int, dy: Int, large: Bool = false) {
    let step = large ? 10.0 : 1.0
    moveSelection(by: CGPoint(x: Double(dx) * step, y: Double(dy) * step), name: "Nudge")
  }

  /// Moves each selected element one place up in z-order (past the nearest unselected neighbour).
  public func bringForward() {
    let ids = selection
    perform("Bring Forward") { document in
      var elements = document.elements
      for index in stride(from: elements.count - 2, through: 0, by: -1)
      where ids.contains(elements[index].id) && !ids.contains(elements[index + 1].id) {
        elements.swapAt(index, index + 1)
      }
      document.elements = elements
    }
  }

  /// Moves each selected element one place down in z-order.
  public func sendBackward() {
    let ids = selection
    perform("Send Backward") { document in
      var elements = document.elements
      for index in 1..<max(elements.count, 1)
      where ids.contains(elements[index].id) && !ids.contains(elements[index - 1].id) {
        elements.swapAt(index, index - 1)
      }
      document.elements = elements
    }
  }
}
