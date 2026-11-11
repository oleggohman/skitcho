import AppKit
import SkitchoCore
import SwiftUI
import UniformTypeIdentifiers

import struct SkitchoCore.Document

/// State of the Export As… accessory: format, JPEG quality and Retina 2x. The last choice is kept in
/// `UserDefaults` (a private suite in tests, never `.standard`).
@MainActor @Observable
public final class ExportAccessoryModel {
  public enum Kind: String, CaseIterable, Sendable {
    case png, jpeg, tiff

    public var title: String {
      switch self {
      case .png: "PNG"
      case .jpeg: "JPEG"
      case .tiff: "TIFF"
      }
    }

    public var contentType: UTType {
      switch self {
      case .png: .png
      case .jpeg: .jpeg
      case .tiff: .tiff
      }
    }

    public var fileExtension: String {
      switch self {
      case .png: "png"
      case .jpeg: "jpg"
      case .tiff: "tiff"
      }
    }
  }

  enum Key {
    static let kind = "export.format"
    static let quality = "export.jpegQuality"
    static let retina = "export.retina"
  }

  public static let defaultQuality = 0.85

  @ObservationIgnored private let defaults: UserDefaults

  public var kind: Kind { didSet { defaults.set(kind.rawValue, forKey: Key.kind) } }
  /// JPEG quality in 0...1.
  public var jpegQuality: Double { didSet { defaults.set(jpegQuality, forKey: Key.quality) } }
  public var retina: Bool { didSet { defaults.set(retina, forKey: Key.retina) } }

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    kind = defaults.string(forKey: Key.kind).flatMap(Kind.init(rawValue:)) ?? .png
    let quality = defaults.object(forKey: Key.quality) as? Double ?? Self.defaultQuality
    jpegQuality = min(1, max(0, quality))
    retina = defaults.bool(forKey: Key.retina)
  }

  public var format: ExportFormat {
    switch kind {
    case .png: .png
    case .jpeg: .jpeg(quality: jpegQuality)
    case .tiff: .tiff
    }
  }

  public var scale: Int { retina ? 2 : 1 }

  /// `name` with the extension of the selected format (an existing known extension is replaced).
  public func fileName(for name: String) -> String {
    let known = Kind.allCases.flatMap { [$0.fileExtension] } + ["jpeg", "tif"]
    let ext = (name as NSString).pathExtension.lowercased()
    let base = known.contains(ext) ? (name as NSString).deletingPathExtension : name
    return base + "." + kind.fileExtension
  }
}

/// The accessory shown in the save panel.
struct ExportAccessoryView: View {
  @Bindable var model: ExportAccessoryModel

  var body: some View {
    CZCard(compact: true) {
      Picker("Format", selection: $model.kind) {
        ForEach(ExportAccessoryModel.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      if model.kind == .jpeg {
        HStack(spacing: Spacing.xs) {
          Text("Quality")
          Slider(value: $model.jpegQuality, in: 0.1...1)
          Text("\(Int((model.jpegQuality * 100).rounded()))%")
            .monospacedDigit()
            .frame(minWidth: 40, alignment: .trailing)
        }
      }
      Toggle("Retina (2×)", isOn: $model.retina)
    }
    .frame(width: 320)
    .padding(Spacing.xs)
  }
}

/// Runs the Export As… save panel for a document.
@MainActor
public enum ExportPresenter {
  /// Presents the panel as a sheet on `window` (or modally without one) and writes the file on confirm.
  /// `onError` receives a failure message.
  public static func present(
    document: @escaping () -> Document, suggestedName: String, window: NSWindow?,
    model: ExportAccessoryModel = ExportAccessoryModel(), onError: @escaping (String) -> Void
  ) {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.allowedContentTypes = [model.kind.contentType]
    panel.nameFieldStringValue = model.fileName(for: suggestedName)
    let host = NSHostingView(rootView: ExportAccessoryView(model: model))
    host.setFrameSize(host.fittingSize)
    panel.accessoryView = host

    // The file extension follows the chosen format.
    var observed = model.kind
    let timer = Timer(timeInterval: 0.15, repeats: true) { _ in
      MainActor.assumeIsolated {
        guard model.kind != observed else { return }
        observed = model.kind
        panel.allowedContentTypes = [model.kind.contentType]
        panel.nameFieldStringValue = model.fileName(for: panel.nameFieldStringValue)
        host.setFrameSize(host.fittingSize)
      }
    }
    RunLoop.main.add(timer, forMode: .common)

    let finish: (NSApplication.ModalResponse) -> Void = { response in
      timer.invalidate()
      guard response == .OK, let url = panel.url else { return }
      do {
        let data = try Exporter.data(document(), format: model.format, scale: model.scale)
        try data.write(to: url, options: .atomic)
      } catch {
        onError("Export failed: \(error.localizedDescription)")
      }
    }
    if let window {
      panel.beginSheetModal(for: window, completionHandler: finish)
    } else {
      finish(panel.runModal())
    }
  }
}
