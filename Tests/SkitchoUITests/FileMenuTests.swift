import AppKit
import CoreGraphics
import Foundation
import SkitchoCore
import SwiftUI
import Testing
import UniformTypeIdentifiers

import struct SkitchoCore.Document

@testable import SkitchoUI

/// An `NSDocument` that records the document commands the File menu sends.
private final class MenuRecordingDocument: NSDocument {
  var calls: [String] = []
  override func duplicate(_ sender: Any?) { calls.append("duplicate") }
  override func revertToSaved(_ sender: Any?) { calls.append("revert") }
  override func rename(_ sender: Any?) { calls.append("rename") }
  override func move(_ sender: Any?) { calls.append("move") }
  override func save(_ sender: Any?) { calls.append("save") }
  override func saveAs(_ sender: Any?) { calls.append("saveAs") }
}

@MainActor
@Suite struct FileMenuTests {
  private let saved = URL(fileURLWithPath: "/tmp/skitcho-menu-test/a")

  private func document(type: UTType, url: URL?) -> MenuRecordingDocument {
    let document = MenuRecordingDocument()
    document.fileType = type.identifier
    document.fileURL = url
    return document
  }

  private func makeEditor() -> EditorModel {
    EditorModel(document: Document.blank(size: CGSize(width: 40, height: 30)), undoManager: nil)
  }

  private func makeCoordinator(_ nsDocument: NSDocument?) -> SaveCoordinator {
    SaveCoordinator(
      editor: makeEditor(), handle: CanvasHandle(), window: { nil }, resolveDocument: { _ in nsDocument },
      presentPanel: { _, completion in completion(nil) })
  }

  // MARK: Table

  @Test func tableExposesEveryItemWithItsShortcut() {
    #expect(FileMenuItem.allCases == [.close, .save, .saveAs, .duplicate, .revertToSaved, .rename, .moveTo])
    #expect(FileMenuItem.close.title == "Close")
    #expect(FileMenuItem.save.title == "Save")
    #expect(FileMenuItem.saveAs.title == "Save As…")
    #expect(FileMenuItem.duplicate.title == "Duplicate")
    #expect(FileMenuItem.revertToSaved.title == "Revert to Saved")
    #expect(FileMenuItem.rename.title == "Rename…")
    #expect(FileMenuItem.moveTo.title == "Move To…")

    #expect(FileMenuItem.close.shortcut == KeyboardShortcut("w", modifiers: .command))
    #expect(FileMenuItem.save.shortcut == KeyboardShortcut("s", modifiers: .command))
    #expect(FileMenuItem.saveAs.shortcut == KeyboardShortcut("s", modifiers: [.command, .shift]))
    for item in [FileMenuItem.duplicate, .revertToSaved, .rename, .moveTo] {
      #expect(item.shortcut == nil, "\(item)")
    }
  }

  @Test func closeIsEnabledWheneverAnyWindowIsKey() {
    // About or Settings: a key window, no document.
    #expect(FileMenuItem.close.isEnabled(hasKeyWindow: true, document: nil))
    #expect(!FileMenuItem.close.isEnabled(hasKeyWindow: false, document: nil))
    #expect(FileMenuItem.close.isEnabled(hasKeyWindow: true, document: document(type: .jpeg, url: nil)))
    // Document-only items are off without a document.
    #expect(!FileMenuItem.save.isEnabled(hasKeyWindow: true, document: nil))
  }

  @Test func enablementByDocumentKind() {
    let editable: [FileMenuItem: Bool] = [
      .save: true, .saveAs: true, .duplicate: true, .revertToSaved: true, .rename: true, .moveTo: true,
    ]
    let readOnlyFile: [FileMenuItem: Bool] = [
      .save: true, .saveAs: true, .duplicate: true, .revertToSaved: false, .rename: false, .moveTo: false,
    ]
    let kinds: [(String, NSDocument, [FileMenuItem: Bool])] = [
      ("saved skitcho", document(type: .skitchoDocument, url: saved), editable),
      ("unsaved skitcho", document(type: .skitchoDocument, url: nil), readOnlyFile),
      ("opened jpeg", document(type: .jpeg, url: saved), readOnlyFile),
      ("opened png", document(type: .png, url: saved), readOnlyFile),
    ]
    for (name, document, expected) in kinds {
      for (item, enabled) in expected {
        #expect(item.isEnabled(hasKeyWindow: true, document: document) == enabled, "\(item), \(name)")
      }
    }
  }

  // MARK: Routing

  @Test func theModelRoutesFileItemsToTheWindowsDocument() {
    let nsDocument = document(type: .skitchoDocument, url: saved)
    let model = EditorCommandModel(editor: makeEditor(), handle: CanvasHandle())
    #expect(!model.isEnabled(FileMenuItem.save))  // no coordinator yet
    #expect(!model.perform(FileMenuItem.save))

    model.saveCoordinator = makeCoordinator(nsDocument)
    for item in [FileMenuItem.duplicate, .revertToSaved, .rename, .moveTo, .save, .saveAs] {
      #expect(model.perform(item), "\(item)")
    }
    // Save on a saved .skitcho goes to the document's own save; Save As asks the panel (cancelled here).
    #expect(nsDocument.calls == ["duplicate", "revert", "rename", "move", "save"])
    // Close is routed to the key window by the menu, never through the model.
    #expect(!model.perform(FileMenuItem.close))
  }

  @Test func revertRenameAndMoveDoNothingForDocumentsThatAreNotSavedSkitchoFiles() {
    let jpeg = document(type: .jpeg, url: saved)
    let coordinator = makeCoordinator(jpeg)
    for item in [FileMenuItem.revertToSaved, .rename, .moveTo] {
      #expect(!coordinator.perform(item), "\(item)")
    }
    #expect(jpeg.calls.isEmpty)
    #expect(coordinator.perform(.duplicate))
    #expect(jpeg.calls == ["duplicate"])
  }

  // MARK: Save panel accessory

  @Test func thePopupOffersJPEGFirstAndChangesTheTypeAndExtension() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Screenshot"
    let accessory = SaveFormatAccessoryView(panel: panel)

    #expect(accessory.popup.itemTitles == ["JPEG", "Skitcho (editable)"])
    #expect(accessory.selectedFormat == .jpeg)
    #expect(panel.allowedContentTypes == [.jpeg])
    #expect(panel.nameFieldStringValue == "Screenshot.jpg")

    // Pick the second item the way the popup does: select, then fire its action.
    accessory.popup.selectItem(at: 1)
    _ = accessory.popup.target?.perform(accessory.popup.action, with: accessory.popup)
    #expect(accessory.selectedFormat == .skitcho)
    #expect(panel.allowedContentTypes == [.skitchoDocument])
    #expect(panel.nameFieldStringValue == "Screenshot.skitcho")

    accessory.select(.jpeg)
    #expect(accessory.popup.indexOfSelectedItem == 0)
    #expect(panel.allowedContentTypes == [.jpeg])
    #expect(panel.nameFieldStringValue == "Screenshot.jpg")
  }

  @Test func onlyKnownExtensionsAreReplaced() {
    #expect(SaveFormatAccessoryView.name("v1.2", in: .jpeg) == "v1.2.jpg")
    #expect(SaveFormatAccessoryView.name("shot.JPEG", in: .skitcho) == "shot.skitcho")
    #expect(SaveFormatAccessoryView.name("shot.skitcho", in: .jpeg) == "shot.jpg")
  }
}
