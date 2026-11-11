import Foundation
import SkitchoCore
import UniformTypeIdentifiers

import struct SkitchoCore.Document

/// A JPEG could not be produced. Carries the readable message from `ErrorMessages`.
public struct SaveFormatError: Error, LocalizedError, Equatable {
  public let message: String
  public var errorDescription: String? { message }
}

/// The formats the Save panel offers. JPEG is the default (flattened, lossy); Skitcho keeps the annotations editable.
///
/// JPEG is deliberately NOT a writable content type of `SkitchoDocument`: SwiftUI hard-codes autosave-in-place for
/// every writable type, which would silently overwrite a lossy file. JPEG is written by the save coordinator only.
public enum SaveFormat: Sendable, CaseIterable {
  case jpeg
  case skitcho

  /// JPEG quality for saved files (0...1).
  public static let jpegQuality = 0.9

  public var fileExtension: String {
    switch self {
    case .jpeg: "jpg"
    case .skitcho: "skitcho"
    }
  }

  public var contentType: UTType {
    switch self {
    case .jpeg: .jpeg
    case .skitcho: .skitchoDocument
    }
  }

  /// Flattens `document` at 1x and encodes it as JPEG. Pure, so it may run off the main actor.
  public static func jpegData(for document: Document) throws -> Data {
    do {
      return try Exporter.data(document, format: .jpeg(quality: jpegQuality), scale: 1)
    } catch {
      throw SaveFormatError(message: error.localizedDescription)
    }
  }
}
