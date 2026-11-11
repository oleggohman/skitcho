import CoreGraphics
import CoreText
import Foundation

/// CoreText layout and drawing for text elements. Uses the system UI font only, so rendered content does not
/// depend on installed fonts. Layout is in document space (top-left origin, y-down).
public enum TextRenderer {
  /// Outline width of styled text as a fraction of the font size.
  public static let outlineWidthRatio = 0.12

  /// The system font at `fontSize` (never a bundled or named font).
  static func font(size: Double) -> CTFont {
    let points = max(1, size)
    return CTFontCreateUIFontForLanguage(.system, points, nil)
      ?? CTFontCreateWithName("Helvetica" as CFString, points, nil)
  }

  /// Text with attributes that take the fill/stroke color from the drawing context.
  private static func attributed(_ string: String, fontSize: Double) -> CFAttributedString {
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font(size: fontSize),
      NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
    ]
    return NSAttributedString(string: string, attributes: attributes) as CFAttributedString
  }

  private static func framesetter(for content: TextContent, fontSize: Double) -> CTFramesetter {
    CTFramesetterCreateWithAttributedString(attributed(content.string, fontSize: fontSize))
  }

  private static func lineHeight(fontSize: Double) -> Double {
    let font = font(size: fontSize)
    return (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
  }

  /// Laid-out size of the text in document units. Wrapped text is as wide as its wrap width.
  public static func size(for content: TextContent, fontSize: Double) -> CGSize {
    let height = lineHeight(fontSize: fontSize)
    let wrap = content.wrapWidth.flatMap { $0 > 0 ? $0 : nil }
    guard !content.string.isEmpty else { return CGSize(width: wrap ?? 0, height: height) }
    let measured = CTFramesetterSuggestFrameSizeWithConstraints(
      framesetter(for: content, fontSize: fontSize), CFRange(location: 0, length: 0), nil,
      CGSize(width: wrap ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude), nil)
    return CGSize(width: wrap ?? measured.width.rounded(.up), height: max(height, measured.height.rounded(.up)))
  }

  /// Draws the text into a y-down document-space context. `rotation` turns the text box about its center.
  static func draw(_ content: TextContent, style: Style, rotation: Double, in context: CGContext) {
    guard !content.string.isEmpty else { return }
    let size = size(for: content, fontSize: style.fontSize)
    guard size.width > 0, size.height > 0 else { return }

    context.saveGState()
    defer { context.restoreGState() }

    if rotation != 0 {
      let center = CGPoint(x: content.origin.x + size.width / 2, y: content.origin.y + size.height / 2)
      context.translateBy(x: center.x, y: center.y)
      context.rotate(by: rotation)
      context.translateBy(x: -center.x, y: -center.y)
    }

    // CoreText lays out y-up: flip locally so the text box (0, 0, w, h) sits at `origin` and glyphs are upright.
    context.translateBy(x: content.origin.x, y: content.origin.y + size.height)
    context.scaleBy(x: 1, y: -1)

    let frame = CTFramesetterCreateFrame(
      framesetter(for: content, fontSize: style.fontSize), CFRange(location: 0, length: 0),
      CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), nil)

    if content.styled {
      context.setTextDrawingMode(.stroke)
      context.setStrokeColor(style.color.contrastingOutline.cgColor)
      context.setLineWidth(style.fontSize * outlineWidthRatio)
      context.setLineJoin(.round)
      CTFrameDraw(frame, context)
    }
    context.setTextDrawingMode(.fill)
    context.setFillColor(style.color.cgColor)
    CTFrameDraw(frame, context)
  }
}
