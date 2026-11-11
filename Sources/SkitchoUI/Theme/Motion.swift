import SwiftUI

/// CloudZone transition durations (seconds). Every transition uses ease-in-out.
public enum Motion {
  public static let instant: TimeInterval = 0.1
  public static let quick: TimeInterval = 0.15
  public static let normal: TimeInterval = 0.25
  public static let slow: TimeInterval = 0.35
  public static let slower: TimeInterval = 0.5

  public static let all: [TimeInterval] = [instant, quick, normal, slow, slower]

  public static func animation(_ duration: TimeInterval = quick) -> Animation {
    .easeInOut(duration: duration)
  }

  /// Opacity of a button hover when a variant has no dedicated hover color.
  public static let hoverFallbackOpacity: Double = 0.75
}
