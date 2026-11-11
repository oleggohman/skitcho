import CoreGraphics
import Foundation

/// An sRGB color with components clamped to 0...1.
public struct RGBA: Sendable, Equatable, Hashable, Codable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = RGBA.clamp(red)
    self.green = RGBA.clamp(green)
    self.blue = RGBA.clamp(blue)
    self.alpha = RGBA.clamp(alpha)
  }

  /// Builds a color from a 24-bit 0xRRGGBB value.
  public init(hex: UInt32, alpha: Double = 1) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      alpha: alpha)
  }

  private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }

  /// Decoding clamps out-of-range values; a missing alpha means opaque.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      red: try container.decode(Double.self, forKey: .red),
      green: try container.decode(Double.self, forKey: .green),
      blue: try container.decode(Double.self, forKey: .blue),
      alpha: try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1)
  }

  private static func clamp(_ value: Double) -> Double {
    value.isNaN ? 0 : min(1, max(0, value))
  }
}

/// The content palette used for annotations (distinct from the app chrome's `BrandColor`).
public enum AnnotationColor: Sendable, Equatable, Hashable, Codable {
  case red, orange, blue, purple, lavender, navy
  case black, white
  /// Content-only exception to the brand palette: the highlighter default.
  case yellow
  /// Content-only exception to the brand palette: the approve stamp.
  case green
  case custom(RGBA)

  /// Preset swatches in display order.
  public static let presets: [AnnotationColor] = [
    .red, .orange, .yellow, .green, .blue, .purple, .lavender, .navy, .black, .white,
  ]

  public var rgba: RGBA {
    switch self {
    case .red: return RGBA(hex: 0xF96C5D)  // #f96c5d
    case .orange: return RGBA(hex: 0xF8A23A)  // #f8a23a
    case .blue: return RGBA(hex: 0x2FA8F7)  // #2fa8f7
    case .purple: return RGBA(hex: 0x5D77F9)  // #5d77f9
    case .lavender: return RGBA(hex: 0xAF85F5)  // #af85f5
    case .navy: return RGBA(hex: 0x0E1E4D)  // #0e1e4d
    case .black: return RGBA(hex: 0x000000)
    case .white: return RGBA(hex: 0xFFFFFF)
    case .yellow: return RGBA(hex: 0xFFD60A)  // #ffd60a
    case .green: return RGBA(hex: 0x34C759)  // #34c759
    case .custom(let value): return value
    }
  }

  public var cgColor: CGColor {
    let value = rgba
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGColor(colorSpace: space, components: [value.red, value.green, value.blue, value.alpha])!
  }

  /// WCAG relative luminance (0 = black, 1 = white), ignoring alpha.
  public var luminance: Double {
    func linear(_ channel: Double) -> Double {
      channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    let value = rgba
    return 0.2126 * linear(value.red) + 0.7152 * linear(value.green) + 0.0722 * linear(value.blue)
  }

  /// A black or white color that stays readable around this color (used for text outlines).
  public var contrastingOutline: AnnotationColor {
    luminance > 0.4 ? .black : .white
  }
}
