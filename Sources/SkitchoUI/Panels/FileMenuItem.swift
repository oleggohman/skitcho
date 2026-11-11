import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The File menu items that replace SwiftUI's save group (Close, Save, Save As…, Duplicate, Revert to Saved,
/// Rename…, Move To…), as a table: title, key equivalent and enablement rule. The app's `Commands` only renders it.
public enum FileMenuItem: CaseIterable, Sendable {
  case close, save, saveAs, duplicate, revertToSaved, rename, moveTo

  /// When an item is available.
  public enum Enablement: Sendable {
    /// Always. Close acts on whatever window is key (also About and Settings) and does nothing without one; the
    /// key window is not observable, so a rule based on it could leave Close stuck disabled.
    case always
    /// The key window is a document window.
    case documentWindow
    /// The key window's document is a `.skitcho` file that has been saved (it has a `fileURL`).
    case savedSkitchoDocument
  }

  public var title: String {
    switch self {
    case .close: "Close"
    case .save: "Save"
    case .saveAs: "Save As…"
    case .duplicate: "Duplicate"
    case .revertToSaved: "Revert to Saved"
    case .rename: "Rename…"
    case .moveTo: "Move To…"
    }
  }

  /// The key equivalent, nil when the item has none. Duplicate has none because ⇧⌘S is Save As.
  public var shortcut: KeyboardShortcut? {
    switch self {
    case .close: KeyboardShortcut("w", modifiers: .command)
    case .save: KeyboardShortcut("s", modifiers: .command)
    case .saveAs: KeyboardShortcut("s", modifiers: [.command, .shift])
    case .duplicate, .revertToSaved, .rename, .moveTo: nil
    }
  }

  public var enablement: Enablement {
    switch self {
    case .close: .always
    case .save, .saveAs, .duplicate: .documentWindow
    case .revertToSaved, .rename, .moveTo: .savedSkitchoDocument
    }
  }

  /// Whether the item is enabled. `document` is the key window's document, nil when it is not a document window.
  @MainActor
  public func isEnabled(document: NSDocument?) -> Bool {
    switch enablement {
    case .always: return true
    case .documentWindow: return document != nil
    case .savedSkitchoDocument:
      guard let document else { return false }
      return SaveCoordinator.isSkitchoFile(document)
    }
  }
}
