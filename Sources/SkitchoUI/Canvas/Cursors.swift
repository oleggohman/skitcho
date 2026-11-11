import AppKit
import SkitchoCore

/// Per-tool cursors built from SF Symbols (UI only; Core never uses symbols).
@MainActor
public enum ToolCursors {
  /// SF Symbol name of the cursor glyph, nil for tools using a system cursor.
  public static func symbolName(for tool: Tool) -> String? {
    switch tool {
    case .select: nil
    case .arrow: "arrow.up.right"
    case .text: "textformat"
    case .marker: "pencil.tip"
    case .highlighter: "highlighter"
    case .rect: "rectangle"
    case .roundedRect: "app"
    case .ellipse: "circle"
    case .line: "line.diagonal"
    case .stamp: "checkmark.seal"
    case .pixelate: "squareshape.split.3x3"
    case .crop: "crop"
    }
  }

  private static var cache: [Tool: NSCursor] = [:]

  public static func cursor(for tool: Tool) -> NSCursor {
    if let cached = cache[tool] { return cached }
    let cursor = makeCursor(for: tool)
    cache[tool] = cursor
    return cursor
  }

  private static func makeCursor(for tool: Tool) -> NSCursor {
    guard let name = symbolName(for: tool) else { return .arrow }
    let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    guard
      let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else { return .crosshair }
    let size = NSSize(width: symbol.size.width + 4, height: symbol.size.height + 4)
    let white = tinted(symbol, with: .white)
    let black = tinted(symbol, with: .black)
    let image = NSImage(size: size, flipped: false) { _ in
      // A white halo (glyph offset in four directions) keeps the black glyph visible on dark content.
      for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
        white.draw(in: NSRect(origin: NSPoint(x: 2 + dx, y: 2 + dy), size: symbol.size))
      }
      black.draw(in: NSRect(origin: NSPoint(x: 2, y: 2), size: symbol.size))
      return true
    }
    return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
  }

  private static func tinted(_ symbol: NSImage, with color: NSColor) -> NSImage {
    NSImage(size: symbol.size, flipped: false) { rect in
      symbol.draw(in: rect)
      color.set()
      rect.fill(using: .sourceIn)
      return true
    }
  }
}
