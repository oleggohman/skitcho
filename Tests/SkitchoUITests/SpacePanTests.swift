import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct SpacePanTests {
  private func key(_ type: NSEvent.EventType) -> NSEvent {
    NSEvent.keyEvent(
      with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
      characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
  }

  private func mouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(
      with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
      eventNumber: 0, clickCount: 1, pressure: 1)!
  }

  @Test func spaceDragPansTheScrollViewInsteadOfDrawing() {
    let editor = EditorModel(document: Document.blank(size: CGSize(width: 400, height: 300)), undoManager: nil)
    editor.currentTool = .rect
    let (scrollView, canvas) = CanvasView.makeScrollView(editor: editor)
    scrollView.frame = CGRect(x: 0, y: 0, width: 200, height: 150)
    canvas.setZoom(3)
    scrollView.layoutSubtreeIfNeeded()
    scrollView.contentView.scroll(to: CGPoint(x: 100, y: 100))
    let before = scrollView.contentView.bounds.origin

    canvas.keyDown(with: key(.keyDown))
    canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 100)))
    canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 60, y: 80)))
    canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 60, y: 80)))
    canvas.keyUp(with: key(.keyUp))

    #expect(scrollView.contentView.bounds.origin != before)
    #expect(editor.document.elements.isEmpty)

    // After Space is released the same drag draws again.
    canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 100)))
    canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 160, y: 160)))
    canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 160, y: 160)))
    #expect(editor.document.elements.count == 1)
  }
}
