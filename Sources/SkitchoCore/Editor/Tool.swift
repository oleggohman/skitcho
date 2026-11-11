import CoreGraphics
import Foundation

/// The editor tools. Drawing tools map onto `StyleTool` for their default style.
public enum Tool: String, Sendable, Equatable, Hashable, CaseIterable {
  case select, arrow, text, marker, highlighter, rect, roundedRect, ellipse, line, stamp, pixelate, crop

  /// Single-key shortcut (lowercase): V A T M H R U O L S P C.
  public var shortcut: Character {
    switch self {
    case .select: "v"
    case .arrow: "a"
    case .text: "t"
    case .marker: "m"
    case .highlighter: "h"
    case .rect: "r"
    case .roundedRect: "u"
    case .ellipse: "o"
    case .line: "l"
    case .stamp: "s"
    case .pixelate: "p"
    case .crop: "c"
    }
  }

  /// The tool bound to `key` (case-insensitive), if any.
  public static func tool(forShortcut key: Character) -> Tool? {
    let lowered = Character(key.lowercased())
    return allCases.first { $0.shortcut == lowered }
  }

  /// The style family of the tool, or nil for tools that create no styled element.
  public var styleTool: StyleTool? {
    switch self {
    case .arrow: .arrow
    case .line: .line
    case .rect: .rect
    case .roundedRect: .roundedRect
    case .ellipse: .ellipse
    case .marker: .marker
    case .highlighter: .highlighter
    case .text: .text
    case .stamp: .stamp
    case .select, .pixelate, .crop: nil
    }
  }

  /// Default style for a new element made with this tool (nil for non-drawing tools).
  public func defaultStyle(
    sizeStep: SizeStep = .default, color: AnnotationColor? = nil, imageSize: CGSize
  ) -> Style? {
    styleTool.map { Style.make(tool: $0, sizeStep: sizeStep, color: color, imageSize: imageSize) }
  }
}
