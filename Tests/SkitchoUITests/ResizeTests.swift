import CoreGraphics
import Foundation
import SkitchoCore
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct ResizeTests {
  private func makeEditor() -> (EditorModel, UndoManager) {
    let manager = UndoManager()
    manager.groupsByEvent = false
    let document = Document.blank(size: CGSize(width: 200, height: 100))
    return (EditorModel(document: document, undoManager: manager), manager)
  }

  private func step(_ manager: UndoManager, _ body: () -> Void) {
    manager.beginUndoGrouping()
    defer { manager.endUndoGrouping() }
    body()
  }

  // MARK: Fields

  @Test func startsAtTheCurrentSizeAndCannotApply() {
    let (editor, _) = makeEditor()
    let model = ResizeModel(editor: editor)
    #expect(model.width == 200 && model.height == 100)
    #expect(model.scale == 1)
    #expect(model.isProportionLinked)
    #expect(!model.canApply)
    #expect(model.message == nil)
  }

  @Test func linkedWidthEditKeepsTheAspectRatio() {
    let (editor, _) = makeEditor()
    let model = ResizeModel(editor: editor)
    model.setWidth(100)
    #expect(model.width == 100 && model.height == 50)
    model.setHeight(25)
    #expect(model.width == 50 && model.height == 25)
  }

  @Test func scaleSliderMovesBothAxes() {
    let (editor, _) = makeEditor()
    let model = ResizeModel(editor: editor)
    model.setScale(0.5)
    #expect(model.width == 100 && model.height == 50)
    model.isProportionLinked = false
    model.setScale(2)
    #expect(model.width == 400 && model.height == 200)
  }

  @Test func unlinkedEditsChangeOnlyOneAxis() {
    let (editor, _) = makeEditor()
    let model = ResizeModel(editor: editor)
    model.isProportionLinked = false
    model.setWidth(120)
    #expect(model.width == 120 && model.height == 100)
    model.setHeight(30)
    #expect(model.width == 120 && model.height == 30)
    // A non-uniform size cannot be applied and says why.
    #expect(!model.isUniform && !model.canApply)
    #expect(model.message != nil)
    // Relinking is not enough by itself; the next edit restores the ratio.
    model.isProportionLinked = true
    model.setWidth(120)
    #expect(model.height == 60 && model.canApply)
  }

  @Test func nonPositiveValuesClampToOne() {
    let (editor, _) = makeEditor()
    let model = ResizeModel(editor: editor)
    model.setWidth(-5)
    #expect(model.width == 1 && model.height >= 1)
    model.setScale(0)  // ignored
    #expect(model.width == 1)
  }

  // MARK: Size guard

  @Test func oversizeTargetSurfacesAnErrorAndBlocksApply() {
    let (editor, manager) = makeEditor()
    let model = ResizeModel(editor: editor)
    model.setWidth(ImageOps.maxSide + 1)
    #expect(model.sizeError != nil)
    #expect(model.message == model.sizeError)
    #expect(!model.canApply)
    #expect(!model.apply())
    #expect(editor.document.canvasSize == CGSize(width: 200, height: 100))
    #expect(!manager.canUndo)
    model.setWidth(ImageOps.maxSide)
    #expect(model.sizeError == nil && model.canApply)
  }

  // MARK: Apply / cancel

  @Test func applyResizesAsOneUndoStepAndDismisses() {
    let (editor, manager) = makeEditor()
    let model = ResizeModel(editor: editor)
    var dismissed = 0
    model.onDismiss = { dismissed += 1 }
    model.setWidth(100)
    var applied = false
    step(manager) { applied = model.apply() }
    #expect(applied)
    #expect(dismissed == 1)
    #expect(editor.document.canvasSize == CGSize(width: 100, height: 50))
    #expect(manager.undoActionName == "Resize Image")
    // The panel rebased on the new size.
    #expect(model.originalWidth == 100 && model.width == 100 && !model.canApply)
    manager.undo()
    #expect(editor.document.canvasSize == CGSize(width: 200, height: 100))
    #expect(!manager.canUndo)
  }

  @Test func cancelDiscardsThePendingSize() {
    let (editor, manager) = makeEditor()
    let model = ResizeModel(editor: editor)
    var dismissed = 0
    model.onDismiss = { dismissed += 1 }
    model.setWidth(50)
    model.cancel()
    #expect(model.width == 200 && model.height == 100)
    #expect(dismissed == 1)
    #expect(!manager.canUndo)
  }

  // MARK: Rotate / flip

  @Test func rotateAndFlipAreUndoableCommands() {
    let (editor, manager) = makeEditor()
    let model = ResizeModel(editor: editor)
    step(manager) { model.rotate(clockwise: true) }
    #expect(editor.document.canvasSize == CGSize(width: 100, height: 200))
    #expect(model.width == 100 && model.height == 200)
    #expect(manager.undoActionName == "Rotate")
    step(manager) { model.rotate(clockwise: false) }
    #expect(editor.document.canvasSize == CGSize(width: 200, height: 100))
    step(manager) { model.flip(.horizontal) }
    #expect(manager.undoActionName == "Flip")
    step(manager) { model.flip(.vertical) }
    #expect(editor.document.canvasSize == CGSize(width: 200, height: 100))
    manager.undo()
    #expect(manager.undoActionName == "Flip")
  }
}
