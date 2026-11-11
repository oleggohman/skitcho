import CoreGraphics
import Foundation

/// Errors thrown while reading or writing the `.skitcho` package.
public enum PackageCodecError: Error, Equatable {
  case missingFile(String)
  case corruptImage
  case corruptJSON
  /// The package was written by a newer version of the app.
  case unsupportedVersion(Int)
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
    var imageOriginX: Double
    var imageOriginY: Double
    var background: AnnotationColor
    var elements: [Element]
  }

  /// Read first so a package from a future version reports its version instead of a decoding error.
  private struct Header: Codable {
    var version: Int
  }

  public static func wrapper(for document: Document) throws -> FileWrapper {
    let payload = Payload(
      version: Document.currentVersion, canvasWidth: document.canvasSize.width,
      canvasHeight: document.canvasSize.height, imageOriginX: document.imageOrigin.x,
      imageOriginY: document.imageOrigin.y, background: document.background, elements: document.elements)
    // Non-finite geometry cannot be written as JSON; report it as a codec error, not a raw EncodingError.
    guard let json = try? JSONEncoder().encode(payload) else { throw PackageCodecError.encodingFailed }
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
    let decoder = JSONDecoder()
    guard let header = try? decoder.decode(Header.self, from: jsonData) else { throw PackageCodecError.corruptJSON }
    guard header.version <= Document.currentVersion else { throw PackageCodecError.unsupportedVersion(header.version) }
    guard header.version >= 1 else { throw PackageCodecError.corruptJSON }
    guard let payload = try? decoder.decode(Payload.self, from: jsonData) else { throw PackageCodecError.corruptJSON }
    // The file is untrusted: the canvas must be a drawable size and the origin finite, or rendering traps.
    let limit = Double(ImageOps.maxSide)
    guard (1...limit).contains(payload.canvasWidth), (1...limit).contains(payload.canvasHeight),
      payload.imageOriginX.isFinite, payload.imageOriginY.isFinite
    else { throw PackageCodecError.corruptJSON }
    let image: CGImage
    do {
      image = try ImageImporter.decodeImage(pngData)
    } catch {
      throw PackageCodecError.corruptImage
    }
    return Document(
      baseImage: image, canvasSize: CGSize(width: payload.canvasWidth, height: payload.canvasHeight),
      imageOrigin: CGPoint(x: payload.imageOriginX, y: payload.imageOriginY), background: payload.background,
      elements: payload.elements, version: payload.version)
  }

  public static func pngData(_ image: CGImage) throws -> Data {
    do {
      return try Exporter.encode(image, format: .png)
    } catch {
      throw PackageCodecError.encodingFailed
    }
  }
}
