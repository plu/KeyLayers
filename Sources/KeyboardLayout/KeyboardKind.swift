/// The physical arrangement of the alphanumeric block, as macOS reports it (`KBGetLayoutType`).
public enum PhysicalLayout: String, CaseIterable, Codable, Sendable {
  case ansi, iso, jis
}

/// The Apple keyboard family.
public enum KeyboardModel: String, CaseIterable, Codable, Sendable {
  /// MacBook built-in keyboard and Magic Keyboard (with Touch ID): function row, inverted-T arrows.
  case compact
  /// Magic Keyboard with (Touch ID and) Numeric Keypad.
  case extended
}

/// One of the keyboard drawings the configurator supports.
public struct KeyboardKind: Hashable, Codable, Sendable, CustomStringConvertible {
  public var model: KeyboardModel
  public var layout: PhysicalLayout

  public init(model: KeyboardModel, layout: PhysicalLayout) {
    self.model = model
    self.layout = layout
  }

  public static let all: [KeyboardKind] = KeyboardModel.allCases.flatMap { model in
    PhysicalLayout.allCases.map { KeyboardKind(model: model, layout: $0) }
  }

  /// Used when no supported Apple keyboard is detected.
  public static let fallback = KeyboardKind(model: .compact, layout: .ansi)

  public var displayName: String {
    let name = switch model {
    case .compact: "MacBook / Magic Keyboard"
    case .extended: "Magic Keyboard with Numeric Keypad"
    }
    return "\(name) (\(layout.rawValue.uppercased()))"
  }

  public var description: String {
    displayName
  }
}
