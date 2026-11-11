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

  /// Style choices for the next element drawn when nothing is selected (nil color = the tool's default).
  public var nextColor: AnnotationColor?
  public var nextSizeStep: SizeStep = .default
  public var nextTextStyled = true
  public var nextDoubleHeaded = false
  /// The stamp the stamp tool places next.
  public var nextStampKind: StampKind = .approve

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

  /// The IDs that move with `ids`: the elements themselves plus the linked label of every stamp among them.
  /// A set, so a label that is also selected is counted once.
  public func moveTargets(of ids: Set<UUID>) -> Set<UUID> {
    var targets = ids
    for element in document.elements where ids.contains(element.id) {
      if case .stamp(_, _, _, let label?) = element.kind { targets.insert(label) }
    }
    return targets.intersection(document.elements.map(\.id))
  }

  /// The selected elements plus the linked labels of selected stamps (what a move gesture must translate).
  public var movingElements: [Element] {
    let ids = moveTargets(of: selection)
    return document.elements.filter { ids.contains($0.id) }
  }

  /// Moves the selection (and the linked labels of selected stamps) by `delta` as one undo step.
  public func moveSelection(by delta: CGPoint, name: String = "Move") {
    guard delta != .zero else { return }
    let ids = moveTargets(of: selection)
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

  // MARK: Style targeting

  /// The style a new element drawn with `tool` gets, from the next-element choices and the current canvas.
  public func nextStyle(for tool: Tool) -> Style? {
    tool.defaultStyle(sizeStep: nextSizeStep, color: nextColor, imageSize: document.canvasSize)
  }

  /// Applies `color` to the selection, or to the next element when nothing is selected.
  public func applyColor(_ color: AnnotationColor) {
    guard !selection.isEmpty else {
      nextColor = color
      return
    }
    updateSelection("Change Color") { $0.style.color = color }
  }

  /// Applies `color` as a live preview inside a `beginInteractive` / `commitInteractive` gesture: the document
  /// changes without registering undo, so a continuous change (color picker drag) becomes one undo step.
  public func applyColorLive(_ color: AnnotationColor) {
    guard !selection.isEmpty else {
      nextColor = color
      return
    }
    let ids = selection
    for index in document.elements.indices where ids.contains(document.elements[index].id) {
      document.elements[index].style.color = color
    }
  }

  /// Applies `step` to the selection (recomputing frozen sizes from the current canvas), else to the next element.
  public func applySizeStep(_ step: SizeStep) {
    guard !selection.isEmpty else {
      nextSizeStep = step
      return
    }
    let canvas = document.canvasSize
    updateSelection("Change Size") { element in
      let fresh = Style.make(
        tool: EditorModel.styleTool(of: element), sizeStep: step, color: element.style.color, imageSize: canvas)
      element.style = fresh
    }
  }

  /// Toggles the styled ("bubble") outline of the selected text elements, else of the next text element.
  public func toggleTextStyle() {
    guard !selection.isEmpty else {
      nextTextStyled.toggle()
      return
    }
    let texts = selectedElements.compactMap { element -> Bool? in
      if case .text(let content) = element.kind { return content.styled }
      return nil
    }
    guard !texts.isEmpty else { return }
    let target = !texts.allSatisfy { $0 }
    updateSelection("Change Text Style") { element in
      if case .text(var content) = element.kind {
        content.styled = target
        element.kind = .text(content)
      }
    }
  }

  /// Toggles the second arrow head of the selected arrows, else of the next arrow.
  public func toggleDoubleHead() {
    guard !selection.isEmpty else {
      nextDoubleHeaded.toggle()
      return
    }
    let heads = selectedElements.compactMap { element -> Bool? in
      if case .arrow(_, _, let double) = element.kind { return double }
      return nil
    }
    guard !heads.isEmpty else { return }
    let target = !heads.allSatisfy { $0 }
    updateSelection("Toggle Double Head") { element in
      if case .arrow(let start, let end, _) = element.kind {
        element.kind = .arrow(start: start, end: end, doubleHeaded: target)
      }
    }
  }

  private func updateSelection(_ name: String, _ change: @escaping (inout Element) -> Void) {
    let ids = selection
    perform(name) { document in
      for index in document.elements.indices where ids.contains(document.elements[index].id) {
        change(&document.elements[index])
      }
    }
  }

  /// The style family used to recompute an element's frozen sizes.
  public static func styleTool(of element: Element) -> StyleTool {
    switch element.kind {
    case .arrow: .arrow
    case .line: .line
    case .rect(_, let rounded): rounded ? .roundedRect : .rect
    case .ellipse: .ellipse
    case .freehand(_, let highlighter): highlighter ? .highlighter : .marker
    case .text: .text
    case .stamp: .stamp
    }
  }

  // MARK: Element clipboard

  /// Encoded copy of the selection, or nil when nothing is selected.
  public func copySelectionData() -> Data? { ElementClipboard.encode(selectedElements) }

  /// Pastes elements decoded from `data` (new IDs, offset +10) on top and selects them.
  /// Returns false and changes nothing when the data is not valid clipboard content.
  @discardableResult
  public func paste(_ data: Data) -> Bool {
    guard let decoded = ElementClipboard.decode(data) else { return false }
    let copies = ElementClipboard.duplicated(decoded, offset: ElementClipboard.pasteOffset)
    perform("Paste") { $0.elements.append(contentsOf: copies) }
    selection = Set(copies.map(\.id))
    return true
  }

  // MARK: Image operations

  /// Runs `operation` on the document; on success it becomes one undo step named `name`. Errors leave
  /// the document untouched.
  private func performImageOp(_ name: String, _ operation: (Document) throws -> Document) throws {
    let result = try operation(document)
    perform(name) { $0 = result }
  }

  public func crop(to rect: CGRect) throws {
    try performImageOp("Crop Image") { try ImageOps.crop($0, rect: rect) }
  }

  public func resize(scale: Double) throws {
    try performImageOp("Resize Image") { try ImageOps.resize($0, scale: scale) }
  }

  public func pixelate(rect: CGRect, blockSize: Int) throws {
    try performImageOp("Pixelate") { try ImageOps.pixelate($0, rect: rect, blockSize: blockSize) }
  }

  public func rotate90(clockwise: Bool) throws {
    try performImageOp("Rotate") { try ImageOps.rotate90($0, clockwise: clockwise) }
  }

  public func flip(axis: FlipAxis) throws {
    try performImageOp("Flip") { try ImageOps.flip($0, axis: axis) }
  }

  public func expandCanvas(edge: CanvasEdge, amount: Int) throws {
    try performImageOp("Expand Canvas") { try ImageOps.expandCanvas($0, edge: edge, amount: amount) }
  }
}
