import CoreGraphics
import Foundation
import SkitchoCore
import SwiftUI
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct PanelTests {
  private func makeEditor(elements: [Element] = []) -> EditorModel {
    let manager = UndoManager()
    manager.groupsByEvent = false
    var document = Document.blank(size: CGSize(width: 400, height: 300))
    document.elements = elements
    return EditorModel(document: document, undoManager: manager)
  }

  /// Runs `body` inside an undo group (the manager has `groupsByEvent` off, so registering needs one).
  private func grouped(_ editor: EditorModel, _ body: () -> Void) {
    editor.undoManager?.beginUndoGrouping()
    body()
    editor.undoManager?.endUndoGrouping()
  }

  private func element(_ kind: ElementKind, tool: StyleTool) -> Element {
    Element(kind: kind, style: Style.make(tool: tool, imageSize: CGSize(width: 400, height: 300)))
  }

  private func arrow(double: Bool = false) -> Element {
    element(.arrow(start: .zero, end: CGPoint(x: 50, y: 50), doubleHeaded: double), tool: .arrow)
  }

  private func text(styled: Bool = true) -> Element {
    element(.text(TextContent(string: "hi", origin: .zero, styled: styled)), tool: .text)
  }

  private func stamp(label: UUID? = nil) -> Element {
    element(.stamp(.approve, center: CGPoint(x: 40, y: 40), tailAngle: nil, labelID: label), tool: .stamp)
  }

  // MARK: Palette

  @Test func everyToolIsReachableFromThePalette() {
    let covered = Set(PaletteItem.allCases.flatMap(\.tools))
    #expect(covered == Set(Tool.allCases))
  }

  @Test func tappingAPlainItemSetsTheCurrentTool() {
    let editor = makeEditor()
    let palette = ToolPaletteModel(editor: editor)
    for item in [PaletteItem.arrow, .text, .marker, .highlighter, .pixelate, .crop, .select] {
      #expect(!palette.tap(item))
      #expect(editor.currentTool == item.tools[0])
      #expect(palette.isSelected(item))
    }
  }

  @Test func shapesRememberTheLastChoiceAndOpenThePopoverOnSecondTap() {
    let editor = makeEditor()
    let palette = ToolPaletteModel(editor: editor)
    #expect(!palette.tap(.shapes))
    #expect(editor.currentTool == .rect)
    #expect(palette.tap(.shapes))  // already active: the caller shows the popover
    palette.select(.ellipse)
    #expect(editor.currentTool == .ellipse)
    #expect(palette.lastShape == .ellipse)
    #expect(palette.symbolName(for: .shapes) == Tool.ellipse.symbolName)
    palette.select(.crop)
    #expect(!palette.isSelected(.shapes))
    #expect(!palette.tap(.shapes))
    #expect(editor.currentTool == .ellipse)
  }

  @Test func stampPopoverSetsTheKindAndTheTool() {
    let editor = makeEditor()
    let palette = ToolPaletteModel(editor: editor)
    #expect(!palette.tap(.stamp))
    #expect(editor.currentTool == .stamp)
    #expect(palette.tap(.stamp))
    palette.selectStamp(.perfect)
    #expect(editor.nextStampKind == .perfect)
    #expect(palette.currentStampKind == .perfect)
    editor.currentTool = .select
    palette.selectStamp(.reject)
    #expect(editor.currentTool == .stamp)
    #expect(editor.nextStampKind == .reject)
  }

  @Test func everyItemHasAHelpTooltipWithItsShortcut() {
    let palette = ToolPaletteModel(editor: makeEditor())
    for item in palette.items {
      let help = palette.help(for: item)
      #expect(help.contains(item.title))
      #expect(help.contains("(\(String(palette.tool(for: item).shortcut).uppercased()))"))
    }
  }

  // MARK: Properties: commands

  @Test func swatchSizeAndTogglesSetTheNextStyleWithoutSelection() {
    let editor = makeEditor()
    editor.currentTool = .arrow
    let panel = PropertiesModel(editor: editor)
    panel.setColor(.green)
    panel.setSize(.xl)
    panel.toggleDoubleHead()
    #expect(editor.nextColor == .green)
    #expect(editor.nextSizeStep == .xl)
    #expect(editor.nextDoubleHeaded)
    #expect(panel.currentColor == .green)
    #expect(panel.currentSizeStep == .xl)
    #expect(panel.isDoubleHeaded)
    editor.currentTool = .text
    panel.toggleTextStyle()
    #expect(!editor.nextTextStyled)
    #expect(!panel.isTextStyled)
  }

  @Test func commandsApplyToTheSelectionAsUndoSteps() {
    let target = arrow()
    let editor = makeEditor(elements: [target])
    editor.select(target.id)
    let panel = PropertiesModel(editor: editor)
    grouped(editor) { panel.setColor(.purple) }
    grouped(editor) { panel.setSize(.small) }
    grouped(editor) { panel.toggleDoubleHead() }
    #expect(editor.undoManager?.canUndo == true)
    let updated = editor.document.elements[0]
    #expect(updated.style.color == .purple)
    #expect(updated.style.sizeStep == .small)
    if case .arrow(_, _, let double) = updated.kind { #expect(double) } else { Issue.record("not an arrow") }
    #expect(panel.currentColor == .purple && panel.currentSizeStep == .small && panel.isDoubleHeaded)
    #expect(editor.nextColor == nil)  // the selection took the change, not the next-element default
    #expect(editor.nextSizeStep == .default)
  }

  @Test func textToggleFlipsTheSelectedText() {
    let target = text(styled: true)
    let editor = makeEditor(elements: [target])
    editor.select(target.id)
    let panel = PropertiesModel(editor: editor)
    #expect(panel.isTextStyled)
    grouped(editor) { panel.toggleTextStyle() }
    #expect(!panel.isTextStyled)
    if case .text(let content) = editor.document.elements[0].kind {
      #expect(!content.styled)
    } else {
      Issue.record("not text")
    }
  }

  @Test func customColorIsStoredAsACustomAnnotationColor() {
    let editor = makeEditor()
    editor.currentTool = .rect
    let panel = PropertiesModel(editor: editor)
    panel.setCustomColor(Color(.sRGB, red: 0.25, green: 0.5, blue: 0.75, opacity: 1))
    guard case .custom(let rgba) = editor.nextColor else {
      Issue.record("expected a custom color")
      return
    }
    #expect(abs(rgba.red - 0.25) < 0.01 && abs(rgba.green - 0.5) < 0.01 && abs(rgba.blue - 0.75) < 0.01)
  }

  // MARK: Properties: visibility

  @Test func visibleControlsFollowTheToolAndSelection() {
    let editor = makeEditor(elements: [arrow(), text(), stamp()])
    let panel = PropertiesModel(editor: editor)
    #expect(!panel.showsStyle)  // select tool, nothing selected
    editor.currentTool = .crop
    #expect(!panel.showsStyle)
    editor.currentTool = .rect
    #expect(panel.showsStyle && !panel.showsTextStyle && !panel.showsDoubleHead)
    editor.currentTool = .arrow
    #expect(panel.showsDoubleHead && !panel.showsTextStyle)
    editor.currentTool = .text
    #expect(panel.showsTextStyle && !panel.showsDoubleHead)
    editor.currentTool = .select
    editor.select(editor.document.elements[0].id)
    #expect(panel.showsStyle && panel.showsDoubleHead && !panel.showsTextStyle)
    editor.select(editor.document.elements[1].id)
    #expect(panel.showsTextStyle && !panel.showsDoubleHead)
    editor.selectAll()
    #expect(panel.showsTextStyle && panel.showsDoubleHead)
  }

  // MARK: Properties: attach label

  @Test func attachLabelIsOfferedForASingleUnlabeledStampOnly() {
    let plain = stamp()
    let labeled = stamp(label: UUID())
    let other = arrow()
    let editor = makeEditor(elements: [plain, labeled, other])
    var requested: [UUID] = []
    let panel = PropertiesModel(
      editor: editor,
      attachLabel: {
        requested.append($0)
        return true
      })
    #expect(!panel.canAttachLabel)
    #expect(!panel.attachLabel())
    editor.select(plain.id)
    #expect(panel.canAttachLabel)
    editor.select(labeled.id)
    #expect(!panel.canAttachLabel)
    editor.select(other.id)
    #expect(!panel.canAttachLabel)
    editor.select(ids: [plain.id, labeled.id])
    #expect(!panel.canAttachLabel)
    #expect(requested.isEmpty)
    editor.select(plain.id)
    #expect(panel.attachLabel())
    #expect(requested == [plain.id])
  }

  @Test func attachLabelReachesTheStampToolOnARealCanvas() {
    let target = stamp()
    let editor = makeEditor(elements: [target])
    editor.select(target.id)
    let (_, canvas) = CanvasView.makeScrollView(editor: editor)
    let panel = PropertiesModel(editor: editor, attachLabel: { canvas.attachLabel(to: $0) })
    grouped(editor) { #expect(panel.attachLabel()) }
    #expect(editor.currentTool == .text)
    #expect(editor.document.elements.count == 2)  // the empty label exists while it is edited
    if case .stamp(_, _, _, let label) = editor.document.elements[0].kind {
      #expect(label != nil)
    } else {
      Issue.record("not a stamp")
    }
  }
}
