import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

@MainActor
@Suite struct EditorCommandTests {
  private func makeEditor(size: CGSize = CGSize(width: 200, height: 100)) -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    manager.groupsByEvent = false
    return (EditorModel(document: Document.blank(size: size), undoManager: manager), manager)
  }

  private func step(_ manager: UndoManager, _ body: () throws -> Void) rethrows {
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    try body()
  }

  private func rect(x: Double = 10, color: AnnotationColor = .red) -> Element {
    Element(kind: .rect(CGRect(x: x, y: 10, width: 30, height: 20), rounded: false), style: testStyle(color))
  }

  private func text(styled: Bool = true) -> Element {
    Element(
      kind: .text(TextContent(string: "hi", origin: CGPoint(x: 5, y: 5), styled: styled)), style: testStyle(.red))
  }

  private func arrow(double: Bool = false) -> Element {
    Element(
      kind: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 80, y: 0), doubleHeaded: double),
      style: testStyle(.red))
  }

  // MARK: Style targeting

  @Test func colorWithoutSelectionSetsNextElementStyle() {
    let (editor, manager) = makeEditor()
    step(manager) { editor.add(rect()) }
    editor.deselect()
    step(manager) { editor.applyColor(.blue) }
    #expect(editor.document.elements[0].style.color == .red)
    #expect(editor.nextStyle(for: .rect)?.color == .blue)
    #expect(editor.nextStyle(for: .select) == nil)
  }

  @Test func colorWithSelectionChangesOnlySelectionAndUndoes() {
    let (editor, manager) = makeEditor()
    let a = rect(x: 10)
    let b = rect(x: 60)
    step(manager) { editor.add(a) }
    step(manager) { editor.add(b) }
    editor.select(a.id)
    step(manager) { editor.applyColor(.navy) }
    #expect(editor.document.elements[0].style.color == .navy)
    #expect(editor.document.elements[1].style.color == .red)
    #expect(editor.nextColor == nil)
    manager.undo()
    #expect(editor.document.elements[0].style.color == .red)
  }

  @Test func sizeStepRecomputesFrozenSizesFromCurrentCanvas() {
    let (editor, manager) = makeEditor(size: CGSize(width: 2000, height: 2000))
    step(manager) { editor.add(rect()) }
    step(manager) { editor.applySizeStep(.xl) }
    let style = editor.document.elements[0].style
    #expect(style.sizeStep == .xl)
    // relative 1.0 * base 10 * image scale 2
    #expect(style.strokeWidth == 20)
    #expect(style.fontSize == 96)
    #expect(style.color == .red)
  }

  @Test func sizeStepUsesHighlighterBaseForHighlighterFreehand() {
    let (editor, manager) = makeEditor()
    let segment = BezierSegment(CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 15, y: 0))
    let freehand = Element(kind: .freehand(segments: [segment], highlighter: true), style: testStyle(.yellow))
    step(manager) { editor.add(freehand) }
    step(manager) { editor.applySizeStep(.xl) }
    #expect(editor.document.elements[0].style.strokeWidth == 28)
  }

  @Test func sizeStepWithoutSelectionSetsNextSize() {
    let (editor, _) = makeEditor()
    editor.applySizeStep(.large)
    #expect(editor.nextSizeStep == .large)
    #expect(editor.nextStyle(for: .rect)?.strokeWidth == 0.8 * 10)
  }

  @Test func toggleTextStyleTargetsSelectedTextOrNext() {
    let (editor, manager) = makeEditor()
    step(manager) { editor.add(text(styled: true)) }
    step(manager) { editor.toggleTextStyle() }
    guard case .text(let content) = editor.document.elements[0].kind else {
      Issue.record("expected text")
      return
    }
    #expect(!content.styled)
    #expect(editor.nextTextStyled)
    editor.deselect()
    editor.toggleTextStyle()
    #expect(!editor.nextTextStyled)
  }

  @Test func toggleTextStyleIgnoresSelectionWithoutText() {
    let (editor, manager) = makeEditor()
    step(manager) { editor.add(rect()) }
    let before = editor.document
    editor.toggleTextStyle()
    #expect(editor.document == before)
    #expect(editor.nextTextStyled)
  }

  @Test func toggleDoubleHeadTargetsSelectedArrowOrNext() {
    let (editor, manager) = makeEditor()
    step(manager) { editor.add(arrow()) }
    step(manager) { editor.toggleDoubleHead() }
    guard case .arrow(_, _, let double) = editor.document.elements[0].kind else {
      Issue.record("expected arrow")
      return
    }
    #expect(double)
    manager.undo()
    guard case .arrow(_, _, let undone) = editor.document.elements[0].kind else {
      Issue.record("expected arrow")
      return
    }
    #expect(!undone)
    editor.deselect()
    editor.toggleDoubleHead()
    #expect(editor.nextDoubleHeaded)
  }

  // MARK: Clipboard

  @Test func clipboardRoundTrip() throws {
    let elements = [rect(), text(), arrow()]
    let data = try #require(ElementClipboard.encode(elements))
    #expect(ElementClipboard.decode(data) == elements)
    #expect(ElementClipboard.encode([]) == nil)
  }

  @Test func pasteInsertsCopiesWithNewIDsOffsetAndSelects() throws {
    let (editor, manager) = makeEditor()
    let original = rect(x: 10)
    step(manager) { editor.add(original) }
    let data = try #require(editor.copySelectionData())
    step(manager) { #expect(editor.paste(data)) }
    #expect(editor.document.elements.count == 2)
    let pasted = editor.document.elements[1]
    #expect(pasted.id != original.id)
    #expect(pasted.kind == original.translated(by: CGPoint(x: 10, y: 10)).kind)
    #expect(editor.selection == [pasted.id])
    #expect(manager.undoActionName == "Paste")
    manager.undo()
    #expect(editor.document.elements.count == 1)
  }

  @Test func pasteTwiceGivesDistinctIDs() throws {
    let (editor, manager) = makeEditor()
    let data = try #require(ElementClipboard.encode([rect()]))
    step(manager) { editor.paste(data) }
    step(manager) { editor.paste(data) }
    #expect(Set(editor.document.elements.map(\.id)).count == 2)
  }

  @Test func pasteRemapsStampLabelLinks() throws {
    let (editor, manager) = makeEditor()
    let label = text()
    let stamp = Element(
      kind: .stamp(.approve, center: CGPoint(x: 50, y: 50), tailAngle: nil, labelID: label.id),
      style: testStyle(.green))
    let data = try #require(ElementClipboard.encode([stamp, label]))
    step(manager) { editor.paste(data) }
    let pastedLabel = editor.document.elements[1]
    guard case .stamp(_, _, _, let labelID) = editor.document.elements[0].kind else {
      Issue.record("expected stamp")
      return
    }
    #expect(labelID == pastedLabel.id)
    #expect(labelID != label.id)
  }

  @Test func invalidClipboardDataIsIgnored() {
    let (editor, manager) = makeEditor()
    let before = editor.document
    step(manager) {
      #expect(!editor.paste(Data("not json".utf8)))
      #expect(!editor.paste(Data()))
      #expect(!editor.paste(Data("{\"version\":1,\"elements\":[]}".utf8)))
      #expect(!editor.paste(Data("{\"version\":99,\"elements\":[]}".utf8)))
    }
    #expect(editor.document == before)
    #expect(editor.selection.isEmpty)
  }

  @Test func copyWithoutSelectionReturnsNil() {
    let (editor, _) = makeEditor()
    #expect(editor.copySelectionData() == nil)
  }

  // MARK: Image operations

  @Test func eachImageOpIsUndoableWithName() throws {
    let (editor, manager) = makeEditor()
    let original = editor.document
    let cases: [(String, () throws -> Void)] = [
      ("Crop Image", { try editor.crop(to: CGRect(x: 0, y: 0, width: 100, height: 50)) }),
      ("Resize Image", { try editor.resize(scale: 0.5) }),
      ("Pixelate", { try editor.pixelate(rect: CGRect(x: 0, y: 0, width: 40, height: 40), blockSize: 8) }),
      ("Rotate", { try editor.rotate90(clockwise: true) }),
      ("Flip", { try editor.flip(axis: .horizontal) }),
      ("Expand Canvas", { try editor.expandCanvas(edge: .right, amount: 20) }),
    ]
    for (name, command) in cases {
      let before = editor.document
      try step(manager) { try command() }
      #expect(manager.undoActionName == name)
      #expect(editor.document != before, "\(name) changed the document")
      manager.undo()
      #expect(editor.document == before, "\(name) undone")
      manager.redo()
      #expect(editor.document != before, "\(name) redone")
      manager.undo()
    }
    #expect(editor.document == original)
  }

  @Test func cropKeepsElementsAndSelection() throws {
    let (editor, manager) = makeEditor()
    let element = rect(x: 50)
    step(manager) { editor.add(element) }
    try step(manager) { try editor.crop(to: CGRect(x: 20, y: 0, width: 100, height: 100)) }
    #expect(editor.document.canvasSize == CGSize(width: 100, height: 100))
    #expect(editor.document.elements.map(\.id) == [element.id])
    #expect(editor.selection == [element.id])
  }

  @Test func failingImageOpLeavesDocumentAndUndoStackAlone() {
    let (editor, manager) = makeEditor()
    // No undo group is opened: a failing op must not register anything (an empty group would count).
    let before = editor.document
    #expect(throws: ImageOpError.invalidRect) {
      try editor.crop(to: CGRect(x: 500, y: 500, width: 10, height: 10))
    }
    #expect(throws: ImageOpError.tooLarge) {
      try editor.resize(scale: 1000)
    }
    #expect(throws: ImageOpError.invalidArgument) {
      try editor.pixelate(rect: CGRect(x: 0, y: 0, width: 10, height: 10), blockSize: 0)
    }
    #expect(editor.document == before)
    #expect(!manager.canUndo)
  }
}
