import Foundation

public enum LayerName: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
  case base, mod, fn, mouse, fn2, fn3, fn4, fn5

  public var displayName: String {
    switch self {
    case .base: "Base"
    case .mod: "Mod"
    case .fn: "Fn"
    case .mouse: "Mouse"
    case .fn2: "Fn2"
    case .fn3: "Fn3"
    case .fn4: "Fn4"
    case .fn5: "Fn5"
    }
  }

  public static let switchable: [LayerName] = allCases.filter { $0 != .base }
}

public enum LayerSwitchMode: String, Codable, Sendable, CaseIterable {
  case hold, toggle, holdAndDoubleTapToggle
}
