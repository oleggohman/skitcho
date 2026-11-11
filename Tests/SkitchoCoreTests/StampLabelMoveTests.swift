import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

/// A stamp's linked label (the text element behind `labelID`) moves together with the stamp.
@MainActor
@Suite struct StampLabelMoveTests {
  private func makeEditor() -> (EditorModel, CountingUndoManager, stamp: Element, label: Element) {
    let manager = CountingUndoManager()
    manager.groupsByEvent = false
    let label = Element(
      kind: .text(TextContent(string: "note", origin: CGPoint(x: 60, y: 20), styled: true)), style: testStyle(.red))
    let stamp = Element(
      kind: .stamp(.approve, center: CGPoint(x: 30, y: 30), tailAngle: nil, labelID: label.id),
      style: testStyle(.red))
    var document = Document.blank(size: CGSize(width: 200, height: 100))
    document.elements = [stamp, label]
    return (EditorModel(document: document, undoManager: manager), manager, stamp, label)
  }

  private func origin(_ editor: EditorModel, _ id: UUID) -> CGPoint? {
    guard let element = editor.document.elements.first(where: { $0.id == id }),
      case .text(let content) = element.kind
    else { return nil }
    return content.origin
  }

  private func center(_ editor: EditorModel, _ id: UUID) -> CGPoint? {
    guard let element = editor.document.elements.first(where: { $0.id == id }),
      case .stamp(_, let center, _, _) = element.kind
    else { return nil }
    return center
  }

  @Test func moveCarriesTheLabelInOneUndoStep() {
    let (editor, manager, stamp, label) = makeEditor()
    editor.select(stamp.id)
    manager.beginUndoGrouping()
    editor.moveSelection(by: CGPoint(x: 10, y: 5))
    manager.endUndoGrouping()
    // One registration: the group would hide a second one for the label.
    #expect(manager.registrations == 1)
    #expect(center(editor, stamp.id) == CGPoint(x: 40, y: 35))
    #expect(origin(editor, label.id) == CGPoint(x: 70, y: 25))
    manager.undo()
    #expect(center(editor, stamp.id) == CGPoint(x: 30, y: 30))
    #expect(origin(editor, label.id) == CGPoint(x: 60, y: 20))
    #expect(!manager.canUndo)
  }

  @Test func nudgeCarriesTheLabel() {
    let (editor, manager, stamp, label) = makeEditor()
    editor.select(stamp.id)
    manager.beginUndoGrouping()
    editor.nudgeSelection(dx: 1, dy: 0, large: true)
    manager.endUndoGrouping()
    #expect(manager.registrations == 1)
    #expect(center(editor, stamp.id) == CGPoint(x: 40, y: 30))
    #expect(origin(editor, label.id) == CGPoint(x: 70, y: 20))
    manager.undo()
    #expect(origin(editor, label.id) == CGPoint(x: 60, y: 20))
    #expect(!manager.canUndo)
  }

  @Test func labelAlsoSelectedMovesOnce() {
    let (editor, manager, stamp, label) = makeEditor()
    editor.select(ids: [stamp.id, label.id])
    manager.beginUndoGrouping()
    editor.moveSelection(by: CGPoint(x: 10, y: 0))
    manager.endUndoGrouping()
    #expect(center(editor, stamp.id) == CGPoint(x: 40, y: 30))
    #expect(origin(editor, label.id) == CGPoint(x: 70, y: 20))
  }

  @Test func movingTheLabelAloneDoesNotMoveTheStamp() {
    let (editor, manager, stamp, label) = makeEditor()
    editor.select(label.id)
    manager.beginUndoGrouping()
    editor.moveSelection(by: CGPoint(x: 10, y: 0))
    manager.endUndoGrouping()
    #expect(center(editor, stamp.id) == CGPoint(x: 30, y: 30))
    #expect(origin(editor, label.id) == CGPoint(x: 70, y: 20))
  }

  @Test func copyingAStampCarriesItsLabelAndTheLink() throws {
    let (editor, manager, stamp, _) = makeEditor()
    editor.select(stamp.id)
    let data = try #require(editor.copySelectionData())
    manager.beginUndoGrouping()
    #expect(editor.paste(data))
    manager.endUndoGrouping()
    #expect(editor.document.elements.count == 4)
    let pasted = editor.document.elements.suffix(2)
    let pastedStamp = try #require(pasted.first { if case .stamp = $0.kind { true } else { false } })
    guard case .stamp(_, _, _, let link?) = pastedStamp.kind else {
      Issue.record("pasted stamp lost its label link")
      return
    }
    #expect(pasted.contains { $0.id == link })
    #expect(!editor.document.elements.prefix(2).contains { $0.id == link })
  }

  @Test func deletingAStampDeletesItsLabelInOneUndoStep() {
    let (editor, manager, stamp, label) = makeEditor()
    editor.select(stamp.id)
    manager.beginUndoGrouping()
    editor.removeSelection()
    manager.endUndoGrouping()
    #expect(manager.registrations == 1)
    #expect(editor.document.elements.isEmpty)
    manager.undo()
    #expect(editor.document.elements.map(\.id) == [stamp.id, label.id])
  }

  @Test func deletingTheLabelAloneKeepsTheStamp() {
    let (editor, manager, stamp, label) = makeEditor()
    editor.select(label.id)
    manager.beginUndoGrouping()
    editor.removeSelection()
    manager.endUndoGrouping()
    #expect(editor.document.elements.map(\.id) == [stamp.id])
  }

  @Test func movingElementsIncludeTheLinkedLabelOnce() {
    let (editor, _, stamp, label) = makeEditor()
    editor.select(stamp.id)
    #expect(Set(editor.movingElements.map(\.id)) == [stamp.id, label.id])
    editor.select(ids: [stamp.id, label.id])
    #expect(editor.movingElements.count == 2)
  }
}
