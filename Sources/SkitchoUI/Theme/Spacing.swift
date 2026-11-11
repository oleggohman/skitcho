import CoreGraphics

/// CloudZone spacing scale (points).
public enum Spacing {
  public static let xxs: CGFloat = 4
  public static let xs: CGFloat = 8
  public static let sm: CGFloat = 16
  public static let md: CGFloat = 24
  public static let lg: CGFloat = 32
  public static let xl: CGFloat = 40
  public static let xxl: CGFloat = 48
  public static let xxxl: CGFloat = 64
  public static let huge: CGFloat = 80
  public static let max: CGFloat = 96

  public static let all: [CGFloat] = [xxs, xs, sm, md, lg, xl, xxl, xxxl, huge, max]
}

/// CloudZone corner radii (points).
public enum Radius {
  public static let tiny: CGFloat = 4
  public static let medium: CGFloat = 16
  public static let large: CGFloat = 20
  public static let pill: CGFloat = 40
}
