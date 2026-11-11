// Standalone dev tool: renders the Skitcho app icon and writes an .icns.
// Usage: swift scripts/app-icon.swift <out.icns>
// Original artwork: a darkBlue squircle with a bold blue-to-lavender gradient arrow.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Hex values mirror the BrandColor tokens (darkBlue, blue, lavender) in Sources/.
let darkBlue = (r: 0x0e, g: 0x1e, b: 0x4d)
let blue = (r: 0x2f, g: 0xa8, b: 0xf7)
let lavender = (r: 0xaf, g: 0x85, b: 0xf5)

func color(_ c: (r: Int, g: Int, b: Int), _ space: CGColorSpace) -> CGColor {
  CGColor(
    colorSpace: space,
    components: [CGFloat(c.r) / 255, CGFloat(c.g) / 255, CGFloat(c.b) / 255, 1])!
}

/// Superellipse approximating the macOS squircle, centered in `rect`.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
  let path = CGMutablePath()
  let steps = 360
  let a = rect.width / 2
  let b = rect.height / 2
  for i in 0...steps {
    let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
    let c = cos(t)
    let s = sin(t)
    let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
    let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
  }
  path.closeSubpath()
  return path
}

/// Bold arrow pointing up-right, in a 1024-unit canvas.
func arrowPath() -> CGPath {
  // Built pointing right around the origin, then rotated 45 degrees and centered.
  let shaftHalf: CGFloat = 62
  let tail: CGFloat = -250
  let neck: CGFloat = 40
  let headHalf: CGFloat = 170
  let tip: CGFloat = 290
  let p = CGMutablePath()
  p.move(to: CGPoint(x: tail, y: -shaftHalf))
  p.addLine(to: CGPoint(x: neck, y: -shaftHalf))
  p.addLine(to: CGPoint(x: neck, y: -headHalf))
  p.addLine(to: CGPoint(x: tip, y: 0))
  p.addLine(to: CGPoint(x: neck, y: headHalf))
  p.addLine(to: CGPoint(x: neck, y: shaftHalf))
  p.addLine(to: CGPoint(x: tail, y: shaftHalf))
  p.closeSubpath()
  var t = CGAffineTransform(translationX: 512, y: 512).rotated(by: .pi / 4)
  return p.copy(using: &t)!
}

func render(pixels: Int) -> CGImage {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let ctx = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high
  ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

  // Standard macOS grid: 824 pt body inside the 1024 pt canvas (~10% transparent margin).
  let body = CGRect(x: 100, y: 100, width: 824, height: 824)
  ctx.saveGState()
  ctx.setShadow(
    offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
  ctx.addPath(squircle(in: body))
  ctx.setFillColor(color(darkBlue, space))
  ctx.fillPath()
  ctx.restoreGState()

  ctx.saveGState()
  ctx.addPath(arrowPath())
  ctx.clip()
  let gradient = CGGradient(
    colorsSpace: space, colors: [color(blue, space), color(lavender, space)] as CFArray,
    locations: [0, 1])!
  ctx.drawLinearGradient(
    gradient, start: CGPoint(x: 280, y: 280), end: CGPoint(x: 760, y: 760), options: [])
  ctx.restoreGState()
  return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
  let dest = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, image, nil)
  guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("error: cannot write \(url.path)\n".utf8))
    exit(1)
  }
}

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: swift scripts/app-icon.swift <out.icns>\n".utf8))
  exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
let tmp = fm.temporaryDirectory.appendingPathComponent("skitcho-icon-\(UUID().uuidString)")
let iconset = tmp.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: tmp) }

for base in [16, 32, 128, 256, 512] {
  writePNG(render(pixels: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
  writePNG(
    render(pixels: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
print("wrote \(out.path)")
