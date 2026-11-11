import CoreGraphics
import Foundation

/// The drawing tools that carry style defaults. The editor's `Tool` enum maps onto this.
public enum StyleTool: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
  case arrow, line, rect, roundedRect, ellipse, marker, highlighter, text, stamp
}

/// Visual style of an element. `strokeWidth` and `fontSize` are absolute document units, frozen at creation.
public struct Style: Sendable, Equatable, Codable {
  public var color: AnnotationColor
  public var sizeStep: SizeStep
  public var strokeWidth: Double
  public var fontSize: Double

  public init(color: AnnotationColor, sizeStep: SizeStep, strokeWidth: Double, fontSize: Double) {
    self.color = color
    self.sizeStep = sizeStep
    self.strokeWidth = strokeWidth
    self.fontSize = fontSize
  }

  /// Image-size factor: images shorter than 1000 px use 1, larger ones scale up proportionally.
  public static func imageScale(for imageSize: CGSize) -> Double {
    max(1, min(imageSize.width, imageSize.height) / 1000)
  }

  /// Stroke width at relative size 1.0 on a 1000 px image.
  public static func strokeBase(for tool: StyleTool) -> Double {
    tool == .highlighter ? 28 : 10
  }

  /// Font size at relative size 1.0 on a 1000 px image.
  public static let fontBase: Double = 48

  public static func defaultColor(for tool: StyleTool) -> AnnotationColor {
    tool == .highlighter ? .yellow : .red
  }

  public static func strokeWidth(tool: StyleTool, sizeStep: SizeStep, imageSize: CGSize) -> Double {
    sizeStep.relative * strokeBase(for: tool) * imageScale(for: imageSize)
  }

  public static func fontSize(sizeStep: SizeStep, imageSize: CGSize) -> Double {
    sizeStep.relative * fontBase * imageScale(for: imageSize)
  }

  /// Creates a style for `tool`, freezing absolute sizes from the current image size.
  public static func make(
    tool: StyleTool,
    sizeStep: SizeStep = .default,
    color: AnnotationColor? = nil,
    imageSize: CGSize
  ) -> Style {
    Style(
      color: color ?? defaultColor(for: tool),
      sizeStep: sizeStep,
      strokeWidth: strokeWidth(tool: tool, sizeStep: sizeStep, imageSize: imageSize),
      fontSize: fontSize(sizeStep: sizeStep, imageSize: imageSize))
  }

  /// Returns the style with both absolute sizes multiplied (used when an image is resized).
  public func scaled(by factor: Double) -> Style {
    var copy = self
    copy.strokeWidth *= factor
    copy.fontSize *= factor
    return copy
  }
}
