import AppKit
import SwiftUI

/// CloudZone design-system palette for the app chrome. This file and `AnnotationColor.swift` are the only
/// places where hex literals are allowed.
public enum BrandColor: String, CaseIterable, Sendable {
  case blue, purple, pink, darkBlue, mutedBlue, white, black
  case ghostGray, lightestGray, mutedGray, lightGray, mediumGray, darkMutedGray
  case paleBlue, lightestBlue, lightBlue, mediumBlue
  case red, orange

  /// 24-bit 0xRRGGBB value of the token.
  public var hex: UInt32 {
    switch self {
    case .blue: 0x2FA8F7
    case .purple: 0x5D77F9
    case .pink: 0xAF85F5
    case .darkBlue: 0x0E1E4D
    case .mutedBlue: 0x323F68
    case .white: 0xFFFFFF
    case .black: 0x000000
    case .ghostGray: 0xE4E5EB
    case .lightestGray: 0xEDEDED
    case .mutedGray: 0xCED0D9
    case .lightGray: 0xAAAEBD
    case .mediumGray: 0x666A80
    case .darkMutedGray: 0x909090
    case .paleBlue: 0xEEF2FB
    case .lightestBlue: 0xDFE4FE
    case .lightBlue: 0xC5D3F4
    case .mediumBlue: 0x9FB2E8
    case .red: 0xF96C5D
    case .orange: 0xF8A23A
    }
  }

  /// sRGB components in 0...1.
  public var components: (red: Double, green: Double, blue: Double) {
    (
      Double((hex >> 16) & 0xFF) / 255,
      Double((hex >> 8) & 0xFF) / 255,
      Double(hex & 0xFF) / 255
    )
  }

  public func nsColor(alpha: Double = 1) -> NSColor {
    let c = components
    return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: alpha)
  }

  public var color: Color { Color(nsColor: nsColor()) }

  /// Dim drawn over the canvas behind crop and other modal overlays (black at 0.4).
  public static let modalDimAlpha: Double = 0.4
  public static var modalDim: NSColor { BrandColor.black.nsColor(alpha: modalDimAlpha) }
}

/// Semantic aliases that resolve per appearance (light/dark).
public enum BrandSemantic: CaseIterable, Sendable {
  case windowBackground
  /// Tool palette sidebar.
  case sidebar
  /// Icons on the sidebar.
  case sidebarIcon
  case selectedTool
  case toolHover
  /// Surface around the canvas.
  case canvasSurround
  case panel
  case panelBorder
  case text
  case caption
  case selectionHandle
  case handleOutline

  public var light: BrandColor {
    switch self {
    case .windowBackground: .white
    case .sidebar: .darkBlue
    case .sidebarIcon: .white
    case .selectedTool: .blue
    case .toolHover: .purple
    case .canvasSurround: .paleBlue
    case .panel: .white
    case .panelBorder: .ghostGray
    case .text: .black
    case .caption: .lightGray
    case .selectionHandle: .blue
    case .handleOutline: .white
    }
  }

  public var dark: BrandColor {
    switch self {
    case .windowBackground: .darkBlue
    case .sidebar: .darkBlue
    case .sidebarIcon: .white
    case .selectedTool: .blue
    case .toolHover: .purple
    case .canvasSurround: .mutedBlue
    case .panel: .mutedBlue
    case .panelBorder: .mutedBlue
    case .text: .white
    case .caption: .lightGray
    case .selectionHandle: .blue
    case .handleOutline: .white
    }
  }

  /// Appearance-dependent color.
  public var nsColor: NSColor {
    let light = self.light
    let dark = self.dark
    return NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      return (isDark ? dark : light).nsColor()
    }
  }

  public var color: Color { Color(nsColor: nsColor) }

  /// Resolves the alias for an explicit appearance.
  public func resolved(dark isDark: Bool) -> BrandColor { isDark ? dark : light }
}
