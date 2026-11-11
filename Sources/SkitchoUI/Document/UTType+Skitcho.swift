import UniformTypeIdentifiers

extension UTType {
  /// The `.skitcho` package type, exported by Info.plist.
  public static let skitchoDocument = UTType(exportedAs: "com.oleggohman.skitcho.document", conformingTo: .package)
}
