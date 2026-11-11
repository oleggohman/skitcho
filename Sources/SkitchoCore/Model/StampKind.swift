import CoreGraphics
import Foundation

/// The stamp badges. Glyphs are drawn geometry (built at render time), never SF Symbols.
public enum StampKind: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
  case approve  // check mark
  case reject  // cross
  case question  // question mark
  case attention  // exclamation mark
  case perfect  // star

  /// Default badge color: approve green, reject red, question blue, attention orange, perfect lavender.
  public var defaultColor: AnnotationColor {
    switch self {
    case .approve: return .green
    case .reject: return .red
    case .question: return .blue
    case .attention: return .orange
    case .perfect: return .lavender
    }
  }

  /// Badge radius in document units for a frozen `strokeWidth` (relative 0.6 on a 1000 px image gives 24).
  public static func radius(strokeWidth: Double) -> Double {
    max(strokeWidth, 0) * 4
  }

  /// How far the tail tip extends beyond the badge edge, as a fraction of the radius.
  public static let tailExtension = 0.6
}
