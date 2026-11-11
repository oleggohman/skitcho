import CoreGraphics
import Foundation
import Testing

@testable import SkitchoCore

@Suite struct StyleTests {
  @Test func paletteTable() {
    #expect(AnnotationColor.red.rgba == RGBA(hex: 0xF96C5D))
    #expect(AnnotationColor.yellow.rgba == RGBA(hex: 0xFFD60A))
    #expect(AnnotationColor.green.rgba == RGBA(hex: 0x34C759))
    #expect(AnnotationColor.white.rgba == RGBA(red: 1, green: 1, blue: 1))
    #expect(AnnotationColor.black.rgba == RGBA(red: 0, green: 0, blue: 0))
    #expect(abs(AnnotationColor.navy.rgba.blue - 0x4D / 255.0) < 1e-9)
    #expect(AnnotationColor.presets.count == 10)
  }

  @Test func cgColorMatchesRGBA() {
    let color = AnnotationColor.blue.cgColor
    let comps = color.components ?? []
    #expect(comps.count == 4)
    #expect(abs(comps[0] - 0x2F / 255.0) < 1e-6)
    #expect(abs(comps[1] - 0xA8 / 255.0) < 1e-6)
    #expect(abs(comps[2] - 0xF7 / 255.0) < 1e-6)
    #expect(color.colorSpace?.name == CGColorSpace.sRGB)
  }

  @Test func luminanceAndContrast() {
    #expect(AnnotationColor.black.luminance == 0)
    #expect(abs(AnnotationColor.white.luminance - 1) < 1e-9)
    #expect(AnnotationColor.white.contrastingOutline == .black)
    #expect(AnnotationColor.yellow.contrastingOutline == .black)
    #expect(AnnotationColor.black.contrastingOutline == .white)
    #expect(AnnotationColor.navy.contrastingOutline == .white)
  }

  @Test func sizeStepTable() {
    let values = SizeStep.allCases.map(\.relative)
    #expect(values.count == 5)
    for (value, expected) in zip(values, [0.2, 0.4, 0.6, 0.8, 1.0]) {
      #expect(abs(value - expected) < 1e-9)
    }
    #expect(SizeStep.default.relative == 0.6)
  }

  @Test(arguments: [
    (CGSize(width: 400, height: 300), 1.0),
    (CGSize(width: 1000, height: 1000), 1.0),
    (CGSize(width: 4000, height: 2000), 2.0),
    (CGSize(width: 8000, height: 6000), 6.0),
  ])
  func freezingFormula(size: CGSize, scale: Double) {
    let style = Style.make(tool: .arrow, sizeStep: .large, imageSize: size)
    #expect(abs(style.strokeWidth - 0.8 * 10 * scale) < 1e-9)
    #expect(abs(style.fontSize - 0.8 * 48 * scale) < 1e-9)
    let highlighter = Style.make(tool: .highlighter, sizeStep: .xl, imageSize: size)
    #expect(abs(highlighter.strokeWidth - 28 * scale) < 1e-9)
  }

  @Test func perToolDefaults() {
    let size = CGSize(width: 800, height: 600)
    #expect(Style.make(tool: .highlighter, imageSize: size).color == .yellow)
    #expect(Style.make(tool: .arrow, imageSize: size).color == .red)
    #expect(Style.make(tool: .arrow, imageSize: size).sizeStep == .medium)
    #expect(Style.make(tool: .text, color: .blue, imageSize: size).color == .blue)
  }

  @Test func scaledMultipliesAbsoluteSizes() {
    let style = Style.make(tool: .rect, imageSize: CGSize(width: 1000, height: 1000)).scaled(by: 0.5)
    #expect(abs(style.strokeWidth - 3) < 1e-9)
    #expect(abs(style.fontSize - 14.4) < 1e-9)
  }

  @Test func codableRoundTrip() throws {
    let style = Style.make(
      tool: .text, sizeStep: .small, color: .custom(RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.5)),
      imageSize: CGSize(width: 2000, height: 1500))
    let data = try JSONEncoder().encode(style)
    #expect(try JSONDecoder().decode(Style.self, from: data) == style)
    for color in AnnotationColor.presets {
      let encoded = try JSONEncoder().encode(color)
      #expect(try JSONDecoder().decode(AnnotationColor.self, from: encoded) == color)
    }
  }

  @Test func customColorClamps() throws {
    let color = RGBA(red: -1, green: 2, blue: .nan, alpha: 5)
    #expect(color == RGBA(red: 0, green: 1, blue: 0, alpha: 1))
    let json = Data(#"{"red":3,"green":-2,"blue":0.5}"#.utf8)
    let decoded = try JSONDecoder().decode(RGBA.self, from: json)
    #expect(decoded == RGBA(red: 1, green: 0, blue: 0.5, alpha: 1))
    #expect(AnnotationColor.custom(color).cgColor.alpha == 1)
  }

  @Test func unknownSizeIdDecodesToDefault() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(SizeStep.self, from: Data("99".utf8)) == .default)
    #expect(try decoder.decode(SizeStep.self, from: Data("0".utf8)) == .default)
    #expect(try decoder.decode(SizeStep.self, from: Data(#""huge""#.utf8)) == .default)
    #expect(try decoder.decode(SizeStep.self, from: Data("5".utf8)) == .xl)
  }
}
