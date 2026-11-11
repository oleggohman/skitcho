import CoreGraphics
import Foundation

/// Data encoding of copied elements (the NSPasteboard bridge in SkitchoUI only moves these bytes around).
public enum ElementClipboard {
  /// Offset applied to pasted elements so they do not hide the originals.
  public static let pasteOffset = CGPoint(x: 10, y: 10)

  private struct Payload: Codable {
    var version: Int
    var elements: [Element]
  }

  private static let currentVersion = 1

  /// Encodes `elements` as JSON. Returns nil for an empty list.
  public static func encode(_ elements: [Element]) -> Data? {
    guard !elements.isEmpty else { return nil }
    return try? JSONEncoder().encode(Payload(version: currentVersion, elements: elements))
  }

  /// Decodes data written by `encode`. Returns nil for anything unreadable, empty or from a newer version.
  public static func decode(_ data: Data) -> [Element]? {
    guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
      payload.version <= currentVersion, !payload.elements.isEmpty
    else { return nil }
    return payload.elements
  }

  /// Copies of `elements` with fresh IDs (stamp label links follow the new IDs), moved by `offset`.
  static func duplicated(_ elements: [Element], offset: CGPoint) -> [Element] {
    var idMap: [UUID: UUID] = [:]
    for element in elements { idMap[element.id] = UUID() }
    return elements.map { element in
      var copy = element.translated(by: offset)
      copy.id = idMap[element.id] ?? UUID()
      if case .stamp(let kind, let center, let tail, let label) = copy.kind {
        copy.kind = .stamp(kind, center: center, tailAngle: tail, labelID: label.flatMap { idMap[$0] })
      }
      return copy
    }
  }
}
