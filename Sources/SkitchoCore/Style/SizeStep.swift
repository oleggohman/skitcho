import Foundation

/// The five discrete tool sizes offered in the UI.
public enum SizeStep: Int, Sendable, Equatable, Hashable, CaseIterable, Codable {
  case xs = 1
  case small
  case medium
  case large
  case xl

  public static let `default`: SizeStep = .medium

  /// Relative tool size: 0.2, 0.4, 0.6, 0.8, 1.0.
  public var relative: Double {
    switch self {
    case .xs: return 0.2
    case .small: return 0.4
    case .medium: return 0.6
    case .large: return 0.8
    case .xl: return 1.0
    }
  }

  /// Decoding never fails on an unknown id; it falls back to the default step.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let id = (try? container.decode(Int.self)) ?? SizeStep.default.rawValue
    self = SizeStep(rawValue: id) ?? .default
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
