import Foundation

public enum SecondaryRole: Equatable, Hashable, Sendable, Codable {
  case layer(LayerName)
  case modifier(Modifier)

  private enum CodingKeys: String, CodingKey { case type, layer, modifier }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    switch try c.decode(String.self, forKey: .type) {
    case "layer": self = try .layer(c.decode(LayerName.self, forKey: .layer))
    case "modifier": self = try .modifier(c.decode(Modifier.self, forKey: .modifier))
    case let other:
      throw DecodingError.dataCorruptedError(
        forKey: .type, in: c, debugDescription: "Unknown secondary role type \"\(other)\""
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .layer(layer):
      try c.encode("layer", forKey: .type)
      try c.encode(layer, forKey: .layer)
    case let .modifier(modifier):
      try c.encode("modifier", forKey: .type)
      try c.encode(modifier, forKey: .modifier)
    }
  }
}

public struct Keypress: Equatable, Hashable, Sendable, Codable {
  public var key: KeyID?
  public var modifiers: Modifiers
  public var secondaryRole: SecondaryRole?

  public init(key: KeyID?, modifiers: Modifiers, secondaryRole: SecondaryRole? = nil) {
    self.key = key
    self.modifiers = modifiers
    self.secondaryRole = secondaryRole
  }
}

public enum KeyAction: Equatable, Hashable, Sendable, Codable {
  case keypress(Keypress)
  case switchLayer(LayerName, mode: LayerSwitchMode)
  case switchKeymap(Keymap.ID)
  case block
  /// An action type this version does not understand; preserved as `{"type": ...}`.
  case unsupported(type: String)

  private enum CodingKeys: String, CodingKey {
    case type, key, modifiers, secondaryRole, layer, mode, keymapID
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let type = try c.decode(String.self, forKey: .type)
    switch type {
    case "keypress":
      self = try .keypress(Keypress(
        key: c.decodeIfPresent(KeyID.self, forKey: .key),
        modifiers: c.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? [],
        secondaryRole: c.decodeIfPresent(SecondaryRole.self, forKey: .secondaryRole)
      ))
    case "switchLayer":
      self = try .switchLayer(
        c.decode(LayerName.self, forKey: .layer),
        mode: c.decode(LayerSwitchMode.self, forKey: .mode)
      )
    case "switchKeymap":
      self = try .switchKeymap(c.decode(Keymap.ID.self, forKey: .keymapID))
    case "block":
      self = .block
    default:
      self = .unsupported(type: type)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .keypress(press):
      try c.encode("keypress", forKey: .type)
      try c.encodeIfPresent(press.key, forKey: .key)
      try c.encode(press.modifiers, forKey: .modifiers)
      try c.encodeIfPresent(press.secondaryRole, forKey: .secondaryRole)
    case let .switchLayer(layer, mode):
      try c.encode("switchLayer", forKey: .type)
      try c.encode(layer, forKey: .layer)
      try c.encode(mode, forKey: .mode)
    case let .switchKeymap(id):
      try c.encode("switchKeymap", forKey: .type)
      try c.encode(id, forKey: .keymapID)
    case .block:
      try c.encode("block", forKey: .type)
    case let .unsupported(type):
      try c.encode(type, forKey: .type)
    }
  }
}
