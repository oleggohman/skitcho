import Foundation
import Observation

/// Minimal editor state holder; undo, selection and commands arrive in later tasks.
@MainActor @Observable
public final class EditorModel {
  public var document: Document
  public var undoManager: UndoManager?

  public init(document: Document, undoManager: UndoManager?) {
    self.document = document
    self.undoManager = undoManager
  }
}
