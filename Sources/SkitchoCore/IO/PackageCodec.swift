import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Errors thrown while reading or writing the `.skitcho` package.
public enum PackageCodecError: Error, Equatable {
  case missingFile(String)
  case corruptImage
  case corruptJSON
  case encodingFailed
}

/// Reads and writes the `.skitcho` package: a directory with `document.json` and `base.png`.
public enum PackageCodec {
  public static let jsonName = "document.json"
  public static let imageName = "base.png"

  struct Payload: Codable {
    var version: Int
    var canvasWidth: Double
    var canvasHeight: Double
    var elements: [Element]
  }

  public static func wrapper(for document: Document) throws -> FileWrapper {
    let payload = Payload(
      version: 1, canvasWidth: document.canvasSize.width, canvasHeight: document.canvasSize.height,
      elements: document.elements)
    let json = try JSONEncoder().encode(payload)
    let png = try pngData(document.baseImage)
    let dir = FileWrapper(directoryWithFileWrappers: [:])
    let jsonFile = FileWrapper(regularFileWithContents: json)
    jsonFile.preferredFilename = jsonName
    let pngFile = FileWrapper(regularFileWithContents: png)
    pngFile.preferredFilename = imageName
    dir.addFileWrapper(jsonFile)
    dir.addFileWrapper(pngFile)
    return dir
  }

  public static func document(from wrapper: FileWrapper) throws -> Document {
    guard let files = wrapper.fileWrappers else { throw PackageCodecError.missingFile(jsonName) }
    guard let jsonData = files[jsonName]?.regularFileContents else { throw PackageCodecError.missingFile(jsonName) }
    guard let pngData = files[imageName]?.regularFileContents else { throw PackageCodecError.missingFile(imageName) }
    guard let payload = try? JSONDecoder().decode(Payload.self, from: jsonData) else {
      throw PackageCodecError.corruptJSON
    }
    let image = try decodeImage(pngData)
    return Document(
      baseImage: image, canvasSize: CGSize(width: payload.canvasWidth, height: payload.canvasHeight),
      elements: payload.elements)
  }

  /// Builds a document from raw image bytes (PNG, JPEG, ...).
  public static func document(fromImageData data: Data) throws -> Document {
    Document(baseImage: try decodeImage(data))
  }

  public static func decodeImage(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw PackageCodecError.corruptImage }
    return image
  }

  public static func pngData(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
      throw PackageCodecError.encodingFailed
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw PackageCodecError.encodingFailed }
    return data as Data
  }
}
