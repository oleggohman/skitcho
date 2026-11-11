import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import SwiftUI
import Testing

import struct SkitchoCore.Document

@testable import SkitchoUI

@MainActor
@Suite struct CommandsTests {
  private let size = CGSize(width: 400, height: 300)

  private func makeEditor(elements: [Element] = []) -> EditorModel {
    let manager = UndoManager()
    manager.groupsByEvent = false
    var document = Document.blank(size: size)
    document.elements = elements
    return EditorModel(document: document, undoManager: manager)
  }

  private func grouped(_ editor: EditorModel, _ body: () -> Void) {
    editor.undoManager?.beginUndoGrouping()
    body()
    editor.undoManager?.endUndoGrouping()
  }

  private func arrow(from start: CGPoint = .zero) -> Element {
    Element(
      kind: .arrow(start: start, end: CGPoint(x: start.x + 50, y: start.y + 50), doubleHeaded: false),
      style: Style.make(tool: .arrow, imageSize: size))
  }

  /// A private pasteboard, never the general one.
  private func privatePasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("skitcho-test-\(UUID().uuidString)"))
  }

  private func makeModel(
    editor: EditorModel, pasteboard: NSPasteboard? = nil
  ) -> (model: EditorCommandModel, handle: CanvasHandle, canvas: CanvasView) {
    let handle = CanvasHandle()
    let (_, canvas) = CanvasView.makeScrollView(editor: editor)
    handle.attach(canvas)
    let bridge = PasteboardBridge(pasteboard: pasteboard ?? privatePasteboard())
    return (EditorCommandModel(editor: editor, handle: handle, bridge: bridge), handle, canvas)
  }

  // MARK: Pasteboard bridge

  @Test func elementsRoundTripThroughThePasteboard() {
    let pasteboard = privatePasteboard()
    defer { pasteboard.releaseGlobally() }
    let bridge = PasteboardBridge(pasteboard: pasteboard)
    let source = makeEditor(elements: [arrow(), arrow(from: CGPoint(x: 100, y: 100))])
    #expect(!bridge.copyElements(from: source))  // nothing selected
    #expect(!bridge.hasElements)
    source.selectAll()
    #expect(bridge.copyElements(from: source))
    #expect(bridge.hasElements)

    let target = makeEditor()
    grouped(target) { #expect(bridge.pasteElements(into: target)) }
    #expect(target.document.elements.count == 2)
    #expect(Set(target.document.elements.map(\.id)).isDisjoint(with: source.document.elements.map(\.id)))
    #expect(target.selection.count == 2)
  }

  @Test func pasteWithoutElementsChangesNothing() {
    let pasteboard = privatePasteboard()
    defer { pasteboard.releaseGlobally() }
    let bridge = PasteboardBridge(pasteboard: pasteboard)
    let editor = makeEditor()
    #expect(!bridge.pasteElements(into: editor))
    pasteboard.setData(Data("junk".utf8), forType: PasteboardBridge.elementType)
    #expect(!bridge.pasteElements(into: editor))
    #expect(editor.document.elements.isEmpty)
  }

  @Test func imageRoundTripsAsPNGAndTIFF() throws {
    let pasteboard = privatePasteboard()
    defer { pasteboard.releaseGlobally() }
    let bridge = PasteboardBridge(pasteboard: pasteboard)
    #expect(!bridge.hasImage)
    #expect(throws: ImageImportError.self) { try bridge.readDocument() }

    var document = Document.blank(size: CGSize(width: 40, height: 30))
    document.elements = [arrow()]
    try bridge.writeImage(try DocumentRenderer.flatten(document))
    #expect(pasteboard.data(forType: .png) != nil)
    #expect(pasteboard.data(forType: .tiff) != nil)
    #expect(bridge.hasImage)

    let loaded = try bridge.readDocument()
    #expect(loaded.canvasSize == CGSize(width: 40, height: 30))
    #expect(loaded.elements.isEmpty)
  }

  @Test func imageReadsFromTIFFOnlyPasteboard() throws {
    let pasteboard = privatePasteboard()
    defer { pasteboard.releaseGlobally() }
    let image = try DocumentRenderer.flatten(Document.blank(size: CGSize(width: 20, height: 10)))
    pasteboard.setData(try Exporter.encode(image, format: .tiff), forType: .tiff)
    let loaded = try PasteboardBridge(pasteboard: pasteboard).readDocument()
    #expect(loaded.canvasSize == CGSize(width: 20, height: 10))
  }

  // MARK: Enablement table

  @Test func enablementTracksSelectionAndElements() {
    let editor = makeEditor()
    let (model, _, _) = makeModel(editor: editor)
    let selectionDependent: [EditorCommandModel.Command] = [.cut, .copy, .delete, .bringForward, .sendBackward]
    for command in selectionDependent { #expect(!model.isEnabled(command), "\(command) with empty doc") }
    #expect(!model.isEnabled(.selectAll))
    #expect(model.isEnabled(.paste))
  }

  @Test func enablementTable() {
    let editor = makeEditor(elements: [arrow(), arrow(from: CGPoint(x: 90, y: 90))])
    let (model, _, _) = makeModel(editor: editor)

    // Nothing selected, two elements.
    var expected: [EditorCommandModel.Command: Bool] = [
      .cut: false, .copy: false, .paste: true, .delete: false, .selectAll: true,
      .bringForward: false, .sendBackward: false,
      .cropTool: true, .resize: true, .rotateLeft: true, .rotateRight: true,
      .flipHorizontal: true, .flipVertical: true, .expandCanvas: true, .copyImage: true, .exportAs: true,
      .zoomIn: true, .zoomOut: true, .actualSize: true, .zoomToFit: true,
    ]
    for command in EditorCommandModel.Command.allCases {
      #expect(model.isEnabled(command) == expected[command], "\(command), no selection")
    }

    // One element selected.
    editor.select(editor.document.elements[0].id)
    for command in [EditorCommandModel.Command.cut, .copy, .delete, .bringForward, .sendBackward] {
      expected[command] = true
    }
    for command in EditorCommandModel.Command.allCases {
      #expect(model.isEnabled(command) == expected[command], "\(command), selection")
    }
  }

  @Test func reorderNeedsMoreThanOneElement() {
    let editor = makeEditor(elements: [arrow()])
    let (model, _, _) = makeModel(editor: editor)
    editor.selectAll()
    #expect(!model.isEnabled(.bringForward))
    #expect(!model.isEnabled(.sendBackward))
  }

  @Test func zoomCommandsNeedACanvas() {
    let model = EditorCommandModel(
      editor: makeEditor(), handle: CanvasHandle(), bridge: PasteboardBridge(pasteboard: privatePasteboard()))
    for command in [EditorCommandModel.Command.zoomIn, .zoomOut, .actualSize, .zoomToFit] {
      #expect(!model.isEnabled(command))
    }
    #expect(!model.perform(.zoomIn))
  }

  @Test func textEditingRoutesClipboardToTheTextEditorAndDisablesElementCommands() {
    let editor = makeEditor()
    let (model, _, canvas) = makeModel(editor: editor)
    editor.currentTool = .text
    canvas.handleKey(.character("a"), modifiers: [])  // type-to-create starts editing
    #expect(canvas.isEditingText)
    #expect(model.isEnabled(.copy) && model.isEnabled(.cut) && model.isEnabled(.selectAll))
    for command in [
      EditorCommandModel.Command.delete, .bringForward, .sendBackward, .resize, .rotateLeft, .copyImage, .exportAs,
    ] {
      #expect(!model.isEnabled(command), "\(command) while editing")
    }
  }

  // MARK: Actions

  @Test func copyPasteDeleteCutActOnTheSelection() {
    let pasteboard = privatePasteboard()
    defer { pasteboard.releaseGlobally() }
    let editor = makeEditor(elements: [arrow(), arrow(from: CGPoint(x: 90, y: 90))])
    let (model, _, _) = makeModel(editor: editor, pasteboard: pasteboard)
    editor.select(editor.document.elements[0].id)

    #expect(model.perform(.copy))
    grouped(editor) { #expect(model.perform(.paste)) }
    #expect(editor.document.elements.count == 3)

    grouped(editor) { #expect(model.perform(.delete)) }
    #expect(editor.document.elements.count == 2)

    editor.select(editor.document.elements[0].id)
    grouped(editor) { #expect(model.perform(.cut)) }
    #expect(editor.document.elements.count == 1)
    grouped(editor) { #expect(model.perform(.paste)) }
    #expect(editor.document.elements.count == 2)

    editor.deselect()
    #expect(!model.perform(.copy))
    #expect(!model.perform(.delete))
  }

  @Test func selectAllAndReorder() {
    let editor = makeEditor(elements: [arrow(), arrow(from: CGPoint(x: 90, y: 90))])
    let (model, _, _) = makeModel(editor: editor)
    #expect(model.perform(.selectAll))
    #expect(editor.selection.count == 2)

    let bottom = editor.document.elements[0].id
    editor.select(bottom)
    grouped(editor) { #expect(model.perform(.bringForward)) }
    #expect(editor.document.elements.last?.id == bottom)
    grouped(editor) { #expect(model.perform(.sendBackward)) }
    #expect(editor.document.elements.first?.id == bottom)
  }

  @Test func imageCommands() {
    let editor = makeEditor()
    let (model, _, _) = makeModel(editor: editor)
    grouped(editor) { #expect(model.perform(.rotateRight)) }
    #expect(editor.document.canvasSize == CGSize(width: 300, height: 400))
    grouped(editor) { #expect(model.perform(.flipHorizontal)) }
    grouped(editor) { #expect(model.expandCanvas(.bottom)) }
    #expect(editor.document.canvasSize == CGSize(width: 300, height: 400 + EditorCommandModel.expandAmount))
    #expect(model.errorMessage == nil)

    #expect(model.perform(.cropTool))
    #expect(editor.currentTool == .crop)

    var opened = 0
    model.beginResize = { opened += 1 }
    #expect(model.perform(.resize))
    #expect(opened == 1)
  }

  @Test func resizeCommandOpensAndCancelClosesThePanel() {
    let editor = makeEditor()
    let model = EditorCommandModel(editor: editor, handle: CanvasHandle())
    #expect(model.resizeModel == nil)
    #expect(model.perform(.resize))
    #expect(model.resizeModel != nil)
    model.resizeModel?.cancel()
    #expect(model.resizeModel == nil)
  }

  @Test func copyImageWritesPNGAndTIFF() {
    let pasteboard = privatePasteboard()
    defer { pasteboard.releaseGlobally() }
    let editor = makeEditor(elements: [arrow()])
    let (model, _, _) = makeModel(editor: editor, pasteboard: pasteboard)
    #expect(model.perform(.copyImage))
    #expect(pasteboard.data(forType: .png) != nil && pasteboard.data(forType: .tiff) != nil)
  }

  @Test func disabledCommandsDoNothing() {
    let editor = makeEditor()
    let (model, _, _) = makeModel(editor: editor)
    #expect(!model.perform(.delete))
    #expect(!model.perform(.bringForward))
    #expect(editor.document.elements.isEmpty)
  }

  // MARK: Pending document

  @Test func pendingDocumentIsTakenByTheNextNewDocument() {
    defer { PendingDocument.clear() }
    let custom = Document.blank(size: CGSize(width: 12, height: 34))
    PendingDocument.set(custom)
    #expect(SkitchoDocument().initial.canvasSize == CGSize(width: 12, height: 34))
    #expect(SkitchoDocument().initial.canvasSize == Document.blank().canvasSize)
  }

  // MARK: About

  @Test func aboutVersionText() {
    #expect(AboutView.title == "Skitcho — by CloudZone")
    #expect(AboutView.license == "MIT License")
    #expect(AboutView.versionText(info: nil) == "Development build")
    #expect(AboutView.versionText(info: ["CFBundleShortVersionString": "1.2"]) == "Version 1.2")
    #expect(
      AboutView.versionText(info: ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "34"])
        == "Version 1.2 (34)")
  }
}

// MARK: - Tool shortcuts and type-to-create precedence

@MainActor
@Suite struct ToolShortcutTests {
  private func makeCanvas(tool: Tool) -> (EditorModel, CanvasView) {
    let editor = EditorModel(document: Document.blank(size: CGSize(width: 400, height: 300)), undoManager: nil)
    editor.currentTool = tool
    let (_, canvas) = CanvasView.makeScrollView(editor: editor)
    return (editor, canvas)
  }

  @Test func everyShortcutLetterSwitchesTools() {
    let letters = "VATMHRUOLSPC"
    #expect(letters.count == Tool.allCases.count)
    for letter in letters {
      // From the select tool every letter maps to its tool.
      let target = Tool.tool(forShortcut: letter)
      #expect(target != nil)
      #expect(
        ToolShortcutRouter.tool(for: .character(letter), modifiers: [], currentTool: .select, isEditingText: false)
          == target)
    }
  }

  private func route(_ key: ToolKey, _ modifiers: ToolModifiers, on tool: Tool, editing: Bool) -> Tool? {
    ToolShortcutRouter.tool(for: key, modifiers: modifiers, currentTool: tool, isEditingText: editing)
  }

  @Test func routerPrecedence() {
    // 1. editing text: keys go to the editor
    #expect(route(.character("r"), [], on: .arrow, editing: true) == nil)
    #expect(route(.character("r"), [], on: .text, editing: true) == nil)
    // 2. text tool, not editing: typing creates text
    #expect(route(.character("r"), [], on: .text, editing: false) == nil)
    // 3. any other tool: the letter switches (also shifted)
    #expect(route(.character("r"), [], on: .arrow, editing: false) == .rect)
    #expect(route(.character("R"), [.shift], on: .arrow, editing: false) == .rect)
    // chords and non-letters are not shortcuts
    for chord: ToolModifiers in [.command, .control, .option] {
      #expect(route(.character("r"), chord, on: .arrow, editing: false) == nil)
    }
    #expect(route(.escape, [], on: .arrow, editing: false) == nil)
    #expect(route(.character("z"), [], on: .arrow, editing: false) == nil)
  }

  @Test func letterSwitchesToolOnTheCanvas() {
    let (editor, canvas) = makeCanvas(tool: .select)
    #expect(canvas.handleKey(.character("r"), modifiers: []))
    #expect(editor.currentTool == .rect)
    #expect(canvas.handleKey(.character("a"), modifiers: []))
    #expect(editor.currentTool == .arrow)
    #expect(!canvas.isEditingText)
  }

  @Test func textToolTypingCreatesTextInsteadOfSwitching() {
    let (editor, canvas) = makeCanvas(tool: .text)
    #expect(canvas.handleKey(.character("r"), modifiers: []))
    #expect(editor.currentTool == .text)
    #expect(canvas.isEditingText)
  }

  @Test func keysDuringTextEditingDoNotSwitchTools() {
    let (editor, canvas) = makeCanvas(tool: .text)
    canvas.handleKey(.character("h"), modifiers: [])
    #expect(canvas.isEditingText)
    #expect(!canvas.handleKey(.character("r"), modifiers: []))
    #expect(editor.currentTool == .text)
  }

  @Test func shortcutsAreShownInTitlesAndTooltips() {
    #expect(Tool.arrow.titleWithShortcut == "Arrow (A)")
    #expect(Tool.roundedRect.titleWithShortcut == "Rounded Rectangle (U)")
    let editor = EditorModel(document: Document.blank(size: CGSize(width: 40, height: 40)), undoManager: nil)
    let palette = ToolPaletteModel(editor: editor)
    #expect(palette.help(for: .arrow).contains("(A)"))
    // The Shapes button follows a shape picked by keyboard.
    editor.currentTool = .ellipse
    #expect(palette.tool(for: .shapes) == .ellipse)
    #expect(palette.help(for: .shapes).contains("(O)"))
  }
}

// MARK: - Color picker undo coalescing

@MainActor
@Suite struct ColorCoalescingTests {
  private let size = CGSize(width: 400, height: 300)

  private func makeEditor() -> EditorModel {
    let manager = UndoManager()
    manager.groupsByEvent = false
    var document = Document.blank(size: size)
    document.elements = [
      Element(
        kind: .arrow(start: .zero, end: CGPoint(x: 50, y: 50), doubleHeaded: false),
        style: Style.make(tool: .arrow, imageSize: size))
    ]
    let editor = EditorModel(document: document, undoManager: manager)
    editor.select(document.elements[0].id)
    return editor
  }

  private func color(_ step: Double) -> Color { Color(.sRGB, red: step, green: 0.2, blue: 0.4, opacity: 1) }

  @Test func continuousPickerChangesAreOneUndoStep() {
    let editor = makeEditor()
    let manager = editor.undoManager!
    let original = editor.document.elements[0].style.color
    let model = PropertiesModel(editor: editor)
    model.colorCommitDelay = .seconds(60)

    for step in stride(from: 0.1, through: 0.9, by: 0.2) { model.setCustomColor(color(step)) }
    #expect(model.isColorSessionActive)
    #expect(editor.document.elements[0].style.color != original)

    manager.beginUndoGrouping()
    model.finishCustomColor()
    manager.endUndoGrouping()
    #expect(!model.isColorSessionActive)
    #expect(!editor.isInteracting)
    #expect(manager.undoActionName == "Change Color")

    manager.undo()
    #expect(editor.document.elements[0].style.color == original)
    #expect(!manager.canUndo)  // exactly one step
    manager.redo()
    #expect(editor.document.elements[0].style.color != original)
  }

  @Test func quietPeriodCommitsTheChange() async throws {
    let editor = makeEditor()
    let manager = editor.undoManager!
    let model = PropertiesModel(editor: editor)
    model.colorCommitDelay = .milliseconds(20)

    manager.beginUndoGrouping()
    model.setCustomColor(color(0.3))
    model.setCustomColor(color(0.6))
    try await Task.sleep(for: .milliseconds(300))
    manager.endUndoGrouping()
    #expect(!model.isColorSessionActive)
    #expect(!editor.isInteracting)
    #expect(manager.canUndo)
    manager.undo()
    #expect(!manager.canUndo)
  }

  @Test func otherCommandsFlushThePendingColorFirst() {
    let editor = makeEditor()
    let manager = editor.undoManager!
    let model = PropertiesModel(editor: editor)
    model.colorCommitDelay = .seconds(60)
    model.setCustomColor(color(0.5))

    manager.beginUndoGrouping()
    model.setSize(.default)  // same size: changes nothing, but must close the color session
    manager.endUndoGrouping()
    #expect(!model.isColorSessionActive)
    #expect(manager.canUndo)
  }

  /// A canvas press within the debounce closes the color step first, so the drag gets its own undo step.
  @Test func canvasPressFlushesThePendingColor() throws {
    let editor = makeEditor()
    let manager = editor.undoManager!
    let model = PropertiesModel(editor: editor)
    model.colorCommitDelay = .seconds(60)
    let handle = CanvasHandle()
    let canvas = CanvasView(editor: editor)
    handle.attach(canvas)
    handle.willHandleCanvasInput = { [weak model] in model?.finishCustomColor() }
    model.setCustomColor(color(0.5))
    #expect(editor.isInteracting)

    let event = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: NSPoint(x: 1, y: 1), modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    manager.beginUndoGrouping()
    canvas.mouseDown(with: event)
    manager.endUndoGrouping()
    #expect(!model.isColorSessionActive)
    #expect(manager.undoActionName == "Change Color")
  }

  @Test func pickerWithoutSelectionSetsTheNextColorWithoutUndo() {
    let editor = makeEditor()
    editor.deselect()
    let model = PropertiesModel(editor: editor)
    model.colorCommitDelay = .seconds(60)
    model.setCustomColor(color(0.7))
    model.finishCustomColor()
    #expect(editor.nextColor != nil)
    #expect(!editor.undoManager!.canUndo)
  }
}
