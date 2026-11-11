import AppKit
import SwiftUI
import Testing

@testable import SkitchoUI

@Suite struct ThemeTests {
  private func rgb(_ color: NSColor, appearance: NSAppearance.Name) -> [Double] {
    var out: [Double] = []
    NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
      let c = color.usingColorSpace(.sRGB)!
      out = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
    }
    return out
  }

  @Test func exactHexValues() {
    let expected: [BrandColor: UInt32] = [
      .blue: 0x2FA8F7, .purple: 0x5D77F9, .pink: 0xAF85F5, .darkBlue: 0x0E1E4D, .mutedBlue: 0x323F68,
      .white: 0xFFFFFF, .black: 0x000000, .ghostGray: 0xE4E5EB, .lightestGray: 0xEDEDED,
      .mutedGray: 0xCED0D9, .lightGray: 0xAAAEBD, .mediumGray: 0x666A80, .darkMutedGray: 0x909090,
      .paleBlue: 0xEEF2FB, .lightestBlue: 0xDFE4FE, .lightBlue: 0xC5D3F4, .mediumBlue: 0x9FB2E8,
      .red: 0xF96C5D, .orange: 0xF8A23A,
    ]
    #expect(expected.count == BrandColor.allCases.count)
    for (token, hex) in expected { #expect(token.hex == hex, "\(token)") }
  }

  @Test func allHexParseToUnitRange() {
    for token in BrandColor.allCases {
      #expect(token.hex <= 0xFFFFFF)
      let c = token.components
      for v in [c.red, c.green, c.blue] { #expect(v >= 0 && v <= 1) }
      #expect(abs(token.nsColor().usingColorSpace(.sRGB)!.redComponent - c.red) < 0.001)
    }
    let blue = BrandColor.blue.components
    #expect(abs(blue.red - 47.0 / 255.0) < 1e-9)
  }

  @Test func semanticAliasesDifferBetweenLightAndDark() {
    let differing: [BrandSemantic] = [.windowBackground, .canvasSurround, .panel, .text]
    for alias in differing {
      #expect(alias.light != alias.dark, "\(alias)")
      let light = rgb(alias.nsColor, appearance: .aqua)
      let dark = rgb(alias.nsColor, appearance: .darkAqua)
      #expect(light != dark, "\(alias)")
    }
    #expect(rgb(BrandSemantic.text.nsColor, appearance: .aqua) == [0, 0, 0])
    #expect(rgb(BrandSemantic.text.nsColor, appearance: .darkAqua) == [1, 1, 1])
  }

  @Test func semanticMappingFollowsDesignSystem() {
    #expect(BrandSemantic.sidebar.light == .darkBlue)
    #expect(BrandSemantic.selectedTool.light == .blue)
    #expect(BrandSemantic.toolHover.light == .purple)
    #expect(BrandSemantic.canvasSurround.light == .paleBlue)
    #expect(BrandSemantic.panel.light == .white)
    #expect(BrandSemantic.panelBorder.light == .ghostGray)
    #expect(BrandSemantic.windowBackground.dark == .darkBlue)
    #expect(BrandSemantic.panel.dark == .mutedBlue)
    #expect(BrandSemantic.caption.dark == .lightGray)
    #expect(BrandSemantic.selectionHandle.light == .blue)
    #expect(BrandSemantic.handleOutline.light == .white)
    #expect(BrandColor.modalDimAlpha == 0.4)
    #expect(abs(BrandColor.modalDim.alphaComponent - 0.4) < 0.001)
  }

  @Test func typographyScaleAndWeights() {
    #expect(Typography.allCases.map(\.size) == [10, 12, 14, 15, 16, 20, 40])
    #expect(Typography.body.defaultWeight == .medium)
    #expect(Typography.Weight.allCases.map(\.rawValue) == [400, 500, 600])
  }

  @Test func typographyResolvesToSystemFont() {
    let system = NSFont.systemFont(ofSize: 13)
    for token in Typography.allCases {
      for weight in Typography.Weight.allCases {
        let font = token.nsFont(weight: weight)
        #expect(font.pointSize == token.size)
        #expect(font.familyName == system.familyName)
      }
    }
    let semibold = Typography.title.nsFont(weight: .semibold)
    let regular = Typography.title.nsFont(weight: .regular)
    #expect(semibold.fontDescriptor.postscriptName != regular.fontDescriptor.postscriptName)
    // The default weight is medium.
    let defaultName = Typography.body.nsFont().fontDescriptor.postscriptName
    #expect(defaultName == Typography.body.nsFont(weight: .medium).fontDescriptor.postscriptName)
  }

  @Test func spacingRadiusAndMotionTokens() {
    #expect(Spacing.all == [4, 8, 16, 24, 32, 40, 48, 64, 80, 96])
    #expect([Radius.tiny, Radius.medium, Radius.large, Radius.pill] == [4, 16, 20, 40])
    #expect(Motion.all == [0.1, 0.15, 0.25, 0.35, 0.5])
    #expect(Motion.hoverFallbackOpacity == 0.75)
  }

  @Test func buttonSizesAndColors() {
    #expect(CZButtonStyle.Size.small.minHeight == 24)
    #expect(CZButtonStyle.Size.small.cornerRadius == 16)
    #expect(CZButtonStyle.Size.normal.minHeight == 38)
    #expect(CZButtonStyle.Size.normal.cornerRadius == 40)

    typealias S = CZButtonStyle
    #expect(S.background(.primary, hovering: false, enabled: true) == .blue)
    #expect(S.background(.primary, hovering: true, enabled: true) == .purple)
    #expect(S.foreground(.primary, hovering: false, enabled: true) == .white)
    #expect(S.background(.secondary, hovering: false, enabled: true) == .paleBlue)
    #expect(S.background(.secondary, hovering: true, enabled: true) == .lightBlue)
    #expect(S.background(.transparent, hovering: true, enabled: true) == nil)
    #expect(S.background(.link, hovering: false, enabled: true) == nil)
    #expect(S.foreground(.link, hovering: false, enabled: true) == .purple)
    for variant in [S.Variant.primary, .secondary] {
      #expect(S.background(variant, hovering: true, enabled: false) == .mutedGray)
    }
  }

  @Test func cardMetrics() {
    #expect(CZCard<EmptyView>.borderWidth == 2)
    #expect(CZCard<EmptyView>.padding(compact: false) == 32)
    #expect(CZCard<EmptyView>.padding(compact: true) == 24)
  }
}
