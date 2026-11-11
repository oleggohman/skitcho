import AppKit
import SkitchoCore

/// Moves editor data through an `NSPasteboard`: elements as `ElementClipboard` bytes under a custom type,
/// images as PNG + TIFF. The pasteboard is injectable so tests never touch the general one.
@MainActor
public struct PasteboardBridge {
  /// Custom type carrying `ElementClipboard` JSON.
  public static let elementType = NSPasteboard.PasteboardType("com.oleggohman.skitcho.elements")

  private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

  public let pasteboard: NSPasteboard

  public init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  // MARK: Elements

  /// Copies the selected elements of `editor`. Returns false when nothing is selected.
  @discardableResult
  public func copyElements(from editor: EditorModel) -> Bool {
    guard let data = editor.copySelectionData() else { return false }
    pasteboard.clearContents()
    return pasteboard.setData(data, forType: Self.elementType)
  }

  public var hasElements: Bool { pasteboard.data(forType: Self.elementType) != nil }

  /// Pastes the copied elements into `editor`. Returns false when the pasteboard holds none.
  @discardableResult
  public func pasteElements(into editor: EditorModel) -> Bool {
    guard let data = pasteboard.data(forType: Self.elementType) else { return false }
    return editor.paste(data)
  }

  // MARK: Images

  /// Writes `image` as PNG and TIFF so any receiver can pick its preferred format.
  public func writeImage(_ image: CGImage) throws {
    let png = try Exporter.encode(image, format: .png)
    let tiff = try Exporter.encode(image, format: .tiff)
    pasteboard.clearContents()
    pasteboard.setData(png, forType: .png)
    pasteboard.setData(tiff, forType: .tiff)
  }

  public var hasImage: Bool { imageData() != nil }

  /// Image bytes on the pasteboard: PNG or TIFF directly, else whatever `NSImage` can read from it.
  public func imageData() -> Data? {
    if let type = pasteboard.availableType(from: Self.imageTypes), let data = pasteboard.data(forType: type) {
      return data
    }
    guard NSImage.canInit(with: pasteboard) else { return nil }
    return NSImage(pasteboard: pasteboard)?.tiffRepresentation
  }

  /// A new document whose base image is the pasteboard image (New from Clipboard).
  public func readDocument() throws -> Document {
    guard let data = imageData() else { throw ImageImportError.unreadable }
    return try ImageImporter.load(data: data)
  }
}
