import Foundation
import SkitchoCore

// User-facing text for Core errors. `localizedDescription` (alerts, the open-failure dialog of the document
// system, the crop/pixelate/resize bars) then reads as a sentence instead of a type name.

extension ImageImportError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unreadable: "The file is not an image Skitcho can read."
    case .zeroSize: "The image has no pixels."
    case .tooLarge: "The image is too large. Skitcho opens images up to \(ImageOps.maxSide) pixels per side."
    }
  }
}

extension ImageOpError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .tooLarge: "The image would be larger than \(ImageOps.maxSide) pixels per side."
    case .invalidRect: "The selected area is empty or outside the image."
    case .invalidArgument: "The value is out of range."
    case .renderFailed: "The image could not be processed."
    }
  }
}

extension RenderError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidSize: "The image is too large to render."
    case .contextCreationFailed, .imageCreationFailed: "The image could not be rendered."
    }
  }
}

extension ExportError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidScale: "The export scale is not supported."
    case .encodingFailed: "The image could not be encoded."
    }
  }
}

extension PackageCodecError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missingFile(let name): "The document is damaged: \(name) is missing."
    case .corruptImage: "The document's image is damaged."
    case .corruptJSON: "The document's annotations are damaged."
    case .unsupportedVersion: "The document was saved by a newer version of Skitcho."
    case .encodingFailed: "The document could not be written."
    }
  }
}
